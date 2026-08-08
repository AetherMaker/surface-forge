import Foundation
import Testing
import simd

@testable import SurfaceForge

/// A source the test drives by hand, so the model can be stepped through exact
/// attitudes at exact timestamps.
@MainActor
private final class ManualMotionSource: SurfaceAttitudeSource {
    var sampleHandler: ((SurfaceAttitudeSample) -> Void)?
    var failureHandler: (() -> Void)?
    var startCount = 0
    var stopCount = 0

    func start() { startCount += 1 }
    func stop() { stopCount += 1 }

    func send(
        pitch: Float = 0,
        roll: Float = 0,
        at timestamp: TimeInterval,
        deterministic: Bool = false
    ) {
        sampleHandler?(
            SurfaceAttitudeSample(
                orientation: simd_quatf(angle: pitch, axis: SIMD3(1, 0, 0))
                    * simd_quatf(angle: roll, axis: SIMD3(0, 1, 0)),
                timestamp: timestamp,
                isDeterministic: deterministic
            )
        )
    }

    func send(_ sample: SurfaceAttitudeSample) { sampleHandler?(sample) }
    func fail() { failureHandler?() }
}

@MainActor
private func started() -> (SurfaceReflectionModel, ManualMotionSource) {
    let source = ManualMotionSource()
    let model = SurfaceReflectionModel(source: source)
    model.setActive(true)
    return (model, source)
}

@MainActor
@Suite("Adopting a neutral")
struct NeutralTests {
    @Test("The first live sample only sets the neutral, it does not move the light")
    func firstLiveSampleOnlySetsTheNeutral() {
        let (model, source) = started()

        source.send(roll: 0.4, at: 1.0)

        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
        #expect(model.diffuseAxis == SurfaceShading.restingDiffuseAxis)
        #expect(model.tiltAngle == 0)
    }

    @Test("Holding the adopted attitude keeps the light at rest")
    func holdingTheNeutralKeepsTheLightAtRest() {
        let (model, source) = started()

        for i in 0..<40 {
            source.send(roll: 0.4, at: 1.0 + Double(i) / 30)
        }

        #expect(simd_distance(model.keyDirection, SurfaceShading.neutralKeyDirection) < 1e-4)
    }

    @Test("Turning away from the neutral moves the light")
    func turningMovesTheLight() {
        let (model, source) = started()

        source.send(roll: 0, at: 1.0)
        for i in 1...40 {
            source.send(roll: 0.3, at: 1.0 + Double(i) / 30)
        }

        #expect(simd_distance(model.keyDirection, SurfaceShading.neutralKeyDirection) > 0.05)
    }

    @Test("A deterministic sample moves the light on its own")
    func deterministicSampleActsImmediately() {
        let (model, source) = started()

        // No neutral to adopt and no ramp to wait for, so one sample is an
        // absolute angle. That is the whole point of asking for one.
        source.send(roll: 0.3, at: 1.0, deterministic: true)

        #expect(simd_distance(model.keyDirection, SurfaceShading.neutralKeyDirection) > 0.05)
    }

    @Test("A repeated deterministic sample resolves to the same light every time")
    func deterministicSampleIsRepeatable() {
        let (model, source) = started()

        source.send(roll: 0.3, at: 1.0, deterministic: true)
        let first = model.keyDirection

        for i in 1...20 {
            source.send(roll: 0.3, at: 1.0 + Double(i) / 30, deterministic: true)
        }

        #expect(simd_distance(model.keyDirection, first) < 1e-6)
    }
}

@MainActor
@Suite("Smoothing")
struct SmoothingTests
{
    /// Drives the same attitude change over the same wall-clock span at a given
    /// rate, and reports where the light ended up.
    private func lightAfterOneSecond(atHz hz: Double) -> SIMD3<Float> {
        let (model, source) = started()
        source.send(roll: 0, at: 1.0)

        let step = 1.0 / hz
        for i in 1...Int(hz) {
            source.send(roll: 0.3, at: 1.0 + Double(i) * step)
        }
        return model.keyDirection
    }

    @Test("The response is the same at 30 Hz and 60 Hz")
    func responseIsRateIndependent() {
        // The filter is written as a time constant rather than a per-sample
        // blend precisely so this holds. A per-sample blend would land twice as
        // far along at double the rate.
        let at30 = lightAfterOneSecond(atHz: 30)
        let at60 = lightAfterOneSecond(atHz: 60)

        #expect(simd_distance(at30, at60) < 1e-3)
    }

    @Test("The response is the same at 30 Hz and 120 Hz")
    func responseHoldsAtHighRates() {
        let at30 = lightAfterOneSecond(atHz: 30)
        let at120 = lightAfterOneSecond(atHz: 120)

        #expect(simd_distance(at30, at120) < 1e-3)
    }

    @Test("A sample older than the last one is ignored")
    func staleSampleIsIgnored() {
        let (model, source) = started()
        source.send(roll: 0, at: 10.0)
        for i in 1...30 { source.send(roll: 0.3, at: 10.0 + Double(i) / 30) }
        let settled = model.keyDirection

        source.send(roll: -0.9, at: 5.0)

        #expect(model.keyDirection == settled)
    }
}

@MainActor
@Suite("The surface's own tilt")
struct TiltTests {
    @Test("Turning the device leans the surface")
    func turningLeansTheSurface() {
        let (model, source) = started()
        source.send(roll: 0, at: 1.0)

        for i in 1...20 {
            source.send(roll: Float(i) * 0.02, at: 1.0 + Double(i) / 30)
        }

        #expect(model.tiltAngle > 0.01)
    }

    @Test("The resting reference does not eat the gesture while the device turns")
    func referenceDoesNotEatTheGesture() {
        let (model, source) = started()
        source.send(roll: 0, at: 1.0)

        // A steady turn well above the deadband. An ungated reference would
        // relax toward the moving attitude and cancel most of this.
        var t = 1.0
        for i in 1...30 {
            t += 1.0 / 30
            source.send(roll: Float(i) * 0.02, at: t)
        }
        let duringGesture = model.tiltAngle

        // Now hold perfectly still at the final attitude. The reference is free
        // to catch up, so the surface settles flat.
        let held = Float(30) * 0.02
        for _ in 1...120 {
            t += 1.0 / 30
            source.send(roll: held, at: t)
        }

        #expect(duringGesture > 0.02, "gesture gave \(duringGesture)")
        #expect(model.tiltAngle < duringGesture / 4, "settled to \(model.tiltAngle)")
    }

    @Test("The lean never exceeds the ceiling")
    func leanNeverExceedsTheCeiling() {
        let (model, source) = started()
        source.send(roll: 0, at: 1.0)

        var t = 1.0
        for i in 1...60 {
            t += 1.0 / 30
            source.send(roll: Float(i) * 0.1, at: t)
        }

        let ceiling = Double(SurfaceReflectionModel.tiltCeiling(reduceMotion: false))
        #expect(model.tiltAngle <= ceiling + 1e-6)
    }

    @Test("Spinning the device in its own plane does not lean the surface")
    func inPlaneSpinDoesNotLean() {
        let source = ManualMotionSource()
        let model = SurfaceReflectionModel(source: source)
        model.setActive(true)

        source.send(SurfaceAttitudeSample(orientation: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)), timestamp: 1.0))

        // A rotation about z is the phone spinning in its own plane. The surface
        // is printed on that plane, so it spins with it and must not
        // counter-rotate.
        var t = 1.0
        for i in 1...40 {
            t += 1.0 / 30
            source.send(
                SurfaceAttitudeSample(
                    orientation: simd_quatf(angle: Float(i) * 0.03, axis: SIMD3(0, 0, 1)),
                    timestamp: t
                )
            )
        }

        #expect(model.tiltAngle < 1e-4, "z spin leaned it to \(model.tiltAngle)")
    }
}

@MainActor
@Suite("Lifecycle")
struct ReflectionLifecycleTests {
    @Test("Nothing is built until the model goes active")
    func nothingIsBuiltUntilActive() {
        let source = ManualMotionSource()
        _ = SurfaceReflectionModel(source: source)

        #expect(source.startCount == 0)
    }

    @Test("Going inactive stops sampling")
    func goingInactiveStopsSampling() {
        let (model, source) = started()
        #expect(source.startCount == 1)

        model.setActive(false)
        #expect(source.stopCount == 1)
    }

    @Test("Reduce Motion stops sampling and flattens the surface")
    func reduceMotionFlattensTheSurface() {
        let (model, source) = started()
        source.send(roll: 0, at: 1.0)
        for i in 1...30 { source.send(roll: Float(i) * 0.02, at: 1.0 + Double(i) / 30) }
        #expect(model.tiltAngle > 0)

        model.setReduceMotion(true)

        #expect(source.stopCount == 1)
        #expect(model.tiltAngle == 0)
        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
    }

    @Test("A sample arriving under Reduce Motion is ignored")
    func sampleUnderReduceMotionIsIgnored() {
        let (model, source) = started()
        model.setReduceMotion(true)

        source.send(roll: 0.5, at: 1.0, deterministic: true)

        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
        #expect(model.tiltAngle == 0)
    }

    @Test("A failed source returns the light to rest")
    func failureReturnsToRest() {
        let (model, source) = started()
        source.send(roll: 0.3, at: 1.0, deterministic: true)
        #expect(model.keyDirection != SurfaceShading.neutralKeyDirection)

        source.fail()

        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
        #expect(model.diffuseAxis == SurfaceShading.restingDiffuseAxis)
    }

    @Test("A non-finite sample returns the light to rest rather than poisoning it")
    func nonFiniteSampleReturnsToRest() {
        let (model, source) = started()
        source.send(roll: 0.3, at: 1.0, deterministic: true)

        source.send(
            SurfaceAttitudeSample(
                orientation: simd_quatf(ix: .nan, iy: 0, iz: 0, r: 1),
                timestamp: 2.0
            )
        )

        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
    }

    @Test("Changing the tilt source rebuilds it and returns to rest")
    func changingTheTiltSourceResets() {
        let (model, source) = started()
        source.send(roll: 0.3, at: 1.0, deterministic: true)
        #expect(model.keyDirection != SurfaceShading.neutralKeyDirection)

        model.setTiltSource(.fixed(pitch: 10, roll: 10))

        #expect(source.stopCount == 1)
        #expect(model.keyDirection == SurfaceShading.neutralKeyDirection)
    }
}

@Suite("The rotation vector")
struct RotationVectorTests {
    @Test("Identity maps to zero")
    func identityMapsToZero() {
        let v = SurfaceReflectionModel.rotationVector(simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)))
        #expect(simd_length(v) < 1e-6)
    }

    @Test("The magnitude is the rotation angle")
    func magnitudeIsTheAngle() {
        for angle in [Float(0.1), 0.5, 1.0, 2.0, 3.0] {
            let v = SurfaceReflectionModel.rotationVector(
                simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
            )
            #expect(abs(simd_length(v) - angle) < 1e-4, "angle \(angle) gave \(simd_length(v))")
        }
    }

    @Test("It takes the shortest arc past a half turn")
    func shortestArcPastAHalfTurn() {
        // A quaternion and its negation are the same rotation, but their log maps
        // differ by a half turn. Without the branch the surface snaps through 180
        // degrees at the wrap.
        let q = simd_quatf(angle: 3.4, axis: SIMD3(0, 1, 0))
        let v = SurfaceReflectionModel.rotationVector(q)

        #expect(simd_length(v) <= .pi + 1e-4)
    }
}
