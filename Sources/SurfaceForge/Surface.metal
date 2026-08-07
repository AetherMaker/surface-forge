#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Paints magenta, reads nothing.
//
// SwiftUI leaves a view untouched when a shader fails to resolve, so a missing
// metallib looks like a working build. Magenta cannot be mistaken for a real
// surface.
[[stitchable]] half4 surfaceProbe(float2 position, half4 color) {
    return half4(1.0h, 0.0h, 1.0h, 1.0h);
}
