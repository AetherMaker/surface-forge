import SwiftUI
import simd

extension View {
    /// Applies a metallic material over this view's rendered content.
    ///
    /// A filter rather than a layer behind the content, which is what lets the
    /// material retint a light surface to metal while dark content stays dark, and
    /// lets the gleam cross the content instead of being occluded by it. See the
    /// shader's own note.
    func surfaceMetal(
        _ material: SurfaceMaterial,
        keyDirection: SIMD3<Float>,
        diffuseAxis: SIMD3<Float>,
        gleam: Double,
        lightOffset: Double
    ) -> some View {
        // Resolved here, once per body, rather than inside the effect closure. The
        // closure runs per layout pass and this is a function of published state.
        let lights = SurfaceShading.lights(
            keyDirection: keyDirection,
            diffuseAxis: diffuseAxis,
            gleam: gleam
        )
        let amount = Float(min(max(gleam, 0), 1))
        let tint = material.tint
        let tightness = material.highlightTightness
        let offset = min(max(lightOffset, -1), 1)

        let finish = material.surfaceFinish

        return visualEffect { view, proxy in
            // Solved here rather than per fragment. The eye is a function of the
            // surface's proportion alone, so the shader would be recomputing one
            // quadratic per pixel for a value that is uniform across the surface,
            // and the compiler cannot hoist it because it cannot know the uniform.
            let halfHeight = max(
                proxy.size.height / max(proxy.size.width, 1),
                1.0e-3
            )
            let eye = SurfaceShading.virtualEye(halfHeight: halfHeight)

            // After `lights`, not before. `lights` walks the live pose toward the
            // rest pose as the gleam fades, and the swing has to ride the
            // resolved pair or a fading gleam would eat it. Solved here rather
            // than in the body because it needs this surface's own proportion.
            let angle = SurfaceShading.lightAngle(
                forOffset: offset,
                halfHeight: halfHeight
            )
            let key = SurfaceShading.swung(
                lights.key,
                by: angle,
                minimumZ: SurfaceShading.keyReflectionMinimumZ
            )
            let diffuse = SurfaceShading.swung(
                lights.diffuse,
                by: angle,
                minimumZ: SurfaceShading.diffuseMinimumZ
            )

            // One shader arm per finish, picked here rather than branched on
            // a uniform in the shader. Every arm shares the same leading
            // arguments; what follows is the arm's own coefficient registers.
            //
            // Spelled out component-wise: the multi-Float overloads are the
            // ones guaranteed across SDK revisions.
            let common: [Shader.Argument] = [
                .float2(proxy.size),
                .float2(Float(eye.y), Float(eye.z)),
                .float(Float(halfHeight)),
                .float3(key.x, key.y, key.z),
                .float3(diffuse.x, diffuse.y, diffuse.z),
                .float(amount),
                .float3(tint.x, tint.y, tint.z),
                .float(tightness),
            ]
            let azimuth = SIMD2(diffuse.x, diffuse.y)
            let library = ShaderLibrary.bundle(.module)

            let arm: (ShaderFunction, [SurfaceFinishCoefficients])
            switch finish.kind {
            case .polished:
                arm = (library.surfacePolished, [])
            case .brushed:
                // Perpendicular to the brush stroke, because a groove scatters
                // light across itself: hair gives a band across the strands, a
                // record streaks radially. Solved here so no fragment pays for
                // a sincos of one value that is the same everywhere.
                var c = SurfaceFinishCoefficients()
                c.a = SIMD4(
                    finish.stretch,
                    -sin(finish.grainAngle),
                    cos(finish.grainAngle),
                    0
                )
                arm = (library.surfaceMetal, [c])
            case .pinstripe:
                arm = (library.surfacePinstripe,
                       [finish.pinstripeCoefficients(size: proxy.size)])
            case .carbonTwill:
                arm = (library.surfaceCarbonTwill,
                       [finish.twillCoefficients(size: proxy.size, lightAzimuth: azimuth)])
            case .topographic:
                arm = (library.surfaceTopographic,
                       [finish.topographicCoefficients(size: proxy.size)])
            case .basketweave:
                arm = (library.surfaceBasketweave,
                       [finish.basketweaveCoefficients(size: proxy.size, lightAzimuth: azimuth)])
            case .clousDeParis:
                arm = (library.surfaceClousDeParis,
                       [finish.clousCoefficients(size: proxy.size)])
            case .knurling:
                arm = (library.surfaceKnurling,
                       [finish.knurlCoefficients(size: proxy.size)])
            case .sandblasted:
                arm = (library.surfaceSandblasted,
                       [finish.blastCoefficients(size: proxy.size)])
            case .sunburst:
                arm = (library.surfaceSunburst,
                       [finish.sunburstCoefficients(size: proxy.size)])
            }

            let shader = Shader(
                function: arm.0,
                arguments: common + arm.1.flatMap { c in
                    c.registers.map { r in
                        Shader.Argument.float4(r.x, r.y, r.z, r.w)
                    }
                }
            )
            return view.colorEffect(shader)
        }
    }
}
