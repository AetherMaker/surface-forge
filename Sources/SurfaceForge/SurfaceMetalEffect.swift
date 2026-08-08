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
        gleam: Double
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

            return view.colorEffect(
                ShaderLibrary.bundle(.module).surfaceMetal(
                    .float2(proxy.size),
                    // Spelled out component-wise: the multi-Float overloads are
                    // the ones guaranteed across SDK revisions.
                    .float2(Float(eye.y), Float(eye.z)),
                    .float(Float(halfHeight)),
                    .float3(lights.key.x, lights.key.y, lights.key.z),
                    .float3(lights.diffuse.x, lights.diffuse.y, lights.diffuse.z),
                    .float(amount),
                    .float3(tint.x, tint.y, tint.z)
                )
            )
        }
    }
}
