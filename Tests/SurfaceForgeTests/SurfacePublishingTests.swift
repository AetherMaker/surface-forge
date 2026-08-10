import Foundation
import Testing
import simd

@testable import SurfaceForge

/// Feeds attitudes with a controllable amount of jitter on top.
@MainActor
private final class JitterSource: SurfaceAttitudeSource {
    var sampleHandler: ((SurfaceAttitudeSample) -> Void)?
    var failureHandler: (() -> Void)?
    func start() {}
    func stop() {}

    private var time = 1.0
    private var seed: UInt64

    init(seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.seed = seed
    }

    /// Deterministic, and signed.
    ///
    /// Returns -1 to +1, so jitter straddles the held attitude. An unsigned
    /// generator would add a constant offset that the resting reference simply
    /// absorbs, leaving the test exercising half the excursion a reader assumes.
    private func next() -> Float {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int64(bitPattern: seed >> 11)) / Float(1 << 53) * 2 - 1
    }

    func hold(
        roll: Float,
        jitter: Float,
        seconds: Double,
        onSample: (() -> Void)? = nil
    ) {
        for _ in 0..<Int(seconds * 30) {
            time += 1.0 / 30
            sampleHandler?(
                SurfaceAttitudeSample(
                    orientation: simd_quatf(
                        angle: roll + next() * jitter,
                        axis: SIMD3(0, 1, 0)
                    ),
                    timestamp: time
                )
            )
            onSample?()
        }
    }

    func turn(from start: Float, to end: Float, seconds: Double) {
        let steps = Int(seconds * 30)
        for i in 1...steps {
            time += 1.0 / 30
            sampleHandler?(
                SurfaceAttitudeSample(
                    orientation: simd_quatf(
                        angle: start + (end - start) * Float(i) / Float(steps),
                        axis: SIMD3(0, 1, 0)
                    ),
                    timestamp: time
                )
            )
        }
    }
}

@MainActor
@Suite("Publishing")
struct SurfacePublishingTests {
    /// Sensor noise at rest, in radians per reading.
    ///
    /// The worst a still device was measured to produce, against a typical 4e-5,
    /// so the tests run at the top of the range rather than the middle.
    private let noise: Float = 0.0001

    @Test("A still device barely republishes", arguments: [
        0x9E37_79B9_7F4A_7C15 as UInt64, 0x1234_5678_9ABC_DEF0, 0xDEAD_BEEF_CAFE_0001,
        0x0000_0000_0000_0001, 0xFFFF_FFFF_FFFF_FFFF,
    ])
    func stillDeviceBarelyRepublishes(seed: UInt64) {
        // Readings arrive at 30 Hz whether or not the device moves, and noise
        // means no two are alike. Assigning every one holds the display at full
        // refresh for a surface that is visibly doing nothing.
        //
        // Counts assignments rather than demanding they be bit-identical, which a
        // change threshold never promised: sub-threshold motion accumulates until
        // it crosses. Ungated this is 150 of 150. Several seeds, because one
        // passing is luck.
        let source = JitterSource(seed: seed)
        let model = SurfaceReflectionModel(source: source)
        model.setActive(true)

        source.hold(roll: 0, jitter: noise, seconds: 0.1)
        source.turn(from: 0, to: 0.30, seconds: 1)

        // Long enough for the light's own walk home to finish. Every step of that
        // is a real change and must publish. Only after it lands should the
        // surface go quiet.
        source.hold(roll: 0.30, jitter: noise, seconds: 40)

        var previous = (
            key: model.keyDirection,
            diffuse: model.diffuseAxis,
            angle: model.tiltAngle,
            axis: model.tiltAxis
        )
        var publishes = 0

        source.hold(roll: 0.30, jitter: noise, seconds: 5) {
            let now = (
                key: model.keyDirection,
                diffuse: model.diffuseAxis,
                angle: model.tiltAngle,
                axis: model.tiltAxis
            )
            if now != previous { publishes += 1 }
            previous = now
        }

        #expect(publishes < 15, "a still surface republished \(publishes) times in 150 samples")
    }

    @Test("Real movement still publishes")
    func realMovementStillPublishes() {
        // The other half. A threshold that silences noise must not silence the
        // gesture, or the material stops responding at all.
        let source = JitterSource()
        let model = SurfaceReflectionModel(source: source)
        model.setActive(true)

        source.hold(roll: 0, jitter: noise, seconds: 0.1)
        source.turn(from: 0, to: 0.30, seconds: 1)
        source.hold(roll: 0.30, jitter: noise, seconds: 3)

        let before = model.keyDirection
        source.turn(from: 0.30, to: 0.40, seconds: 0.5)

        #expect(
            simd_distance(model.keyDirection, before) > 0.01,
            "a real turn moved the light only \(simd_distance(model.keyDirection, before))"
        )
    }

    @Test("A slow drift is not swallowed")
    func slowDriftIsNotSwallowed() {
        // The failure a threshold invites: movement below the bar on every single
        // sample, which never publishes and leaves the surface frozen through a
        // gesture that is genuinely happening.
        let source = JitterSource()
        let model = SurfaceReflectionModel(source: source)
        model.setActive(true)

        source.hold(roll: 0, jitter: noise, seconds: 0.1)
        source.turn(from: 0, to: 0.25, seconds: 8)

        #expect(
            simd_distance(model.keyDirection, SurfaceShading.neutralKeyDirection) > 0.05,
            "an eight-second drift left the light where it started"
        )
    }
}
