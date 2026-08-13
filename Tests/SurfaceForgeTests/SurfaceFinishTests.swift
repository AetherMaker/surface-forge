import SwiftUI
import Testing
import simd

@testable import SurfaceForge

@Suite("Finish solving")
struct SurfaceFinishTests {
    @Test("Pinstripe holds its pitch at any size")
    func pinstripePitchIsSizeInvariant() {
        // The stripes are a physical width, not a fraction of the card. A
        // coefficient in surface units must therefore change with the card, and
        // the count of stripes must come out as width over pitch.
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.pinstripe
                .pinstripeCoefficients(size: CGSize(width: width, height: 220))
            // u spans 2 units across the width, and one cycle is 2 pi of phase.
            let cycles = Double(simd_length(SIMD2(c.a.x, c.a.y))) * 2 / (2 * .pi)

            #expect(
                abs(cycles - width / Double(SurfaceFinish.pinstripePitch)) < 0.01,
                "\(width)pt wide drew \(cycles) stripes"
            )
        }
    }

    @Test("Pinstripe survives hostile angles")
    func pinstripeStaysFinite() {
        // The shader trusts these to be finite for the same reason it trusts
        // the brush grain: sanitizing lives on the CPU, once.
        for degrees in [Double.nan, .infinity, -.infinity, 1e300, -1e300, 37] {
            let c = SurfaceFinish.pinstripe(angle: .degrees(degrees))
                .pinstripeCoefficients(size: CGSize(width: 353, height: 220))

            for value in [c.a.x, c.a.y, c.a.z, c.a.w, c.b.x, c.b.y, c.b.z] {
                #expect(value.isFinite, "angle \(degrees)° produced \(value)")
            }
        }
    }

    @Test("Every finish slope stays under the gleam's ceiling")
    func slopesStayUnderTheCeiling() {
        // 0.030 is the slope past which a pattern stops modulating the
        // travelling gleam and starts switching it, which tears the highlight.
        #expect(SurfaceFinish.pinstripeSlope <= 0.030)
        #expect(SurfaceFinish.twillCrownSlope <= 0.030)
        #expect(SurfaceFinish.basketweaveRibSlope <= 0.030)
        #expect(SurfaceFinish.clousSlope <= 0.030)
        // Knurling's two families cross, so the budget is shared.
        #expect(SurfaceFinish.knurlSlope * 2 <= 0.030)
    }

    @Test("Knurl phase vectors are unit directions after the reciprocal")
    func knurlReciprocalIsExact() {
        // The shader multiplies each phase vector by b.z to get a unit slope
        // direction. If the reciprocal drifts from the vectors' length, every
        // groove's depth silently scales with it.
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.knurling
                .knurlCoefficients(size: CGSize(width: width, height: 220))
            let lengthA = simd_length(SIMD2(c.a.x, c.a.y)) * c.b.z
            let lengthB = simd_length(SIMD2(c.a.z, c.a.w)) * c.b.z

            #expect(abs(lengthA - 1) < 1e-5 && abs(lengthB - 1) < 1e-5)
        }
    }

    @Test("The blast depth clears the 8-bit quantum")
    func blastDepthIsVisible() {
        // 0.87 substrate luminance, times depth, must span several of 255
        // levels or the mottle renders as nothing, which is how the first
        // version died.
        let levels = SurfaceFinish.blastDepth * 0.87 * 255
        #expect(levels >= 5, "mottle spans only \(levels) levels")
    }

    @Test("Clous holds its pitch at any size")
    func clousPitchIsSizeInvariant() {
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.clousDeParis
                .clousCoefficients(size: CGSize(width: width, height: 220))
            let studs = Double(c.a.x) * 2 / (2 * .pi)

            #expect(
                abs(studs - width / Double(SurfaceFinish.clousPitchPoints)) < 0.01,
                "\(width)pt wide set \(studs) studs"
            )
        }
    }

    @Test("Twill holds its cell size at any size")
    func twillCellIsSizeInvariant() {
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.carbonTwill.twillCoefficients(
                size: CGSize(width: width, height: 220),
                lightAzimuth: SIMD2(0.3, 0.2)
            )
            // a.x is cells per surface unit and the width spans 2 units.
            let cells = Double(c.a.x) * 2

            #expect(
                abs(cells - width / Double(SurfaceFinish.twillCellPoints)) < 0.01,
                "\(width)pt wide wove \(cells) cells"
            )
        }
    }

    @Test("Topographic slope holds its bar at any size")
    func topographicSlopeHoldsAtAnySize() {
        // The solver divides the slope bar by the field's peak gradient. If the
        // mirrored constants drift from the shader's, this stops holding, so it
        // is the test that welds the two copies together.
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.topographic
                .topographicCoefficients(size: CGSize(width: width, height: 220))
            let peak = c.a.y * SurfaceFinish.TopographicField.peakGradient * c.a.x

            #expect(
                abs(peak - SurfaceFinish.topographicSlope) < 0.001,
                "\(width)pt wide peaks at slope \(peak)"
            )
        }
    }

    @Test("The mirrored field matches the shader's constants")
    func topographicFieldMatchesTheShader() throws {
        // The real weld. The gradient test below checks the Swift copy against
        // its own closed form, which both copies pass however far they drift
        // apart; this one reads Surface.metal and fails when they differ.
        let shader = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/SurfaceForge/Surface.metal")
        let text = try String(contentsOf: shader, encoding: .utf8)

        func constants(named name: String) throws -> [Float] {
            let pattern = #"constant float3 k"# + name + #"\s*= float3\(([^)]*)\);"#
            let regex = try Regex(pattern)
            let match = try #require(text.firstMatch(of: regex), "\(name) not found")
            return String(match.output[1].substring ?? "")
                .split(separator: ",")
                .compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        }

        let field = SurfaceFinish.TopographicField.self
        let pairs: [(String, SIMD3<Float>)] = [
            ("TopoFrequencyU", field.frequencyU),
            ("TopoFrequencyV", field.frequencyV),
            ("TopoPhase", field.phase),
            ("TopoWeight", field.weight),
        ]
        for (name, mirror) in pairs {
            let shaderValues = try constants(named: name)
            #expect(
                shaderValues == [mirror.x, mirror.y, mirror.z],
                "\(name) drifted: shader \(shaderValues) vs mirror \(mirror)"
            )
        }
    }

    @Test("The mirrored field matches its own analytic gradient")
    func topographicGradientIsAnalytic() {
        // Central differences against the closed form, at enough random points
        // to catch a wrong sign or a swapped frequency component.
        var generator = SystemRandomNumberGenerator()
        let step: Float = 1.0e-3

        for _ in 0..<1000 {
            let p = SIMD2<Float>(
                .random(in: -1...1, using: &generator),
                .random(in: -0.6...0.6, using: &generator)
            )
            let field = SurfaceFinish.TopographicField.self
            let numeric = SIMD2<Float>(
                (field.height(p + SIMD2(step, 0), scale: 1)
                    - field.height(p - SIMD2(step, 0), scale: 1)) / (2 * step),
                (field.height(p + SIMD2(0, step), scale: 1)
                    - field.height(p - SIMD2(0, step), scale: 1)) / (2 * step)
            )

            let arg = (field.frequencyU * p.x + field.frequencyV * p.y) + field.phase
            let cosArg = SIMD3<Float>(cos(arg.x), cos(arg.y), cos(arg.z))
            let analytic = SIMD2<Float>(
                simd_dot(field.weight * field.frequencyU, cosArg),
                simd_dot(field.weight * field.frequencyV, cosArg)
            )

            #expect(
                simd_length(numeric - analytic) < 0.01 * max(simd_length(analytic), 1),
                "gradient mismatch at \(p): \(numeric) vs \(analytic)"
            )
        }
    }

    @Test("Basketweave holds its block size at any size")
    func basketweaveBlockIsSizeInvariant() {
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.basketweave.basketweaveCoefficients(
                size: CGSize(width: width, height: 220),
                lightAzimuth: SIMD2(0.3, 0.2)
            )
            let blocks = Double(c.a.x) * 2

            #expect(
                abs(blocks - width / Double(SurfaceFinish.basketweaveBlockPoints)) < 0.01,
                "\(width)pt wide wove \(blocks) blocks"
            )
        }
    }

    @Test("Twill survives a zero light azimuth")
    func twillSurvivesZeroAzimuth() {
        // A light straight overhead has no azimuth. Normalizing zero is NaN,
        // and the solver must hand the shader a finite vector instead.
        let c = SurfaceFinish.carbonTwill.twillCoefficients(
            size: CGSize(width: 353, height: 220),
            lightAzimuth: .zero
        )
        #expect(c.b.x.isFinite && c.b.y.isFinite)
    }

    @Test("A finish leaves the metal itself alone")
    func finishPreservesTheMetal() {
        for material in SurfaceMaterial.all {
            for finish in SurfaceFinish.all {
                let worked = material.finish(finish)

                #expect(worked.tint == material.tint, "\(material.name) changed tint")
                #expect(
                    worked.highlightTightness == material.highlightTightness,
                    "\(material.name) changed tightness"
                )
                #expect(worked.name == material.name, "\(material.name) changed name")
            }
        }
    }
}
