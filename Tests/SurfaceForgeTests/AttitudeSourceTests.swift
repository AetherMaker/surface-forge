import Foundation
import Testing
import simd

@testable import SurfaceForge

/// Counts what the real driver would do to the hardware, without any.
@MainActor
private final class StubDriver: MotionDriver {
    var isAvailable = true
    var startCount = 0
    var stopCount = 0
    private var handler: ((AttitudeSample?) -> Void)?

    func start(interval: TimeInterval, handler: @escaping (AttitudeSample?) -> Void) {
        startCount += 1
        self.handler = handler
    }

    func stop() {
        stopCount += 1
        handler = nil
    }

    func send(_ sample: AttitudeSample?) {
        handler?(sample)
    }
}

private func sample(pitch: Float) -> AttitudeSample {
    AttitudeSample(
        orientation: simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0)),
        timestamp: 0
    )
}

@MainActor
@Suite("Shared device motion")
struct SharedDeviceMotionTests {
    @Test("Ten surfaces start one reader")
    func tenSurfacesStartOneReader() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        let sources = (0..<10).map { _ in DeviceMotionAttitudeSource(hub: hub) }
        for source in sources { source.start() }

        #expect(hub.subscriberCount == 10)
        #expect(driver.startCount == 1)
    }

    @Test("The reader stops only when the last surface stops")
    func readerStopsWithTheLastSurface() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        let first = DeviceMotionAttitudeSource(hub: hub)
        let second = DeviceMotionAttitudeSource(hub: hub)
        first.start()
        second.start()

        first.stop()
        #expect(hub.isRunning)
        #expect(driver.stopCount == 0)

        second.stop()
        #expect(hub.isRunning == false)
        #expect(driver.stopCount == 1)
    }

    @Test("Restarting after idle starts the reader again")
    func restartingStartsTheReaderAgain() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        let source = DeviceMotionAttitudeSource(hub: hub)
        source.start()
        source.stop()
        source.start()

        #expect(driver.startCount == 2)
        #expect(hub.isRunning)
    }

    @Test("Every surface sees the same reading")
    func everySurfaceSeesTheSameReading() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        var seen: [Float] = []
        let sources = (0..<3).map { _ in DeviceMotionAttitudeSource(hub: hub) }
        for source in sources {
            source.sampleHandler = { seen.append($0.orientation.angle) }
            source.start()
        }

        driver.send(sample(pitch: 0.5))

        #expect(seen.count == 3)
        #expect(seen.allSatisfy { abs($0 - 0.5) < 1e-6 })
    }

    @Test("A released surface stops counting, and the reader stops with it")
    func releasedSurfaceStopsTheReader() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        do {
            let source = DeviceMotionAttitudeSource(hub: hub)
            source.start()
            #expect(hub.subscriberCount == 1)
        }

        // The hub holds subscribers weakly, so the released surface is pruned on
        // the next reading rather than leaking a running reader.
        driver.send(sample(pitch: 0.1))

        #expect(hub.subscriberCount == 0)
        #expect(hub.isRunning == false)
        #expect(driver.stopCount == 1)
    }

    @Test("A failed reading reaches every surface as a failure")
    func failureReachesEverySurface() {
        let driver = StubDriver()
        let hub = SharedDeviceMotion(driver: driver)

        var failures = 0
        let sources = (0..<2).map { _ in DeviceMotionAttitudeSource(hub: hub) }
        for source in sources {
            source.failureHandler = { failures += 1 }
            source.start()
        }

        driver.send(nil)

        #expect(failures == 2)
    }

    @Test("No reader starts when the device reports no motion")
    func noReaderWithoutMotion() {
        let driver = StubDriver()
        driver.isAvailable = false
        let hub = SharedDeviceMotion(driver: driver)

        DeviceMotionAttitudeSource(hub: hub).start()

        #expect(driver.startCount == 0)
        #expect(hub.isRunning == false)
    }
}

@MainActor
@Suite("A held angle")
struct FixedAttitudeSourceTests {
    /// Rotating the outward normal is the check that matters. Comparing
    /// quaternion components would only restate how the source builds one.
    private func normal(pitch: Double, roll: Double) -> SIMD3<Float> {
        var seen = SIMD3<Float>.zero
        let source = FixedAttitudeSource(pitch: pitch, roll: roll)
        source.sampleHandler = { seen = $0.orientation.act(SIMD3(0, 0, 1)) }
        source.start()
        source.stop()
        return seen
    }

    @Test("Roll turns the surface about the vertical")
    func rollTurnsAboutTheVertical() {
        let n = normal(pitch: 0, roll: 90)
        #expect(abs(n.x - 1) < 1e-5)
        #expect(abs(n.y) < 1e-5)
        #expect(abs(n.z) < 1e-5)
    }

    @Test("Pitch tips the surface about the horizontal")
    func pitchTipsAboutTheHorizontal() {
        let n = normal(pitch: 90, roll: 0)
        #expect(abs(n.x) < 1e-5)
        #expect(abs(n.y + 1) < 1e-5)
        #expect(abs(n.z) < 1e-5)
    }

    @Test("Zero degrees faces the viewer")
    func zeroFacesTheViewer() {
        let n = normal(pitch: 0, roll: 0)
        #expect(abs(n.z - 1) < 1e-5)
    }

    @Test("Readings are marked deterministic, so the model skips its filter")
    func readingsAreDeterministic() {
        var seen: AttitudeSample?
        let source = FixedAttitudeSource(pitch: 10, roll: 10)
        source.sampleHandler = { seen = $0 }
        source.start()
        source.stop()

        #expect(seen?.isDeterministic == true)
    }

    @Test("A reading arrives before the first interval elapses")
    func firstReadingIsImmediate() {
        var count = 0
        let source = FixedAttitudeSource(pitch: 0, roll: 0)
        source.sampleHandler = { _ in count += 1 }
        source.start()
        source.stop()

        #expect(count == 1)
    }
}

@MainActor
@Suite("Tilt source selection")
struct SurfaceTiltSourceTests {
    @Test("Device motion builds a shared reader, not its own")
    func deviceMotionSharesTheReader() {
        #expect(
            SurfaceTiltSource.deviceMotion.makeAttitudeSource()
                is DeviceMotionAttitudeSource
        )
    }

    @Test("A fixed angle builds a held source")
    func fixedBuildsAHeldSource() {
        #expect(
            SurfaceTiltSource.fixed(pitch: 1, roll: 2).makeAttitudeSource()
                is FixedAttitudeSource
        )
    }
}
