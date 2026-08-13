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

// How tight the window is arrives as a uniform, because it is what separates a
// polished metal from a rough one. 60 gives an 8.69-degree half-width, which
// covers roughly a third of the surface. Lower spreads it, and past about 100 it
// stops narrowing.

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

// MARK: - Brushing

// A brushed metal is a field of parallel grooves. A groove scatters light across
// itself and not along itself, so the highlight spreads one way and stays tight
// the other. That stretch is most of what separates brushed from polished, and it
// is one direction-dependent exponent rather than a second lobe.

// Divides the along-grain exponent, so 3 makes the highlight sqrt(3) longer.
// Widening only: tightening splits the band over the bow (silver would reach
// 330 against its calibrated 110). 9 was tried and dissolved the band into a
// wash.
constant float kBrushedRatio = 3.0;

// Keeps the weighting finite where the half vector meets the normal exactly. At
// the highlight's own peak both projections vanish and a plain ratio is 0/0.
// Added to both sides, so that case resolves to 1, which is isotropic, and a peak
// carries no direction to be anisotropic about. It only outweighs a real
// projection below 1e-6 of deviation, a ten-thousandth of a degree.
constant float kBrushedFloor = 1.0e-12;

/// How far the grain widens a lobe, as a multiplier on its exponent.
///
/// `brushing` is (amount, cos, sin) of the axis the highlight stretches along.
/// Uniform for a straight grain and solved per fragment by the sunburst arm;
/// either way the axis lives in the surface, never in the light.
///
/// `D` is the lobe's direction and `axis` its peak: H against N for the sheen,
/// R against the key for the window. Each lobe reads its own deviation. The
/// window once borrowed the sheen's stretch, which moves with the light, so
/// the band changed shape as it travelled instead of sliding.
///
/// Times the squared deviation, the result is along²/ratio + across²: one
/// quadratic fixed in the surface, so the light can move and dim the band but
/// never reshape it. And never above 1, so no direction tightens past the
/// exponent the bow was calibrated against.
///
/// Measured from the deviation, not from `D` itself: the bow leans N by up to
/// 3.4 degrees, and a raw projection would read that lean as grain.
///
/// `mix` keeps polished exact. `a + 0 * (b - a)` is an exact 1.0 for any
/// finite stretch, which is why ``SurfaceFinish/brushed(angle:)`` will not
/// pass a NaN through.
inline float grainStretch(float3 D, float3 axis, float DdotAxis, float3 brushing) {
    float2 planar = D.xy - axis.xy * DdotAxis;
    float2 grain  = brushing.yz;
    float along   = dot(planar, grain);
    float across  = planar.x * -grain.y + planar.y * grain.x;
    along  *= along;
    across *= across;

    float stretch = (along / kBrushedRatio + across + kBrushedFloor)
                  / (along + across + kBrushedFloor);

    return mix(1.0, stretch, brushing.x);
}

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
inline float2 surfaceSlope(float2 p) {
    float3 arg    = kCockleFrequencyU * p.x + kCockleFrequencyV * p.y + kCocklePhase;
    float3 cosArg = cos(arg);
    // z(u,v) = -kBow * u^2 + cockle, so N is proportional to (-dz/du, -dz/dv, 1)
    return float2(-2.0 * kBowAmplitude * p.x, 0.0)
         + kCockleAmplitude
             * float2(dot(kCockleWeight * kCockleFrequencyU, cosArg),
                      dot(kCockleWeight * kCockleFrequencyV, cosArg));
}

/// Split out so the lines can add to the slope before it becomes a normal.
/// Recovering a slope back out of a finished normal is not an exact round trip.
inline float3 normalFromSlope(float2 slope) {
    return normalize(float3(-slope.x, -slope.y, 1.0));
}

inline float3 surfaceNormal(float2 p) {
    return normalFromSlope(surfaceSlope(p));
}

// MARK: - The lines

// Brushing cuts lines into the metal. These are the lines, and the stretch above is
// what they do to light.
//
// Straight and evenly spaced, with no wander and no variation in density. Every
// attempt at making them look organic turned them into wood grain, because an
// organic directional pattern is what wood grain is. A brushed surface is ruled.
//
// One line every 4 points, so a line is about 2 points across: 4 device pixels at 2x
// and 6 at 3x. A real brush line is nearer one pixel and cannot hold a lit side and
// a dark side at that width, so these are deliberately coarser than physical. That
// is the whole reason they are visible.
constant float kLinePitch = 4.0;

// How far a groove darkens whatever the light is doing. Without it the lines
// only appear where the gleam crosses them, and a brushed surface shows its
// lines on a still card.
constant float kLineInk = 0.12;

// And how much more the wall facing away from the light takes, which is what gives
// a groove a bright side and a dark side and swaps them as the surface tilts.
constant float kLineWall = 0.09;

// The groove's own steepness, so the lines reach the gleam as well as the substrate.
// Well under the cockle's 0.018, because a line is far finer than a cockle wave and
// the same slope over a shorter distance is a much sharper crease.
constant float kLineSlope = 0.012;

/// One groove's anatomy, shared by every arm that cuts lines.
///
/// `wall` is odd about the groove's centre, one wall then the other. `hollow`
/// is even and deepest in the cut. The phase convention is fixed by the slope:
/// a slope of sin(phase) integrates to a height whose trough sits at phase
/// zero, so the hollow must peak there too or the ink lands on the crest and
/// the lines read as printed ribs rather than cut grooves.
inline void groove(float phase, thread float &wall, thread float &hollow) {
    wall   = sin(phase);
    hollow = 0.5 + 0.5 * cos(phase);
}

/// The lines' slope, and how far they darken the substrate.
///
/// Exactly zero and exactly one at zero brushing, so a polished surface keeps the
/// normal and the substrate it had.
inline void engraved(
    float2 p,
    float3 brushing,
    float  width,
    float2 lightAzimuth,
    thread float2 &slope,
    thread float &shade
) {
    // `brushing.yz` is perpendicular to the stroke, so the phase runs across the
    // lines and the lines themselves run along it. One turn of phase per pitch,
    // measured in points, so the lines are the same width on any size of surface.
    float2 across = brushing.yz;
    float  phase  = dot(p, across) * (max(width, 1.0) * (M_PI_F / kLinePitch));

    float wall;
    float hollow;
    groove(phase, wall, hollow);

    slope = across * (kLineSlope * brushing.x * wall);
    shade = 1.0
          - brushing.x * (kLineInk * hollow
                          + kLineWall * wall * dot(across, lightAzimuth));
}

}  // namespace SurfaceForge

// MARK: - The body

/// The calibrated metal every finish funnels into.
///
/// `finishSlope` tilts the shading normal. `finishShade` multiplies the
/// substrate after the legibility read, so a pattern can be as strong as taste
/// allows without costing text contrast. `brushing` reshapes the highlight.
///
/// `Grained` is a compile-time switch, so the eight grainless arms do not pay
/// grainStretch's divides per fragment to compute a value `mix` would discard.
/// `p` arrives from the arm, which already computed it for its own pattern.
template <bool Grained>
inline half4 metalBody(
    float2 p,
    half4  color,
    float2 eye,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float3 brushing,
    float2 finishSlope,
    float  finishShade
) {
    using namespace SurfaceForge;

    // Premultiplied in, premultiplied out.
    float alpha = float(color.a);
    if (alpha <= 0.0) { return half4(0.0h); }
    float3 baseStraight = float3(color.rgb) / alpha;
    if (kInputIsSRGBEncoded) { baseStraight = srgbToLinear(baseStraight); }

    float3 V = normalize(float3(-p.x, eye.x - p.y, eye.y));

    // The finish adds to the slope before it becomes a normal, so at zero slope
    // the normal is the one a polished surface had.
    float3 N = normalFromSlope(surfaceSlope(p) + finishSlope);

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
    // The finish darkens here rather than on `baseLuminance`, so the legibility
    // damping never mistakes a groove for the author's content. Clamped because a
    // lit groove wall pushes the substrate up.
    float3 surfaceBase = min(metalTint * baseLuminance * finishShade, 1.0);
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

    float3 R = reflect(-V, N);

    // Each lobe is stretched about its own peak, the sheen from H off N and the
    // window from R off the key below, which is what grainStretch requires of
    // its callers.
    float stretch = Grained ? grainStretch(H, N, NdotH, brushing) : 1.0;

    float highlightAmount = pow(NdotH, kSpecularPower * stretch) * kSpecularStrength;

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
    float RdotKey        = saturate(dot(R, keyDirection));
    float windowStretch  = Grained ? grainStretch(R, keyDirection, RdotKey, brushing)
                                   : 1.0;
    float windowCoupling = pow(RdotKey, windowExponent * windowStretch)
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

// MARK: - Entry points

// One [[stitchable]] arm per finish, not a branch on a uniform. Each arm turns
// its pattern into a slope and a shade, then funnels into metalBody. Solvers in
// SurfaceFinish.swift pre-multiply every coefficient, so an arm never computes a
// value that is uniform across the surface.

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
    float3 metalTint,     // which metal
    float windowExponent, // how tight this metal's travelling band is
    float4 brushing       // (amount, cos, sin, 0) of the grain. Zero amount
                          // renders exactly what polished renders; the fourth
                          // lane exists so the register matches its siblings
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);
    float2 lineSlope;
    float  lineShade;
    engraved(p, brushing.xyz, viewSize.x, diffuseAxis.xy, lineSlope, lineShade);

    return metalBody<true>(p, color, eye, keyDirection, diffuseAxis,
                           gleamAmount, metalTint, windowExponent, brushing.xyz,
                           lineSlope, lineShade);
}

/// Polished, on its own arm so the default finish never pays for grooves or
/// grain it does not have. Renders byte-identically to surfaceMetal with zero
/// brushing: the constants passed here are exactly what engraved and
/// grainStretch produce at zero, and the render test that compares the two
/// arms is what says so.
[[stitchable]] half4 surfacePolished(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);
    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0),
                            float2(0.0), 1.0);
}

/// Pinstripe: straight engraved grooves, coarser than brushing, round highlight.
///
/// `stripe` is (phase.x, phase.y, slope, ink) and `axis` is (across.x, across.y,
/// wall, 0), solved in SurfaceFinish.pinstripeCoefficients. Zero brushing into
/// the body, because a groove this coarse decorates the metal without reworking
/// how it scatters.
[[stitchable]] half4 surfacePinstripe(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 stripe,
    float4 axis
) {
    using namespace SurfaceForge;

    float2 p      = surfaceCoordinates(position, viewSize, halfHeight);
    float  phase = dot(p, stripe.xy);
    float  wall;
    float  hollow;
    groove(phase, wall, hollow);
    // The hollow cubed narrows the line to about a fifth of the pitch, and the
    // wall is windowed by the same square so the cut is a thin V in otherwise
    // flat metal. An unwindowed sine here rolled the whole pitch into soft
    // ribs and the finish read as corduroy, not pinstripe.
    float  line = hollow * hollow * hollow;
    float  cut  = wall * hollow * hollow;

    float2 slope = axis.xy * (stripe.z * cut);
    float  shade = 1.0 - (stripe.w * line
                          + axis.z * cut * dot(axis.xy, diffuseAxis.xy));

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
}

/// Carbon twill: a 2x2 weave of crowned tows, half running each way.
///
/// `twill` is (cells per unit, crown slope, ink, sheen) and `light` carries the
/// diffuse light's unit azimuth, all solved in SurfaceFinish.twillCoefficients.
/// Each tow is a shallow half-cylinder, so its crown gives it a lit wall and a
/// dark wall; the sheen term brightens tows whose fibres run with the light,
/// which is the cue that reads as fibre rather than checkerboard.
[[stitchable]] half4 surfaceCarbonTwill(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 twill,
    float4 light
) {
    using namespace SurfaceForge;

    float2 p    = surfaceCoordinates(position, viewSize, halfHeight);
    float2 q    = p * twill.x;
    float2 cell = floor(q);
    float2 f    = q - cell;

    // 2x2 twill: pairs of cells show the vertical tow, stepping one cell per
    // row, which is what draws the weave's 45-degree diagonal.
    float step     = cell.x - cell.y;
    float phase4   = step - 4.0 * floor(step * 0.25);
    float vertical = phase4 < 2.0 ? 1.0 : 0.0;

    // The crown runs across whichever way this cell's tow lies, and is zero at
    // both edges of the cell, so neighbouring tows meet without a step in the
    // normal.
    float acrossTow = mix(f.y, f.x, vertical);
    float crown     = sin(acrossTow * (2.0 * M_PI_F)) * twill.y;
    float2 slope    = float2(crown * vertical, crown * (1.0 - vertical));

    // A seam shadow where the tow dives under its neighbour, and a sheen on
    // tows lying along the light.
    float  lying = mix(abs(light.x), abs(light.y), vertical);
    float  seam  = 0.5 + 0.5 * cos(acrossTow * (2.0 * M_PI_F));
    float  shade = 1.0 - twill.z * seam + twill.w * (lying - 0.5);

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
}

/// Knurling: two crossed families of shallow grooves, the diamond cut.
///
/// `knurl` is the two phase vectors and `cut` is (slope, ink, 1/|phase|),
/// solved in SurfaceFinish.knurlCoefficients. Cut shallow on purpose: each
/// family takes half the slope budget, because the first attempt at knurling
/// cut to full depth and the crossed grooves dashed the gleam into segments.
[[stitchable]] half4 surfaceKnurling(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 knurl,
    float4 cut
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);

    float phaseA  = dot(p, knurl.xy);
    float phaseB  = dot(p, knurl.zw);
    float wallA;
    float wallB;
    float hollowA;
    float hollowB;
    groove(phaseA, wallA, hollowA);
    groove(phaseB, wallB, hollowB);

    // Each family's slope runs along its own phase vector, rescaled to unit
    // length on the CPU through cut.z.
    float2 slope = (knurl.xy * wallA + knurl.zw * wallB) * (cut.x * cut.z);
    float  shade = 1.0 - cut.y * (hollowA + hollowB) * 0.5;

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
}

// The sandblast mottle: two products of plane waves at mutually irrational
// angles, so the blotches never repeat inside the card. Mirrored in
// SurfaceFinish for the solver's reference pitch.
constant float2 kBlastA = float2( 96.0, -55.0);
constant float2 kBlastB = float2( 43.0, 101.0);
constant float2 kBlastC = float2(-71.0,  83.0);

/// Sandblasted: the bead-blast matte, a fine even mottle and nothing else.
///
/// `blast` is (frequency scale, mottle depth), solved in
/// SurfaceFinish.blastCoefficients. Shade only, no slope: the first version
/// carried its mottle in the normal and rendered as nothing, because sub-pixel
/// normal perturbation is mathematically a roughness increase, and roughness
/// is already the material's own dial. The shade is sized to clear the 8-bit
/// quantum, which is the other way the first version vanished.
[[stitchable]] half4 surfaceSandblasted(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 blast
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);

    float a = dot(p, kBlastA) * blast.x;
    float b = dot(p, kBlastB) * blast.x;
    float c = dot(p, kBlastC) * blast.x;

    float mottle = 0.5 + 0.3 * sin(a) * sin(b) + 0.2 * sin(c) * cos(a);
    float shade  = 1.0 - blast.y * mottle;

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), float2(0.0), shade);
}

/// Sunburst: the brushed finish bent into a circle. Rings for lines, and the
/// grain axis solved per fragment as the radial direction, so the highlight
/// streaks along the radius the way spun metal streaks.
///
/// `burst` is (ring phase per unit, stretch amount), solved in
/// SurfaceFinish.sunburstCoefficients. Everything else reuses the brush line
/// constants, because a sunburst is the same cut on a turning workpiece.
///
/// The one arm that hands metalBody a non-uniform brushing, which is exactly
/// what grainStretch's surface-fixed quadratic permits: the axis varies over
/// the surface, never with the light.
[[stitchable]] half4 surfaceSunburst(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 burst
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);
    float  r = length(p);
    // The centre has no direction to be radial about; any unit axis serves,
    // because every term it feeds is zero there.
    float2 radial = r > 1.0e-4 ? p / r : float2(0.0, 1.0);

    float phase = r * burst.x;
    float wall;
    float hollow;
    groove(phase, wall, hollow);

    float2 slope = radial * (kLineSlope * wall);
    float  shade = 1.0 - (kLineInk * hollow
                          + kLineWall * wall * dot(radial, diffuseAxis.xy));

    return metalBody<true>(p, color, eye, keyDirection, diffuseAxis,
                           gleamAmount, metalTint, windowExponent,
                           float3(burst.y, radial.x, radial.y), slope, shade);
}

/// Clous de Paris: the hobnail grid, filtered. A field of rounded studs whose
/// four faces each catch the light differently, with the valleys inked.
///
/// `clous` is (grid frequency per unit, peak slope, valley ink, 0), solved in
/// SurfaceFinish.clousCoefficients. The sharp pyramid was tried and rejected:
/// its creases alias against the resample grid, and the filtered stud reads as
/// the same pattern at arm's length.
[[stitchable]] half4 surfaceClousDeParis(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 clous
) {
    using namespace SurfaceForge;

    float2 p   = surfaceCoordinates(position, viewSize, halfHeight);
    float2 arg = p * clous.x;
    float2 s   = sin(arg);
    float2 c   = cos(arg);

    // The egg-crate field cos(x)cos(y): studs on the grid, diagonal valleys.
    float2 slope = clous.y * float2(-s.x * c.y, -c.x * s.y);
    float  depth = 0.5 - 0.5 * (c.x * c.y);
    float  shade = 1.0 - clous.z * depth;

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
}

/// Basketweave: blocks of parallel ribs alternating direction like woven
/// strap, each block ringed by a hard crease.
///
/// `weave` is (blocks per unit, rib slope, rib ink, rib phase per block) and
/// `crease` is (crease half-width as a block fraction, crease ink, then the
/// light's azimuth pre-scaled by the wall amount), solved in
/// SurfaceFinish.basketweaveCoefficients. The crease is what sells the weave:
/// without it neighbouring blocks share ribs and the pattern reads as a plaid
/// rather than as straps passing over and under.
[[stitchable]] half4 surfaceBasketweave(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 weave,
    float4 crease
) {
    using namespace SurfaceForge;

    float2 p    = surfaceCoordinates(position, viewSize, halfHeight);
    float2 q    = p * weave.x;
    float2 cell = floor(q);
    float2 f    = q - cell;

    // Checkerboard parity picks which way this block's ribs run.
    float parity   = cell.x + cell.y;
    float vertical = (parity - 2.0 * floor(parity * 0.5)) < 0.5 ? 0.0 : 1.0;
    float2 dir     = float2(vertical, 1.0 - vertical);

    // The ribs, phase running across them. Same groove anatomy as the
    // pinstripe: a signed wall and an even hollow.
    float acrossRib = mix(f.y, f.x, vertical);
    float phase     = acrossRib * weave.w;
    float wall;
    float hollow;
    groove(phase, wall, hollow);
    float2 slope    = dir * (weave.y * wall);

    // The crease loop, hard by design: a tight band around the block's border.
    float edge  = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    float loop  = 1.0 - smoothstep(0.5 * crease.x, crease.x, edge);

    float shade = 1.0 - weave.z * hollow
                      - crease.y * loop
                      - wall * dot(dir, crease.zw);

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
}

// The topographic field: three plane waves at mutually irrational angles, the
// cockle's recipe an octave up. Mirrored in SurfaceFinish.TopographicField so
// the solver can bound the gradient; a change here changes there.
constant float3 kTopoFrequencyU = float3( 5.20, -2.90,  7.10);
constant float3 kTopoFrequencyV = float3( 2.20,  6.90, -4.50);
constant float3 kTopoPhase      = float3( 0.00,  2.39,  4.11);
constant float3 kTopoWeight     = float3( 0.50,  0.30,  0.20);   // sums to 1

/// Topographic: contour lines inked over low rolling hills.
///
/// `topo` is (frequency scale, slope amplitude, contour density, ink) and
/// `line` is (1/points per unit, line half-width in points), solved in
/// SurfaceFinish.topographicCoefficients. The gradient is analytic, so the
/// line width holds in points wherever the field is steep or shallow, and the
/// contours vanish at peaks the way real ones close on a summit.
[[stitchable]] half4 surfaceTopographic(
    float2 position,
    half4  color,
    float2 viewSize,
    float2 eye,
    float  halfHeight,
    float3 keyDirection,
    float3 diffuseAxis,
    float  gleamAmount,
    float3 metalTint,
    float  windowExponent,
    float4 topo,
    float4 line
) {
    using namespace SurfaceForge;

    float2 p = surfaceCoordinates(position, viewSize, halfHeight);

    float3 arg    = (kTopoFrequencyU * p.x + kTopoFrequencyV * p.y) * topo.x
                  + kTopoPhase;
    float3 sinArg = sin(arg);
    float3 cosArg = cos(arg);

    float  height = dot(kTopoWeight, sinArg);
    float2 grad   = topo.x
                  * float2(dot(kTopoWeight * kTopoFrequencyU, cosArg),
                           dot(kTopoWeight * kTopoFrequencyV, cosArg));
    float2 slope  = grad * topo.y;

    // Distance to the nearest contour, measured in the field's own value, and
    // a line width converted into that value through the local gradient.
    float levels    = height * topo.z;
    float t         = levels - floor(levels);
    float toContour = min(t, 1.0 - t);
    float halfWidth = max(line.y * length(grad) * topo.z * line.x, 1.0e-6);
    float contour   = 1.0 - smoothstep(0.5 * halfWidth, halfWidth, toContour);

    float shade = 1.0 - topo.w * contour;

    return metalBody<false>(p, color, eye, keyDirection, diffuseAxis,
                            gleamAmount, metalTint, windowExponent, float3(0.0), slope, shade);
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
