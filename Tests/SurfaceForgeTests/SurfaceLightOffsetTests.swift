import Testing
import simd

@testable import SurfaceForge

/// Where the specular peak lands on a flat surface, in half-widths. The same
/// solve `neutralKeyDirection` inverts, so the light and its highlight can be
/// checked against each other.
private func peakX(light L: SIMD3<Float>, halfHeight: Double) -> Double {
    let eye = SurfaceShading.virtualEye(halfHeight: halfHeight)
    return eye.z * Double(L.x) / Double(L.z)
}

private let h = SurfaceShading.referenceHalfHeight

@Suite("Moving the light")
struct SurfaceLightOffsetTests {
    @Test("At rest the highlight sits dead centre")
    func restIsCentred() {
        #expect(abs(peakX(light: SurfaceShading.neutralKeyDirection, halfHeight: h)) < 1e-3)
    }

    @Test("An offset lands the highlight exactly there")
    func offsetLandsWhereAsked() {
        for offset in [-1.0, -0.5, -0.2, 0.2, 0.5, 1.0] {
            let angle = SurfaceShading.lightAngle(forOffset: offset, halfHeight: h)
            let swung = SurfaceShading.swung(
                SurfaceShading.neutralKeyDirection,
                by: angle,
                minimumZ: SurfaceShading.keyReflectionMinimumZ
            )

            #expect(
                abs(peakX(light: swung, halfHeight: h) - offset) < 0.02,
                "offset \(offset) landed at \(peakX(light: swung, halfHeight: h))"
            )
        }
    }

    @Test("Zero is an exact passthrough")
    func zeroChangesNothing() {
        let angle = SurfaceShading.lightAngle(forOffset: 0, halfHeight: h)
        #expect(angle == 0)

        let swung = SurfaceShading.swung(
            SurfaceShading.neutralKeyDirection,
            by: angle,
            minimumZ: SurfaceShading.keyReflectionMinimumZ
        )
        #expect(swung == SurfaceShading.neutralKeyDirection)
    }

    @Test("The same offset lands in the same place on any proportion")
    func offsetHoldsAcrossProportions() {
        // `ez` grows with a taller surface, so a fixed angle would throw the
        // highlight further on one shape than another. The angle is solved per
        // proportion precisely to stop that.
        for halfHeight in [0.3, 0.6232, 1.0, 1.6] {
            let angle = SurfaceShading.lightAngle(forOffset: 0.5, halfHeight: halfHeight)
            let swung = SurfaceShading.swung(
                SurfaceShading.neutralKeyDirection,
                by: angle,
                minimumZ: SurfaceShading.keyReflectionMinimumZ
            )

            #expect(
                abs(peakX(light: swung, halfHeight: halfHeight) - 0.5) < 0.02,
                "halfHeight \(halfHeight) landed at \(peakX(light: swung, halfHeight: halfHeight))"
            )
        }
    }

    @Test("Both lights swing by the same angle")
    func bothLightsMoveTogether() {
        // Moving only the specular is what makes the shading and the highlight
        // disagree about which side the light is on.
        let angle = SurfaceShading.lightAngle(forOffset: 0.8, halfHeight: h)

        let key = SurfaceShading.swung(
            SurfaceShading.neutralKeyDirection,
            by: angle,
            minimumZ: SurfaceShading.keyReflectionMinimumZ
        )
        let diffuse = SurfaceShading.swung(
            SurfaceShading.restingDiffuseAxis,
            by: angle,
            minimumZ: SurfaceShading.diffuseMinimumZ
        )

        // Both must have moved toward +x, since a positive angle means the light
        // went right.
        #expect(key.x > SurfaceShading.neutralKeyDirection.x)
        #expect(diffuse.x > SurfaceShading.restingDiffuseAxis.x)
    }

    @Test("A swung light stays a unit vector above the surface")
    func swungLightStaysValid() {
        for offset in stride(from: -1.0, through: 1.0, by: 0.1) {
            let angle = SurfaceShading.lightAngle(forOffset: offset, halfHeight: h)
            let swung = SurfaceShading.swung(
                SurfaceShading.neutralKeyDirection,
                by: angle,
                minimumZ: SurfaceShading.keyReflectionMinimumZ
            )

            #expect(abs(simd_length(swung) - 1) < 1e-5)
            #expect(swung.z >= SurfaceShading.keyReflectionMinimumZ - 1e-5)
        }
    }
}
