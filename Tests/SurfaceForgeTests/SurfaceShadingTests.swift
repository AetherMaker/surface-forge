import Testing
import simd

@testable import SurfaceForge

/// Where the specular peak lands on a flat surface, in half-widths, for a light
/// `L` and a virtual eye. The same solve `neutralKeyDirection` inverts, so the
/// two can be checked against each other.
private func specularPeak(
    light L: SIMD3<Float>,
    eye: (y: Double, z: Double)
) -> SIMD2<Double> {
    SIMD2(
        eye.z * Double(L.x) / Double(L.z),
        eye.y + eye.z * Double(L.y) / Double(L.z)
    )
}

@Suite("The lights")
struct ShadingLightTests {
    @Test("The neutral hold returns exactly the neutral key")
    func neutralHoldReturnsTheNeutralKey() {
        let key = SurfaceShading.keyDirection(deviceAxis: SurfaceShading.canonicalAxis)
        #expect(simd_distance(key, SurfaceShading.neutralKeyDirection) < 1e-6)
    }

    @Test("The resting gleam is vertically centred")
    func restingGleamIsVerticallyCentred() {
        // Horizontal placement belongs to `SurfaceLightOffsetTests`. This pins the
        // other axis, which nothing exposes and which a change to the eye solve
        // could quietly break.
        let eye = SurfaceShading.virtualEye(halfHeight: SurfaceShading.referenceHalfHeight)
        let peak = specularPeak(light: SurfaceShading.neutralKeyDirection, eye: eye)

        #expect(abs(peak.y) < 1e-3)
    }

    @Test("Tilting moves the specular panel off its rest direction")
    func tiltMovesThePanel() {
        let tilted = simd_quatf(angle: 0.25, axis: SIMD3(0, 1, 0))
            .act(SurfaceShading.canonicalAxis)
        let key = SurfaceShading.keyDirection(deviceAxis: tilted)

        #expect(simd_distance(key, SurfaceShading.neutralKeyDirection) > 0.05)
    }

    @Test("Every key direction stays a unit vector above the surface")
    func keyDirectionStaysAboveTheSurface() {
        for angle in stride(from: -1.5, through: 1.5, by: 0.1) {
            for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(1, 1, 0)] {
                let tilted = simd_quatf(angle: Float(angle), axis: simd_normalize(axis))
                    .act(SurfaceShading.canonicalAxis)
                let key = SurfaceShading.keyDirection(deviceAxis: tilted)

                #expect(abs(simd_length(key) - 1) < 1e-5)
                #expect(key.z >= SurfaceShading.keyReflectionMinimumZ - 1e-5)
            }
        }
    }
}

@Suite("Lifting an axis")
struct LiftedTests {
    @Test("A lifted axis is always unit length")
    func liftedIsUnitLength() {
        let hostile: [SIMD3<Float>] = [
            SIMD3(0, 0, -1),
            SIMD3(0, 0, 1),
            SIMD3(1, 0, 0),
            SIMD3(-0.7, -0.7, -0.1),
            SIMD3(0, 0, 0),
        ]

        for axis in hostile {
            let lifted = SurfaceShading.lifted(axis, minimumZ: 0.45)
            #expect(abs(simd_length(lifted) - 1) < 1e-5, "\(axis) gave \(lifted)")
        }
    }

    @Test("An edge-on axis keeps a unit planar part rather than being rescaled")
    func edgeOnAxisIsNotRescaled() {
        // The fallback path. The canonical axis's planar part is only 0.513 long,
        // so handing it over raw would return a non-unit direction, which the
        // shader dots against and silently changes the specular's intensity.
        let lifted = SurfaceShading.lifted(SIMD3(0, 0, -1), minimumZ: 0.45)
        #expect(abs(simd_length(lifted) - 1) < 1e-5)
        #expect(lifted.z >= 0.45 - 1e-5)
    }

    @Test("The floor is respected and the ceiling is not exceeded")
    func floorAndCeiling() {
        for z in stride(from: -1.0, through: 1.0, by: 0.1) {
            let lifted = SurfaceShading.lifted(SIMD3(0.5, 0.5, Float(z)), minimumZ: 0.2)
            #expect(lifted.z >= 0.2 - 1e-5)
            #expect(lifted.z <= 1 + 1e-5)
        }
    }
}

@Suite("Fading the reflection out")
struct GleamFadeTests {
    /// A pose nothing like rest, so a leak would be obvious.
    private var hostileKey: SIMD3<Float> {
        SurfaceShading.keyDirection(
            deviceAxis: simd_quatf(angle: 1.2, axis: SIMD3(0, 1, 0))
                .act(SurfaceShading.canonicalAxis)
        )
    }

    @Test("At gleam 0 the output ignores the live pose entirely")
    func gleamZeroIgnoresThePose() {
        let hostileDiffuse = SurfaceShading.lifted(
            SIMD3(-0.9, -0.4, 0.1),
            minimumZ: SurfaceShading.diffuseMinimumZ
        )

        let out = SurfaceShading.lights(
            keyDirection: hostileKey,
            diffuseAxis: hostileDiffuse,
            gleam: 0
        )

        #expect(simd_distance(out.key, SurfaceShading.neutralKeyDirection) < 1e-6)
        #expect(simd_distance(out.diffuse, SurfaceShading.restingDiffuseAxis) < 1e-6)
    }

    @Test("At gleam 0 two different poses give identical output")
    func gleamZeroIsPoseIndependent() {
        let a = SurfaceShading.lights(
            keyDirection: hostileKey,
            diffuseAxis: SurfaceShading.canonicalAxis,
            gleam: 0
        )
        let b = SurfaceShading.lights(
            keyDirection: SurfaceShading.neutralKeyDirection,
            diffuseAxis: SurfaceShading.restingDiffuseAxis,
            gleam: 0
        )

        #expect(a.key == b.key)
        #expect(a.diffuse == b.diffuse)
    }

    @Test("At gleam 1 the live pair passes through bit-exact")
    func gleamOneIsBitExact() {
        let key = hostileKey
        let diffuse = SurfaceShading.restingDiffuseAxis

        let out = SurfaceShading.lights(keyDirection: key, diffuseAxis: diffuse, gleam: 1)

        #expect(out.key == key)
        #expect(out.diffuse == diffuse)
    }

    @Test("Out of range gleam clamps rather than extrapolating")
    func gleamClamps() {
        let key = hostileKey

        let over = SurfaceShading.lights(
            keyDirection: key,
            diffuseAxis: SurfaceShading.restingDiffuseAxis,
            gleam: 5
        )
        let under = SurfaceShading.lights(
            keyDirection: key,
            diffuseAxis: SurfaceShading.restingDiffuseAxis,
            gleam: -5
        )

        #expect(over.key == key)
        #expect(simd_distance(under.key, SurfaceShading.neutralKeyDirection) < 1e-6)
    }

    @Test("A partial gleam stays a unit vector between the two poses")
    func partialGleamStaysUnit() {
        for gleam in stride(from: 0.0, through: 1.0, by: 0.05) {
            let out = SurfaceShading.lights(
                keyDirection: hostileKey,
                diffuseAxis: SurfaceShading.restingDiffuseAxis,
                gleam: gleam
            )
            #expect(abs(simd_length(out.key) - 1) < 1e-5)
            #expect(abs(simd_length(out.diffuse) - 1) < 1e-5)
        }
    }
}

@Suite("The virtual eye")
struct VirtualEyeTests {
    @Test("The eye sits in front of the surface and above its centre")
    func eyeIsInFrontAndAbove() {
        for h in [0.3, 0.5, 0.6232, 1.0, 1.6] {
            let eye = SurfaceShading.virtualEye(halfHeight: h)
            #expect(eye.z > 0, "halfHeight \(h) gave z \(eye.z)")
            #expect(eye.y > h, "halfHeight \(h) gave y \(eye.y)")
        }
    }

    @Test("A taller surface pushes the eye further back")
    func tallerSurfacePushesTheEyeBack() {
        let wide = SurfaceShading.virtualEye(halfHeight: 0.4)
        let tall = SurfaceShading.virtualEye(halfHeight: 1.2)
        #expect(tall.z > wide.z)
    }
}

@Suite("Normalizing")
struct NormalizedTests {
    @Test("Garbage falls back rather than propagating NaN")
    func garbageFallsBack() {
        let fallback = SIMD3<Float>(1, 0, 0)

        #expect(SurfaceShading.normalized(SIMD3(0, 0, 0), fallback: fallback) == fallback)
        #expect(SurfaceShading.normalized(SIMD3(.nan, 0, 0), fallback: fallback) == fallback)
        #expect(SurfaceShading.normalized(SIMD3(.infinity, 0, 0), fallback: fallback) == fallback)
    }

    @Test("A valid vector comes back unit length")
    func validVectorIsUnit() {
        let out = SurfaceShading.normalized(SIMD3(3, 4, 0), fallback: SIMD3(1, 0, 0))
        #expect(abs(simd_length(out) - 1) < 1e-6)
        #expect(abs(out.x - 0.6) < 1e-6)
    }
}
