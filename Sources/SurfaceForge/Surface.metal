#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Paints magenta and reads nothing. Its only job is to answer one question:
// does SwiftUI find this file's compiled metallib inside the package bundle?
//
// A shader that fails to resolve draws the view untouched rather than raising,
// so without a probe whose output cannot be mistaken for a real surface, every
// later material would fail silently.
[[stitchable]] half4 surfaceProbe(float2 position, half4 color) {
    return half4(1.0h, 0.0h, 1.0h, 1.0h);
}
