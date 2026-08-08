import SwiftUI

/// Answers whether the package's shaders resolve at runtime.
///
/// Magenta means the metallib loaded from the package bundle. Grey means it did
/// not: SwiftUI leaves a view untouched when a shader fails to resolve, so a
/// material built on a missing library renders as plain content instead of
/// raising.
///
/// Temporary. Delete once `Surface` ships a real material and the demo app
/// proves the same thing by looking correct.
struct SurfaceShaderProbe: View {
    var body: some View {
        Rectangle()
            .fill(.gray)
            .frame(width: 160, height: 60)
            .colorEffect(ShaderLibrary.bundle(.module).surfaceProbe())
    }
}

#Preview {
    SurfaceShaderProbe()
}
