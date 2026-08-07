@preconcurrency import CoreMotion
import Foundation
import simd

// MARK: - Readings

/// One attitude reading.
struct AttitudeSample: Sendable {
    let orientation: simd_quatf
    let timestamp: TimeInterval

    /// A reading that will not change. The reflection model skips its filter and
    /// its ramp for these, so a preview lands on exactly the requested angle
    /// instead of easing toward it across several frames.
    var isDeterministic = false
}

/// Where a surface gets its attitude readings.
///
/// A protocol because neither a test nor an Xcode preview has motion hardware,
/// and the material has to be reviewable in both.
@MainActor
protocol AttitudeSource: AnyObject {
    var sampleHandler: ((AttitudeSample) -> Void)? { get set }

    /// Called when readings stop and will not resume. The model returns the
    /// light to rest.
    var failureHandler: (() -> Void)? { get set }

    func start()
    func stop()
}

enum AttitudeTiming {
    /// 30 Hz. The reflection is smoothed by a time constant rather than by a
    /// sample count, so this rate sets cost, not feel. Raising it spends battery
    /// and changes nothing a viewer can see.
    static let updateInterval: TimeInterval = 1.0 / 30.0
}

// MARK: - A held angle

/// Emits one unchanging attitude, for previews, screenshots and tests.
///
/// It keeps emitting rather than firing once. A phone held still goes on
/// delivering readings, and the model's resting reference only advances when one
/// arrives, so a single sample freezes the surface mid-lean with no way to
/// settle.
@MainActor
final class FixedAttitudeSource: AttitudeSource {
    var sampleHandler: ((AttitudeSample) -> Void)?
    var failureHandler: (() -> Void)?

    private let orientation: simd_quatf
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - pitch: Degrees about the device's x axis. Positive tips the top edge
    ///     away from the viewer.
    ///   - roll: Degrees about the device's y axis. Positive tips the right edge
    ///     away.
    init(pitch: Double, roll: Double) {
        let radians = Float.pi / 180
        orientation =
            simd_quatf(angle: Float(pitch) * radians, axis: SIMD3(1, 0, 0))
            * simd_quatf(angle: Float(roll) * radians, axis: SIMD3(0, 1, 0))
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard task == nil else { return }

        emit()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AttitudeTiming.updateInterval))
                guard !Task.isCancelled else { break }
                self?.emit()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func emit() {
        sampleHandler?(
            AttitudeSample(
                orientation: orientation,
                timestamp: ProcessInfo.processInfo.systemUptime,
                isDeterministic: true
            )
        )
    }
}

// MARK: - Device motion, shared

/// The hardware behind `SharedDeviceMotion`.
///
/// A protocol so the sharing and the reference counting can be tested. The
/// Simulator reports no device motion, which is where those tests run.
@MainActor
protocol MotionDriver: AnyObject {
    var isAvailable: Bool { get }

    /// `nil` means readings failed and will not resume.
    func start(interval: TimeInterval, handler: @escaping (AttitudeSample?) -> Void)
    func stop()
}

@MainActor
final class CoreMotionDriver: MotionDriver {
    private let manager = CMMotionManager()

    var isAvailable: Bool {
        manager.isDeviceMotionAvailable
            && CMMotionManager.availableAttitudeReferenceFrames()
                .contains(.xArbitraryZVertical)
    }

    deinit {
        // Core Motion keeps streaming, and burning power, until told to stop.
        // CMMotionManager is thread safe, so this is legal here.
        manager.stopDeviceMotionUpdates()
    }

    func start(interval: TimeInterval, handler: @escaping (AttitudeSample?) -> Void) {
        guard !manager.isDeviceMotionActive else { return }

        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: .main
        ) { [weak self] motion, error in
            MainActor.assumeIsolated {
                guard error == nil, let motion else {
                    self?.manager.stopDeviceMotionUpdates()
                    handler(nil)
                    return
                }

                let q = motion.attitude.quaternion
                handler(
                    AttitudeSample(
                        orientation: simd_quatf(
                            ix: Float(q.x),
                            iy: Float(q.y),
                            iz: Float(q.z),
                            r: Float(q.w)
                        ),
                        timestamp: motion.timestamp
                    )
                )
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

/// The process's one motion reader.
///
/// Every surface subscribes here instead of starting its own reader. Two readers
/// spend twice the battery and can report attitudes from different instants,
/// which lights two surfaces differently in the same frame.
@MainActor
final class SharedDeviceMotion {
    static let shared = SharedDeviceMotion(driver: CoreMotionDriver())

    private let driver: any MotionDriver
    private var subscribers: [ObjectIdentifier: WeakSubscriber] = [:]
    private(set) var isRunning = false

    private struct WeakSubscriber {
        weak var value: DeviceMotionAttitudeSource?
    }

    init(driver: any MotionDriver) {
        self.driver = driver
    }

    /// How many surfaces are reading. Reference count for the driver.
    var subscriberCount: Int { subscribers.count }

    func add(_ subscriber: DeviceMotionAttitudeSource) {
        subscribers[ObjectIdentifier(subscriber)] = WeakSubscriber(value: subscriber)

        guard !isRunning, driver.isAvailable else { return }
        isRunning = true
        driver.start(interval: AttitudeTiming.updateInterval) { [weak self] sample in
            self?.deliver(sample)
        }
    }

    func remove(_ subscriber: DeviceMotionAttitudeSource) {
        subscribers[ObjectIdentifier(subscriber)] = nil
        stopIfIdle()
    }

    private func deliver(_ sample: AttitudeSample?) {
        // Prune before delivering. A surface can leave the hierarchy and be
        // released before it unsubscribes, and the driver has to stop once the
        // last one goes rather than stream to nobody.
        subscribers = subscribers.filter { $0.value.value != nil }
        guard stopIfIdle() == false else { return }

        for entry in subscribers.values {
            entry.value?.receive(sample)
        }
    }

    /// Returns whether it stopped.
    @discardableResult
    private func stopIfIdle() -> Bool {
        guard subscribers.isEmpty, isRunning else { return false }
        isRunning = false
        driver.stop()
        return true
    }
}

/// One surface's view of the shared reader.
///
/// Holds no hardware. `SharedDeviceMotion` keeps only a weak reference to this,
/// so forgetting to call `stop()` costs one sample interval rather than leaking
/// a reader.
@MainActor
final class DeviceMotionAttitudeSource: AttitudeSource {
    var sampleHandler: ((AttitudeSample) -> Void)?
    var failureHandler: (() -> Void)?

    private let hub: SharedDeviceMotion

    init(hub: SharedDeviceMotion = .shared) {
        self.hub = hub
    }

    func start() {
        hub.add(self)
    }

    func stop() {
        hub.remove(self)
    }

    func receive(_ sample: AttitudeSample?) {
        guard let sample else {
            failureHandler?()
            return
        }
        sampleHandler?(sample)
    }
}
