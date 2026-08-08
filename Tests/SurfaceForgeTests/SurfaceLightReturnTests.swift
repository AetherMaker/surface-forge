import Foundation
import Testing
import simd

@testable import SurfaceForge

/// Drives the model by hand so the light's return can be stepped through in
/// simulated time rather than waited out.
@MainActor
private final class Driver {
    let model: SurfaceReflectionModel
    private let source = Source()
    private var time = 1.0

    private final class Source: SurfaceAttitudeSource {
        var sampleHandler: ((SurfaceAttitudeSample) -> Void)?
        var failureHandler: (() -> Void)?
        func start() {}
        func stop() {}
        func send(_ sample: SurfaceAttitudeSample) { sampleHandler?(sample) }
    }

    init() {
        model = SurfaceReflectionModel(source: source)
        model.setActive(true)
    }

    /// Holds one attitude for a span of simulated seconds at 30 Hz.
    func hold(roll: Float, seconds: Double) {
        for _ in 0..<Int(seconds * 30) {
            time += 1.0 / 30
            source.send(
                SurfaceAttitudeSample(
                    orientation: simd_quatf(angle: roll, axis: SIMD3(0, 1, 0)),
                    timestamp: time
                )
            )
        }
    }

    /// Turns steadily from one angle to another, so the activation gate sees real
    /// movement rather than a jump.
    func turn(from start: Float, to end: Float, seconds: Double) {
        let steps = Int(seconds * 30)
        for i in 1...steps {
            time += 1.0 / 30
            let roll = start + (end - start) * Float(i) / Float(steps)
            source.send(
                SurfaceAttitudeSample(
                    orientation: simd_quatf(angle: roll, axis: SIMD3(0, 1, 0)),
                    timestamp: time
                )
            )
        }
    }

    var driftFromRest: Float {
        simd_distance(model.keyDirection, SurfaceShading.neutralKeyDirection)
    }
}

@MainActor
@Suite("The light comes home")
struct SurfaceLightReturnTests {
    @Test("Holding still walks the light back toward rest")
    func stillnessBringsTheLightHome() {
        let driver = Driver()
        driver.hold(roll: 0, seconds: 0.1)
        driver.turn(from: 0, to: 0.35, seconds: 1)

        let displaced = driver.driftFromRest
        driver.hold(roll: 0.35, seconds: 20)
        let settled = driver.driftFromRest

        #expect(displaced > 0.05, "the turn did not move the light: \(displaced)")
        #expect(settled < displaced / 3, "displaced \(displaced), settled \(settled)")
    }

    @Test("The light does not come home while the device is still turning")
    func turningHoldsTheLightOut() {
        // The whole point of gating. A reflection that forgets where the light is
        // during a gesture stops being a reflection.
        let driver = Driver()
        driver.hold(roll: 0, seconds: 0.1)

        // Twelve seconds of continuous turning, several times the light's own
        // return constant. An ungated return would have pulled it most of the way
        // home by the end of this.
        driver.turn(from: 0, to: 0.40, seconds: 12)

        #expect(driver.driftFromRest > 0.05, "the gesture was eaten: \(driver.driftFromRest)")
    }

    @Test("The return is far slower than the surface's own settle")
    func lightReturnsSlowerThanTheLean() {
        let driver = Driver()
        driver.hold(roll: 0, seconds: 0.1)
        driver.turn(from: 0, to: 0.35, seconds: 1)

        // Two seconds of stillness. The lean should be essentially flat by now and
        // the light should barely have started, or the two are not separated.
        driver.hold(roll: 0.35, seconds: 2)

        #expect(driver.model.tiltAngle < 0.01, "lean did not settle: \(driver.model.tiltAngle)")
        #expect(driver.driftFromRest > 0.05, "light came home too fast: \(driver.driftFromRest)")
    }

    @Test("A fixed angle is never walked back")
    func fixedAngleIsNotWalkedBack() {
        // A deterministic sample is an absolute request. Relaxing it would move the
        // light off the angle somebody just set, which reads as the control being
        // broken.
        let source = FixedMotionStub()
        let model = SurfaceReflectionModel(source: source)
        model.setActive(true)

        source.send(roll: 0.35, at: 1.0)
        let first = model.keyDirection

        var t = 1.0
        for _ in 0..<900 {   // thirty seconds at 30 Hz
            t += 1.0 / 30
            source.send(roll: 0.35, at: t)
        }

        #expect(simd_distance(model.keyDirection, first) < 1e-5)
    }
}

@MainActor
private final class FixedMotionStub: SurfaceAttitudeSource {
    var sampleHandler: ((SurfaceAttitudeSample) -> Void)?
    var failureHandler: (() -> Void)?
    func start() {}
    func stop() {}

    func send(roll: Float, at timestamp: TimeInterval) {
        sampleHandler?(
            SurfaceAttitudeSample(
                orientation: simd_quatf(angle: roll, axis: SIMD3(0, 1, 0)),
                timestamp: timestamp,
                isDeterministic: true
            )
        )
    }
}
