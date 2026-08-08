#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// A metallic finish over flat SwiftUI content.
//
// Do not retune these constants individually. They are a single calibrated set,
// and several are load-bearing in non-obvious ways. The comments say which.
//
// The one exception is the tint, which arrives as a uniform. It says *which*
// metal, not how metal behaves, so it can vary without re-solving the rest. See
// SurfaceMaterial.swift.

namespace SurfaceForge {

// MARK: - The finish

constant float kSpecularPower    = 60.0;
constant float kSpecularStrength = 0.55;

// The laminate over metal leaf is still a dielectric, so F0 stays 0.04 and the
// coat is untinted white. The leaf's colour is already carried by the tint;
// tinting the coat too would double-count it and push gold toward orange.
constant float kCoatPower       = 160.0;
constant float kCoatStrength    = 0.45;
constant float kCoatFresnelF0   = 0.040;
constant float kCoatRimStrength = 0.26;
constant float kEnvironmentGain = 0.85;

// The scene light. diffuse = 0.30 + 0.66 * max(dot(N, L), 0). On a flat sheet
// with L.z about 0.86 that lands at 0.868, which is the substrate luminance the
// stored tints were chosen against.
constant float kAmbientStrength = 0.30;
constant float kDiffuseStrength = 0.66;

// The analytic room, in linear radiance. The bands are surfaces and stay at or
// below 1. The window is a light source and legitimately exceeds 1, which is
// exactly what lets a 4%-reflectance coat throw a visible gleam across a
// 0.87-luminance surface.
constant float kSkyRadiance     = 0.85;
constant float kHorizonRadiance = 0.42;
constant float kFloorRadiance   = 0.10;
constant float kWindowRadiance  = 5.5;

// 60 gives an 8.69-degree half-width. The reflection vector sweeps about 30
// degrees edge to edge, 44 once the bow below is added, so the window covers
// roughly a third of the width and has a real edge instead of washing the whole
// surface.
constant float kWindowExponent = 60.0;

// Legibility. Content has to stay readable under the metal: a dim sheen over
// dark marks, full effect over the bare surface.
constant float kSheenLegibilityFloor = 0.32;
constant float kSheenLegibilityGain  = 0.68;

// The coat's ceiling. A gleam crossing a glyph must never erase it. The gleam
// also moves, so nothing is permanently obscured.
constant float kCoatCeiling = 0.75;

// How much of the sheen's legibility factor the coat also takes.
//
// At zero the gleam washes content out as it crosses. kCoatCeiling alone does not
// prevent that: the coat is added directly, so a fragment gains up to 0.75 in
// linear light, 226/255, however dark it arrived. This damps that gain by how
// dark the content is, so it bites on glyphs and leaves the band over bare
// surface alone. Lowering kCoatCeiling instead is the wrong lever, because that
// dims the gleam where the effect lives.
//
// Ink-to-surface contrast inside the gleam's own 120px window, captured at four
// light angles, worst first. Read as what each setting buys, not as a log:
//
//     angle    off    0.50    0.85
//         a   67.0    74.6    81.8      (+11% / +22%)
//         b   74.6    83.3    93.5      (+12% / +25%)
//         c  116.5   121.7   126.5      ( +4% /  +9%)
//         d  137.9   135.1   133.3      ( -2% /  -3%, gleam is off the marks)
//
// 0.85 buys roughly double what 0.50 does, and costs about 4/255 of surface
// brightness against 0.50's 2. Neither visibly dims the metal.
//
// Not full damping. The coat crossing content is the single cue that makes this
// read as light on a surface rather than as printed metallic art. The point is
// to stop it erasing, not to stop it happening.
constant float kCoatLegibility = 0.85;

// MARK: - Flat-sheet geometry

// A SwiftUI view is flat, so N is constant, dot(N, H) is one number for the
// whole surface, and no highlight can live anywhere. The answer is a positional
// virtual eye, so V varies per fragment while the projection stays orthographic
// and the layout undistorted.
//
// The eye is solved on the CPU from the dot(N, V) envelope and passed in. See
// SurfaceShading.virtualEye(halfHeight:). It reads only halfHeight, which is one
// value for the whole surface, but a uniform is opaque to the compiler, so
// evaluating it here cost a sqrt and a divide on every device pixel every frame.

// A gentle cylindrical bow about the short axis, convex toward the viewer. How a
// card actually sits when it is held. 0.030 half-widths is 1 to 2mm of sag on a
// 9cm surface.
//
// Chosen, not guessed: the edge slope is 0.060, giving 3.4 degrees of normal tilt
// and so 6.9 degrees of reflection swing, since a reflection doubles the normal's
// tilt. That sits just under the window lobe's 8.69-degree half-width, which
// makes it the largest bow the window can still resolve. It widens the total
// reflection sweep from 30.5 to 44.3 degrees, compressing the gleam from 57% of
// the width to 39%. That is the difference between a wash and a band. Above this
// the gleam starts to tear in two.
constant float kBowAmplitude = 0.030;

// Micro-cockle. Beaten leaf laid on a surface is never optically flat, and
// without this every isophote is a perfect conic, which reads as airbrush rather
// than metal. Three plane waves at mutually irrational angles: no visible repeat
// inside the surface, no texture fetch, and the gradient is analytic so the
// normal is exact at any backing scale. fwidth would alias on a 3x store.
//
// Wavelengths land at 93 to 152pt across a 353pt surface: 2 to 4 undulations,
// which is cockle, not bumps.
constant float3 kCockleFrequencyU = float3( 7.30, -4.10, 11.90);
constant float3 kCockleFrequencyV = float3( 3.10,  9.70, -6.30);
constant float3 kCocklePhase      = float3( 0.00,  2.39,  4.11);
constant float3 kCockleWeight     = float3( 0.44,  0.34,  0.22);   // sums to 1

// Peak slope about 0.018, so 1.04 degrees of normal and 2.1 of reflection: a
// quarter of the window half-width. Enough to make the highlight shimmer as it
// travels, not enough to read as a texture.
constant float kCockleAmplitude = 0.0020;

// MARK: - Colour space

// Verified, not assumed. surfaceGreyProbe returning half4(0.5) renders to exactly
// (128,128,128), the same pixel as Color(white: 0.5), so SwiftUI hands
// colorEffect sRGB-encoded values rather than linear ones. Had it been linear,
// 0.5 would have encoded to 187, which is 59 levels away and could not be
// mistaken.
//
// This matters because every constant above was calibrated in linear light.
// Shading sRGB-encoded values would deliver the 0.868 substrate luminance as
// 0.94, driving the base past the soft shoulder before the gleam contributes
// anything, and the metal would read as coloured plastic.
constant bool kInputIsSRGBEncoded = true;

inline float3 srgbToLinear(float3 c) {
    c = max(c, 0.0);
    return select(c / 12.92,
                  pow((c + 0.055) / 1.055, 2.4),
                  c > 0.04045);
}

inline float3 linearToSRGB(float3 c) {
    c = max(c, 0.0);
    return select(c * 12.92,
                  1.055 * pow(c, 1.0 / 2.4) - 0.055,
                  c > 0.0031308);
}

// MARK: - Shading

/// Surface coordinates: u in [-1, +1] across the width, v in [-h, +h].
inline float2 surfaceCoordinates(float2 position, float2 viewSize, float halfHeight) {
    float2 uv = position / max(viewSize, float2(1.0));
    return float2(uv.x * 2.0 - 1.0, (1.0 - uv.y * 2.0) * halfHeight);
}

/// Derives the ratio rather than being handed it, for the probes below.
inline float2 surfaceCoordinates(float2 position, float2 viewSize) {
    float2 size = max(viewSize, float2(1.0));
    return surfaceCoordinates(position, size, size.y / size.x);
}

// A room, analytically. Twelve ALU, no cubemap, no texture fetch, and it is the
// entire difference between a coat that reflects something and one that reflects
// nothing. A clear coat with nothing to reflect still reads as paint.
//
// On a flat surface R.z stays within [0.87, 0.98], so the bands evaluate to pure
// sky and do not vary. They are kept because the bow perturbs into them. The
// travelling gleam comes entirely from the window lobe, which does vary, because
// R does.
inline float sampleAnalyticEnvironment(float3 direction, float windowCoupling) {
    float elevation   = direction.z;
    float sky         = smoothstep(0.10, 0.55, elevation);
    float floorAmount = smoothstep(-0.05, -0.45, elevation);
    float horizon     = saturate(1.0 - sky - floorAmount);
    float ambient = kSkyRadiance * sky
                  + kHorizonRadiance * horizon
                  + kFloorRadiance * floorAmount;
    return (ambient + windowCoupling * kWindowRadiance) * kEnvironmentGain;
}

// A Reinhard shoulder above 0.80 rather than a flat clip. The coat's core
// routinely exceeds 1.0 over a near-white substrate, and saturate() turned that
// into a white plateau with a hard edge: the look of a blown-out JPEG, not of a
// gleam. Values below 0.80 are exactly unchanged, so this cannot perturb the
// resting surface.
inline float3 softShoulder(float3 color) {
    float3 low    = min(color, 0.80);
    float3 excess = max(color - 0.80, 0.0);
    return low + 0.20 * (excess / (excess + 0.2001));
}

/// The shading normal.
///
/// This is where a cut belongs, if one is ever added. N feeds the diffuse, the
/// sheen's NdotH, the coat's Fresnel NdotV, the coat's specular and, through
/// reflect(-V, N), the window lobe. Tilting it at an edge makes all five respond
/// from constants that are already calibrated, instead of introducing a sixth
/// that is not. It is the same mechanism kBowAmplitude and kCockleAmplitude use,
/// one scale down.
inline float3 surfaceNormal(float2 p) {
    float3 arg    = kCockleFrequencyU * p.x + kCockleFrequencyV * p.y + kCocklePhase;
    float3 cosArg = cos(arg);
    // z(u,v) = -kBow * u^2 + cockle, so N is proportional to (-dz/du, -dz/dv, 1)
    float2 slope = float2(-2.0 * kBowAmplitude * p.x, 0.0)
                 + kCockleAmplitude
                     * float2(dot(kCockleWeight * kCockleFrequencyU, cosArg),
                              dot(kCockleWeight * kCockleFrequencyV, cosArg));
    return normalize(float3(-slope.x, -slope.y, 1.0));
}

}  // namespace SurfaceForge

// MARK: - Entry point

/// A metallic finish, applied as a filter over composited content.
///
/// `colorEffect`, not `layerEffect`: the normal is analytic, so no fragment ever
/// reads a neighbour. `(position, color)` is exactly and only the input this
/// model consumes.
///
/// A filter over the content rather than a layer behind it, which buys three
/// things a background layer structurally cannot:
///
/// - `metalTint * baseLuminance` retints the near-white surface to metal while
///   dark content stays dark. Legibility comes from the model, not by hand.
/// - `sheenLegibility` damps the broad sheen over glyphs, fully.
/// - The coat takes only `kCoatLegibility` of that damping, deliberately, so the
///   gleam crosses the content. That single cue is what makes this read as a
///   reflection on a surface rather than as printed metallic art. A background
///   layer cannot do it, because the content would occlude the highlight.
///
/// One constraint follows, and callers must respect it: chroma is discarded by
/// the luminance step, so content is read as lightness alone. A violet accent
/// simply becomes metal at violet's brightness.
[[stitchable]] half4 surfaceMetal(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,           // (ey, ez), solved on the CPU. See virtualEye above
    float  halfHeight,    // viewSize.y / viewSize.x, likewise
    float3 keyDirection,  // room panel and specular, rotated by device tilt
    float3 diffuseAxis,   // the coherent scene light
    float  gleamAmount,   // 0...1, how much reflection shows. Gates the window,
                          // the coat's own specular and the sheen, and not the
                          // substrate's diffuse term. The CPU walks diffuseAxis
                          // home instead, in SurfaceShading.lights(). At 0
                          // nothing below reads either direction, which is what
                          // lets the light be re-placed with nothing moving.
    float3 metalTint      // which metal
) {
    using namespace SurfaceForge;

    // Premultiplied in, premultiplied out.
    float alpha = float(color.a);
    if (alpha <= 0.0) { return half4(0.0h); }
    float3 baseStraight = float3(color.rgb) / alpha;
    if (kInputIsSRGBEncoded) { baseStraight = srgbToLinear(baseStraight); }

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);
    float3 V = normalize(float3(-p.x, eye.x - p.y, eye.y));
    float3 N = surfaceNormal(p);

    // --- Substrate ---------------------------------------------------------
    float  diffuse = kAmbientStrength
                   + kDiffuseStrength * max(dot(N, diffuseAxis), 0.0);
    float3 litBase = saturate(baseStraight * diffuse);
    float  baseLuminance   = dot(litBase, float3(0.299, 0.587, 0.114));
    float  sheenLegibility = kSheenLegibilityFloor
                           + kSheenLegibilityGain * baseLuminance;

    // Metal leaf: the substrate takes the metal's colour scaled by its own
    // luminance, so a light surface turns metal while dark content stays dark and
    // legible instead of being flooded. Metalness is 1, so this is not a mix.
    float3 surfaceBase = metalTint * baseLuminance;
    // Metals tint what they reflect; dielectrics reflect the light's own colour.
    // At metalness 1 this is the tint.
    float3 specularTint = metalTint;

    // --- The lobes ---------------------------------------------------------
    // The key light is directional here. What is not optional is that it is aimed
    // at the mirror of the eye rather than at the diffuse axis: on this plane the
    // diffuse axis sits about 44 degrees off the mirror everywhere,
    // pow(dot(N, H), 160) evaluates to 5.8e-6, and there is nowhere the half
    // vector can meet the normal.
    float3 H     = normalize(keyDirection + V);
    float  NdotH = max(dot(N, H), 0.0);

    float highlightAmount = pow(NdotH, kSpecularPower) * kSpecularStrength;

    float3 R = reflect(-V, N);
    // The window rides the same direction as the key light, so the broad
    // Blinn-Phong halo and the hot window core stay concentric instead of
    // fighting each other across the surface.
    //
    // Gated by gleamAmount here rather than on the composited coat below. The
    // window is the only term in the environment that reads keyDirection at all,
    // since R is a function of position and normal only, so fading it leaves the
    // flat sky the clear coat reflects intact while making what survives
    // independent of where the light is. That independence is what lets the model
    // park the light at zero gleam with nothing moving on screen. Gating the
    // whole coat instead would also take the sky, and the surface would go
    // visibly flatter.
    float windowCoupling      = pow(saturate(dot(R, keyDirection)), kWindowExponent)
                              * gleamAmount;
    float environmentRadiance = sampleAnalyticEnvironment(R, windowCoupling);

    // Schlick. On a flat surface dot(N, V) runs 0.873 to 0.980, so the Fresnel
    // term is essentially a flat F0 and the coat's whole visible effect comes from
    // what it reflects. The grazing terms only wake up where the bow steepens the
    // normal. Do not raise kCoatRimStrength trying to make the resting surface
    // glow, because that is the environment's job.
    float coatNdotV   = saturate(dot(N, V));
    float grazing     = 1.0 - coatNdotV;
    float grazing2    = grazing * grazing;
    float coatFresnel = kCoatFresnelF0
                      + (1.0 - kCoatFresnelF0) * grazing2 * grazing2 * grazing;
    // The grazing rim multiplies the Fresnel-weighted environment, so it can
    // never manufacture energy.
    float coatReflectance = coatFresnel
                          * (1.0 + kCoatRimStrength * grazing2 * grazing2);
    float coatSpecular    = pow(NdotH, kCoatPower) * kCoatStrength * coatFresnel;

    // Not multiplied by alpha here. `straight` is premultiplied once at the
    // return, and doing it in both places squares the coverage, so on every
    // antialiased edge pixel the coat would fall off as alpha^2 while the surface
    // under it fell off as alpha, and the gleam would die faster than the surface
    // it sits on. Invisible at full coverage, which is why it survives review:
    // 1 * 1 = 1. Any cut added later belongs in that same single place.
    //
    // The legibility damp is applied after the ceiling, not before, because the
    // ceiling is what kCoatLegibility was measured against: the gleam's core is
    // clamped first, and the content's own darkness then decides how much of that
    // clamped value survives. Folded in before the min instead, a bright enough
    // core would clip back to the ceiling and the damp would do nothing at
    // exactly the intensity it exists for.
    float coatLegibility = mix(1.0, sheenLegibility, kCoatLegibility);
    float3 coatColor = min(
        float3(coatReflectance * environmentRadiance + coatSpecular * gleamAmount),
        float3(kCoatCeiling)
    ) * coatLegibility;

    // --- Composite ---------------------------------------------------------
    // The base sheen goes through the remaining headroom and the full legibility
    // factor; the coat adds directly and takes only kCoatLegibility of it. That
    // asymmetry is deliberate: the sheen is a property of the surface underneath,
    // the coat is light sitting on top of it. Writing `+ highlightAmount` instead
    // over-brightens the metal body by roughly 2x at the specular peak.
    float3 straight = surfaceBase
                    + (1.0 - surfaceBase) * float3(highlightAmount)
                        * specularTint * sheenLegibility * gleamAmount
                    + coatColor;
    straight = softShoulder(max(straight, 0.0));

    if (kInputIsSRGBEncoded) { straight = linearToSRGB(straight); }

    return half4(half3(saturate(straight) * alpha), half(alpha));
}

// MARK: - Probes

/// Paints magenta, reads nothing.
///
/// SwiftUI leaves a view untouched when a shader fails to resolve, so a missing
/// metallib looks like a working build. Magenta cannot be mistaken for a real
/// surface.
[[stitchable]] half4 surfaceProbe(float2 position, half4 color) {
    return half4(1.0h, 0.0h, 1.0h, 1.0h);
}

/// Returns mid grey, to check what colour space SwiftUI hands this shader.
///
/// Renders (128,128,128) if values arrive sRGB-encoded, 187 if linear. Every
/// constant in this file is calibrated for the former, so if a future SDK changes
/// it, this is the only thing that will say so.
[[stitchable]] half4 surfaceGreyProbe(float2 position, half4 color) {
    return half4(0.5h, 0.5h, 0.5h, 1.0h);
}

/// The shading normal as colour. The only way to see whether the bow and cockle
/// amplitudes are what the comments claim. Flat blue means the perturbation is
/// not running.
[[stitchable]] half4 surfaceNormalProbe(float2 position, half4 color, float2 viewSize) {
    using namespace SurfaceForge;
    float3 N = surfaceNormal(surfaceCoordinates(position, viewSize));
    return half4(half3(N * 0.5 + 0.5), 1.0h);
}
