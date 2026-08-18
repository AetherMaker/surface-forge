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

    @Test("Only sandblasted and molten retune the highlight")
    func onlyTheRetuningFinishesRetune() {
        // Sandblasted scatters and molten focuses; every other finish must
        // hand the tightness through untouched.
        for material in SurfaceMaterial.all {
            for finish in SurfaceFinish.all {
                let effective = finish.effectiveTightness(of: material)
                if finish.name == "Sandblasted" {
                    #expect(effective < material.highlightTightness)
                } else if finish.name == "Molten" {
                    #expect(effective > material.highlightTightness)
                } else {
                    // Exact, not approximate: polished rides this value.
                    #expect(effective == material.highlightTightness)
                }
            }
        }
    }

    @Test("Molten slopes hold their bars at any size")
    func moltenSlopesHoldAtAnySize() {
        // The solver divides each part's share by its peak and the
        // frequency scale, so the flow keeps its size and steepness on any
        // card.
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.molten
                .moltenCoefficients(size: CGSize(width: width, height: 220))

            let swell = c.a.y * SurfaceFinish.MoltenFlow.swellPeak * c.a.x
            let ripple = c.a.z * SurfaceFinish.MoltenFlow.ripplePeak * c.a.x
            let share = SurfaceFinish.moltenRippleShare

            #expect(abs(swell - SurfaceFinish.moltenSlope * (1 - share)) < 0.001)
            #expect(abs(ripple - SurfaceFinish.moltenSlope * share) < 0.001)
        }
    }

    @Test("Molten crosses the ceiling, and on purpose")
    func moltenCrossesTheCeilingDeliberately() {
        // The 0.030 ceiling protects a flat card's gleam from texture. A
        // melt is not a flat card, so the ceiling does not apply; it must
        // still be a wave, not a wall.
        #expect(SurfaceFinish.moltenSlope > 0.030)
        #expect(SurfaceFinish.moltenSlope < 1.0)
    }

    @Test("The measured flow suprema match a fresh sampling")
    func moltenPeaksAreTight() {
        // The solver trusts the baked peaks. If a wave or the warp changes
        // without re-measuring them, every slope silently rescales, so this
        // re-measures by sampling the same padded card domain.
        var swellPeak: Float = 0
        var ripplePeak: Float = 0
        let nu = 800, nv = 600
        for i in 0..<nu {
            for j in 0..<nv {
                let p = SIMD2<Float>(
                    -1.2 + 2.4 * Float(i) / Float(nu - 1),
                    -0.9 + 1.8 * Float(j) / Float(nv - 1)
                )
                let parts = SurfaceFinish.MoltenFlow.parts(p)
                swellPeak = max(swellPeak, simd_length(parts.swell))
                ripplePeak = max(ripplePeak, simd_length(parts.ripple))
            }
        }

        let flow = SurfaceFinish.MoltenFlow.self
        // A coarser grid than the capture can undersample a peak, so the
        // lower bound has slack. The upper bound does not.
        #expect(swellPeak <= flow.swellPeak * 1.02 && swellPeak >= flow.swellPeak * 0.93)
        #expect(ripplePeak <= flow.ripplePeak * 1.02 && ripplePeak >= flow.ripplePeak * 0.93)
    }

    @Test("The molten slope is finite and bounded everywhere")
    func moltenSlopeIsBounded() {
        // The shares sum to the total bar, so it bounds the whole field. A
        // NaN or an overshoot would be a mistake in the warp's chain rule.
        var generator = SystemRandomNumberGenerator()
        let flow = SurfaceFinish.MoltenFlow.self
        let share = SurfaceFinish.moltenRippleShare
        let bound = SurfaceFinish.moltenSlope * 1.05

        for _ in 0..<10_000 {
            let p = SIMD2<Float>(
                .random(in: -1.3...1.3, using: &generator),
                .random(in: -1.0...1.0, using: &generator)
            )
            let parts = flow.parts(p)
            let slope = parts.swell
                * (SurfaceFinish.moltenSlope * (1 - share) / flow.swellPeak)
                + parts.ripple * (SurfaceFinish.moltenSlope * share / flow.ripplePeak)

            #expect(slope.x.isFinite && slope.y.isFinite, "not finite at \(p)")
            #expect(simd_length(slope) <= bound, "slope \(simd_length(slope)) at \(p)")
        }
    }

    @Test("Hammer slope holds its bar at any size")
    func hammerSlopeHoldsAtAnySize() {
        for width in [200.0, 353.0, 800.0] {
            let c = SurfaceFinish.hammered
                .hammerCoefficients(size: CGSize(width: width, height: 220))
            let peak = c.a.y * SurfaceFinish.HammerField.peak * c.a.x
            #expect(abs(peak - SurfaceFinish.hammerSlope) < 0.001)
        }
    }

    @Test("The measured hammer peak matches a fresh sampling")
    func hammerPeakIsTight() {
        var peak: Float = 0
        let nu = 800, nv = 600
        for i in 0..<nu {
            for j in 0..<nv {
                let p = SIMD2<Float>(
                    -1.2 + 2.4 * Float(i) / Float(nu - 1),
                    -0.9 + 1.8 * Float(j) / Float(nv - 1)
                )
                peak = max(peak, simd_length(SurfaceFinish.HammerField.slope(p)))
            }
        }
        let baked = SurfaceFinish.HammerField.peak
        #expect(peak <= baked * 1.02 && peak >= baked * 0.93, "sampled \(peak) vs baked \(baked)")
    }

    @Test("Hammer crosses the ceiling, and on purpose")
    func hammerCrossesTheCeilingDeliberately() {
        // A dent is coarse enough to shade itself; the ceiling is for fine
        // texture. Still a bowl, not a wall.
        #expect(SurfaceFinish.hammerSlope > 0.030)
        #expect(SurfaceFinish.hammerSlope < 0.5)
    }

    @Test("The mirrored hammer field matches the shader's constants")
    func hammerFieldMatchesTheShader() throws {
        let shader = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/SurfaceForge/Surface.metal")
        let text = try String(contentsOf: shader, encoding: .utf8)

        func scalar(named name: String) throws -> Float {
            let regex = try Regex(#"constant float\s+k"# + name + #"\s*=\s*([0-9.]+);"#)
            let match = try #require(text.firstMatch(of: regex), "\(name) not found")
            return try #require(Float(match.output[1].substring ?? ""))
        }

        let field = SurfaceFinish.HammerField.self
        #expect(try scalar(named: "HammerPitch") == field.pitch)
        #expect(try scalar(named: "HammerRadius") == field.radius)
        #expect(try scalar(named: "HammerJitter") == field.jitter)
        #expect(try scalar(named: "HammerRadiusSpread") == field.radiusSpread)
    }

    @Test("The mirrored flow matches the shader's constants")
    func moltenFlowMatchesTheShader() throws {
        // The tests above check the mirror against itself, which passes
        // however far the shader drifts. This one reads Surface.metal.
        let shader = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/SurfaceForge/Surface.metal")
        let text = try String(contentsOf: shader, encoding: .utf8)

        func numbers(named name: String) throws -> [Float] {
            let pattern = #"constant float[23]?\s+k"# + name + #"(?:\[\d+\])?\s*=\s*\{?([^;]*)\}?;"#
            let regex = try Regex(pattern).dotMatchesNewlines()
            let match = try #require(text.firstMatch(of: regex), "\(name) not found")
            return String(match.output[1].substring ?? "")
                .replacing("float2", with: "").replacing("float3", with: "")
                .split(whereSeparator: { "(),{} \n".contains($0) })
                .compactMap { Float($0) }
        }

        let flow = SurfaceFinish.MoltenFlow.self
        #expect(try numbers(named: "MoltenSwellWave")
            == flow.swellWaves.flatMap { [$0.x, $0.y] })
        #expect(try numbers(named: "MoltenSwellPhase")
            == [flow.swellPhase.x, flow.swellPhase.y, flow.swellPhase.z])
        #expect(try numbers(named: "MoltenSwellWeight")
            == [flow.swellWeight.x, flow.swellWeight.y, flow.swellWeight.z])
        #expect(try numbers(named: "MoltenRippleWave")
            == flow.rippleWaves.flatMap { [$0.x, $0.y] })
        #expect(try numbers(named: "MoltenRipplePhase")
            == [flow.ripplePhase.x, flow.ripplePhase.y, flow.ripplePhase.z])
        #expect(try numbers(named: "MoltenRippleWeight")
            == [flow.rippleWeight.x, flow.rippleWeight.y, flow.rippleWeight.z])
        #expect(try numbers(named: "MoltenWarpA")
            == [flow.warpWaveA.x, flow.warpWaveA.y])
        #expect(try numbers(named: "MoltenWarpB")
            == [flow.warpWaveB.x, flow.warpWaveB.y])
        #expect(try numbers(named: "MoltenWarpPhase")
            == [flow.warpPhase.x, flow.warpPhase.y])
        #expect(try numbers(named: "MoltenWarpAmount") == [flow.warpAmount])
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
