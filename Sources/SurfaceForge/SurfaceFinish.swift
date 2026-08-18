import SwiftUI
import simd

/// How a material's surface is worked.
///
/// A struct with static members rather than an enum, for the reason
/// ``SurfaceMaterial`` is one: a later version can add a finish without breaking an
/// exhaustive `switch` in code that already ships.
///
/// A finish is a thing, not an amount. There is no "half brushed", the same way
/// there is no half-polished, so this carries no strength. What varies is which
/// finish and, where it means something, which way it runs.
public struct SurfaceFinish: Sendable, Hashable {
    /// Which pattern, and so which shader arm draws it.
    enum Kind: Sendable, Hashable {
        case polished
        case brushed
        case pinstripe
        case carbonTwill
        case topographic
        case basketweave
        case clousDeParis
        case knurling
        case sandblasted
        case sunburst
        case molten
        case hammered
    }

    let kind: Kind

    /// How far the finish stretches the highlight, and which way its lines run.
    ///
    /// Both internal. `stretch` is 0 or 1 and nothing else: the polished guarantee is
    /// that a polished surface renders the pixels it rendered before finishes
    /// existed, and that rests on this being an exact zero. For brushed the
    /// grain axis is the uniform the shader receives; for sunburst it is
    /// solved per fragment and this only says the stretch is on.
    let stretch: Float
    let grainAngle: Float

    /// What the finish is called when something has to say.
    public let name: String

    init(kind: Kind, stretch: Float, grainAngle: Float, name: String) {
        self.kind = kind
        // Clamped and de-NaNed here, once. The shader's `mix(1, stretch, x)`
        // is exact only for finite inputs, and everything downstream trusts
        // this range.
        self.stretch = stretch.isFinite ? min(max(stretch, 0), 1) : 0
        self.grainAngle = grainAngle
        self.name = name
    }

    /// Whether the finish has a direction an angle can aim.
    public var hasDirection: Bool {
        kind == .brushed || kind == .pinstripe
    }

    /// The same finish aimed a chosen way, unchanged when it has no direction.
    ///
    /// This is what a finish picker with an angle control wants, so the list
    /// of directed finishes lives here rather than in every app's switch.
    public func aimed(at angle: Angle) -> SurfaceFinish {
        switch kind {
        case .brushed: .brushed(angle: angle)
        case .pinstripe: .pinstripe(angle: angle)
        default: self
        }
    }

    // MARK: - The finishes

    /// Worked smooth. The highlight stays round and the surface carries no lines.
    public static let polished = SurfaceFinish(
        kind: .polished,
        stretch: 0,
        grainAngle: 0,
        name: "Polished"
    )

    /// Dragged with an abrasive, which cuts fine parallel lines.
    ///
    /// The lines run left to right. A groove scatters light across itself and not
    /// along itself, so the highlight stretches across the lines rather than along
    /// them, and the lines themselves stay visible on a still surface.
    public static let brushed = brushed()

    /// Brushed in a chosen direction.
    ///
    /// `angle` is the direction the brush ran, from the surface's long axis:
    /// `.zero` brushes left to right, `.degrees(90)` top to bottom.
    ///
    /// A diagonal grain reads a little weaker than an axis-aligned one, because the
    /// surface's own bow already biases the highlight toward the vertical.
    public static func brushed(angle: Angle = .zero) -> SurfaceFinish {
        SurfaceFinish(
            kind: .brushed,
            stretch: 1,
            grainAngle: sanitized(angle),
            name: "Brushed"
        )
    }

    /// Engraved with straight parallel grooves, coarser and deeper than brushing.
    ///
    /// The stripes read on a still surface and catch a wall of light as it moves.
    /// The highlight stays round: a groove this coarse decorates the metal rather
    /// than reworking how it scatters.
    public static let pinstripe = pinstripe()

    /// Pinstriped in a chosen direction. `angle` is the way the stripes run.
    public static func pinstripe(angle: Angle = .zero) -> SurfaceFinish {
        SurfaceFinish(
            kind: .pinstripe,
            stretch: 0,
            grainAngle: sanitized(angle),
            name: "Pinstripe"
        )
    }

    /// Woven: a twill of crowned tows pressed into the metal, half running each
    /// way. Tows lying along the light pick up a sheen the crossing tows do
    /// not, which is what makes it read as weave rather than checkerboard.
    public static let carbonTwill = SurfaceFinish(
        kind: .carbonTwill,
        stretch: 0,
        grainAngle: 0,
        name: "Carbon twill"
    )

    /// Engraved with contour lines over low rolling hills, the way a map draws
    /// terrain. The lines close on the field's own summits.
    public static let topographic = SurfaceFinish(
        kind: .topographic,
        stretch: 0,
        grainAngle: 0,
        name: "Topographic"
    )

    /// Woven from blocks of parallel ribs, alternating direction block by
    /// block, each ringed by a hard crease where the strap dives under.
    public static let basketweave = SurfaceFinish(
        kind: .basketweave,
        stretch: 0,
        grainAngle: 0,
        name: "Basketweave"
    )

    /// The hobnail grid: rounded studs whose faces catch the light one at a
    /// time as the surface tilts, the guilloché most watch dials wear.
    public static let clousDeParis = SurfaceFinish(
        kind: .clousDeParis,
        stretch: 0,
        grainAngle: 0,
        name: "Clous de Paris"
    )

    /// Cut with crossed shallow grooves into a field of fine diamonds, the way
    /// a tool grip is worked.
    public static let knurling = SurfaceFinish(
        kind: .knurling,
        stretch: 0,
        grainAngle: 0,
        name: "Knurling"
    )

    /// Blasted with fine beads to an even matte mottle, the finish most
    /// hardware wears.
    public static let sandblasted = SurfaceFinish(
        kind: .sandblasted,
        stretch: 0,
        grainAngle: 0,
        name: "Sandblasted"
    )

    /// Brushed on a turning workpiece: rings for lines, and the highlight
    /// streaks along the radius the way spun metal streaks.
    public static let sunburst = SurfaceFinish(
        kind: .sunburst,
        stretch: 1,
        grainAngle: 0,
        name: "Sunburst"
    )

    /// Melted: the surface itself is liquid, and tongues of light swirl
    /// across it as the device tilts.
    public static let molten = SurfaceFinish(
        kind: .molten,
        stretch: 0,
        grainAngle: 0,
        name: "Molten"
    )

    /// Planished: a field of shallow round dents, each catching the light
    /// on its own as the surface tilts.
    public static let hammered = SurfaceFinish(
        kind: .hammered,
        stretch: 0,
        grainAngle: 0,
        name: "Hammered"
    )

    /// Every built-in finish, for pickers and galleries.
    public static let all: [SurfaceFinish] = [
        .polished, .brushed, .pinstripe, .carbonTwill, .topographic,
        .basketweave, .clousDeParis, .knurling, .sandblasted, .sunburst,
        .molten, .hammered,
    ]

    // MARK: - Sanitizing

    /// Sanitized here, not in the shader. The polished guarantee holds for a
    /// finite grain angle and only for a finite one, because the shader's
    /// `mix(1, stretch, 0)` returns an exact 1.0 for finite inputs and a NaN
    /// otherwise.
    ///
    /// `remainder` rather than a clamp, because a grain is an axis and any whole
    /// turn of it is the same grain.
    private static func sanitized(_ angle: Angle) -> Float {
        angle.radians.isFinite
            ? Float(angle.radians.remainder(dividingBy: 2 * .pi))
            : 0
    }
}

// MARK: - Solving

/// Everything a finish arm reads, pre-multiplied on the CPU.
///
/// Two registers of four slots, because a uniform is opaque to the compiler: a
/// value solved here costs nothing per fragment, the same value solved in the
/// shader costs every pixel every frame. The slot meanings live beside each
/// arm's solver.
struct SurfaceFinishCoefficients {
    /// One float4 per shader register, in the order the arm declares them.
    /// Solvers that touch only `a` produce one register, so the argument list
    /// always matches the arm's arity.
    private(set) var registers: [SIMD4<Float>] = []

    var a: SIMD4<Float> {
        get { registers.count > 0 ? registers[0] : .zero }
        set {
            while registers.count < 1 { registers.append(.zero) }
            registers[0] = newValue
        }
    }

    var b: SIMD4<Float> {
        get { registers.count > 1 ? registers[1] : .zero }
        set {
            while registers.count < 2 { registers.append(.zero) }
            registers[1] = newValue
        }
    }
}

extension SurfaceFinish {
    /// Surface u runs -1...+1 over the width, so points per unit is width/2,
    /// and v shares the same scale by construction. This mirrors the shader's
    /// surfaceCoordinates and must move with it.
    static func pointsPerUnit(for size: CGSize) -> Float {
        Float(max(size.width, 1)) / 2
    }
}

extension SurfaceFinish {
    /// One stripe every 16 points, twice the brush pitch, because a pinstripe
    /// is sparse thin lines on open metal where brushing is lines wall to
    /// wall. Comfortably above the 8-device-pixel feature floor.
    static let pinstripePitch: Float = 16

    /// Steeper than brushing's 0.012, because a stripe is the drawn feature
    /// here rather than a texture under one, and still under the 0.030 ceiling
    /// the travelling gleam can resolve.
    static let pinstripeSlope: Float = 0.026

    /// Ink low and wall high: the line is mostly the light catching its cut
    /// edge, not pigment. Flat darkening is what read as dirt.
    static let pinstripeInk: Float = 0.06
    static let pinstripeWall: Float = 0.14

    /// One tow every 8 points, the same floor the pinstripe pitch sits on.
    static let twillCellPoints: Float = 8

    /// The crown's peak slope. Under the 0.030 ceiling, and softer than the
    /// pinstripe's cut because a tow is cloth pressed in, not a groove.
    static let twillCrownSlope: Float = 0.028

    /// The seam's darkening where a tow dives under its neighbour, and the
    /// sheen a tow gains for lying along the light.
    static let twillSeamInk: Float = 0.05
    static let twillSheen: Float = 0.09

    /// Coefficients for the carbon twill arm at one drawn size.
    ///
    /// Slots: `a` = (cells per unit, crown slope, ink, sheen), `b` = the
    /// diffuse light's unit azimuth. Solved here because a uniform normalized
    /// per fragment is the exact waste the virtualEye comment warns about.
    func twillCoefficients(
        size: CGSize,
        lightAzimuth: SIMD2<Float>
    ) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            pointsPerUnit / Self.twillCellPoints,
            Self.twillCrownSlope,
            Self.twillSeamInk,
            Self.twillSheen
        )
        // Raw, not normalized, matching the wall terms in brushed and
        // pinstripe: as the light lifts overhead the azimuth shrinks and the
        // directional sheen fades with it, instead of pointing at a light
        // that is no longer to any side.
        coefficients.b = SIMD4(lightAzimuth.x, lightAzimuth.y, 0, 0)
        return coefficients
    }

    /// The topographic height field, mirrored from the shader's constants so
    /// the solver can bound the gradient. A change there changes here, and the
    /// gradient test is what says so.
    enum TopographicField {
        static let frequencyU: SIMD3<Float> = [5.20, -2.90, 7.10]
        static let frequencyV: SIMD3<Float> = [2.20, 6.90, -4.50]
        static let phase: SIMD3<Float> = [0.00, 2.39, 4.11]
        static let weight: SIMD3<Float> = [0.50, 0.30, 0.20]

        /// The height at one point, for the gradient test.
        static func height(_ p: SIMD2<Float>, scale: Float) -> Float {
            let arg = (frequencyU * p.x + frequencyV * p.y) * scale + phase
            return weight.x * sin(arg.x) + weight.y * sin(arg.y) + weight.z * sin(arg.z)
        }

        /// An upper bound on the gradient's length at unit scale.
        static var peakGradient: Float {
            let lengths = SIMD3<Float>(
                simd_length(SIMD2(frequencyU.x, frequencyV.x)),
                simd_length(SIMD2(frequencyU.y, frequencyV.y)),
                simd_length(SIMD2(frequencyU.z, frequencyV.z))
            )
            return simd_dot(weight, lengths)
        }
    }

    /// The reference card is 353 points wide, and its width spans 2 surface
    /// units, so this is the points-per-unit the field was tuned at. Scaling
    /// against it keeps the hills a physical size on any card.
    static let referencePointsPerUnit: Float = 353.0 / 2

    /// The hills' peak slope, and the bar the solver divides by the field's
    /// own peak gradient to hold it.
    static let topographicSlope: Float = 0.022

    /// Contours per unit of height. Six lines over the field's full swing.
    static let topographicDensity: Float = 3

    /// The line's half-width in points, and its depth of ink.
    static let topographicLineWidth: Float = 1.2
    static let topographicInk: Float = 0.12

    /// Coefficients for the topographic arm at one drawn size.
    ///
    /// Slots: `a` = (frequency scale, slope amplitude, contour density, ink),
    /// `b` = (1/points per unit, line half-width in points, 0, 0).
    func topographicCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)
        let scale = pointsPerUnit / Self.referencePointsPerUnit

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            scale,
            Self.topographicSlope / (TopographicField.peakGradient * max(scale, 1.0e-3)),
            Self.topographicDensity,
            Self.topographicInk
        )
        coefficients.b = SIMD4(1 / pointsPerUnit, Self.topographicLineWidth, 0, 0)
        return coefficients
    }

    /// An 18-point block of three 6-point ribs. The rib is the finest feature
    /// at 12 device pixels on a 2x screen, clear of the 8-pixel floor.
    static let basketweaveBlockPoints: Float = 18
    static let basketweaveRibsPerBlock: Float = 3

    /// Rib amplitudes, pinstripe's family. The crease is darker than any rib
    /// hollow because it stands for a strap in full shadow, and its width is a
    /// fraction of the block so the loop scales with the weave.
    static let basketweaveRibSlope: Float = 0.026
    static let basketweaveRibInk: Float = 0.05
    static let basketweaveWall: Float = 0.12
    static let basketweaveCreaseWidth: Float = 1.5 / 18
    static let basketweaveCreaseInk: Float = 0.10

    /// Coefficients for the basketweave arm at one drawn size.
    ///
    /// Slots: `a` = (blocks per unit, rib slope, rib ink, rib phase per
    /// block), `b` = (crease half-width in block fraction, crease ink, light
    /// azimuth scaled by the wall amount).
    func basketweaveCoefficients(
        size: CGSize,
        lightAzimuth: SIMD2<Float>
    ) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            pointsPerUnit / Self.basketweaveBlockPoints,
            Self.basketweaveRibSlope,
            Self.basketweaveRibInk,
            Self.basketweaveRibsPerBlock * 2 * .pi
        )
        // Raw azimuth, same reasoning as the twill solver.
        coefficients.b = SIMD4(
            Self.basketweaveCreaseWidth,
            Self.basketweaveCreaseInk,
            lightAzimuth.x * Self.basketweaveWall,
            lightAzimuth.y * Self.basketweaveWall
        )
        return coefficients
    }

    /// A stud every 10 points, and the slope each face peaks at. 0.024 leaves
    /// margin under the 0.030 ceiling because all four faces of a stud take
    /// it, twice per grid cell.
    static let clousPitchPoints: Float = 10
    static let clousSlope: Float = 0.028
    static let clousValleyInk: Float = 0.06

    /// Coefficients for the clous de Paris arm at one drawn size.
    ///
    /// Slots: `a` = (grid frequency per unit, peak slope, valley ink, 0).
    func clousCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            2 * .pi * pointsPerUnit / Self.clousPitchPoints,
            Self.clousSlope,
            Self.clousValleyInk,
            0
        )
        return coefficients
    }

    /// A groove family every 6 points, at 30 degrees each side of the long
    /// axis. Each family takes 0.014 of slope so the crossed pair stays under
    /// the 0.030 ceiling; full depth was tried and dashed the gleam.
    static let knurlPitchPoints: Float = 6
    static let knurlAngle: Float = .pi / 6
    static let knurlSlope: Float = 0.014
    static let knurlInk: Float = 0.04

    /// Coefficients for the knurling arm at one drawn size.
    ///
    /// Slots: `a` = the two families' phase vectors, `b` = (slope, ink,
    /// 1/|phase|, 0). The reciprocal is what lets the shader reuse the phase
    /// vectors as unit slope directions without a per-fragment normalize.
    func knurlCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)
        let phasePerUnit = 2 * Float.pi * pointsPerUnit / Self.knurlPitchPoints

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            -sin(Self.knurlAngle) * phasePerUnit,
            cos(Self.knurlAngle) * phasePerUnit,
            -sin(-Self.knurlAngle) * phasePerUnit,
            cos(-Self.knurlAngle) * phasePerUnit
        )
        coefficients.b = SIMD4(Self.knurlSlope, Self.knurlInk, 1 / phasePerUnit, 0)
        return coefficients
    }

    /// How far blasting scatters the highlight: the window keeps a third of
    /// the material's tightness, landing gold between copper and gunmetal.
    /// The mottle alone left sandblasted indistinguishable from polished,
    /// because a blasted surface's real signature is its soft wide gleam.
    static let blastScatter: Float = 0.35

    /// The material's highlight tightness as this finish wears it.
    func effectiveTightness(of material: SurfaceMaterial) -> Float {
        switch kind {
        case .sandblasted: material.highlightTightness * Self.blastScatter
        case .molten: material.highlightTightness * Self.moltenFocus
        default: material.highlightTightness
        }
    }

    /// The mottle's depth in shade. 0.05 of a 0.87-luminance substrate is
    /// about 11 of 255 levels, which is why this cannot fall under the 8-bit
    /// quantum the way the normal-borne version did.
    static let blastDepth: Float = 0.03

    /// Coefficients for the sandblasted arm at one drawn size.
    ///
    /// Slots: `a` = (frequency scale, mottle depth, 0, 0). The scale holds the
    /// blotches at the pitch they were tuned at on the reference card.
    func blastCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            pointsPerUnit / Self.referencePointsPerUnit,
            Self.blastDepth,
            0,
            0
        )
        return coefficients
    }

    /// Coefficients for the sunburst arm at one drawn size.
    ///
    /// Slots: `a` = (ring phase per unit, stretch amount, 0, 0). The ring
    /// pitch mirrors the brush lines' own spacing, because a sunburst is the
    /// same cut on a turning workpiece.
    func sunburstCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(pointsPerUnit * .pi / 2, stretch, 0, 0)
        return coefficients
    }

    /// The melt's flow field, mirrored from the shader so the solver can
    /// hold each part's slope at its bar. The weld test keeps the copies
    /// equal.
    enum MoltenFlow {
        /// The broad swells, 150 to 250 points.
        static let swellWaves: [SIMD2<Float>] = [
            [4.1, 2.7], [-5.2, 3.4], [1.9, -4.6],
        ]
        static let swellPhase: SIMD3<Float> = [0.9, 2.3, 4.8]
        static let swellWeight: SIMD3<Float> = [0.42, 0.33, 0.25]

        /// The ripples riding them, 70 to 100 points.
        static let rippleWaves: [SIMD2<Float>] = [
            [9.7, 6.3], [-11.4, 7.9], [5.1, -10.8],
        ]
        static let ripplePhase: SIMD3<Float> = [2.2, 4.7, 0.6]
        static let rippleWeight: SIMD3<Float> = [0.4, 0.33, 0.27]

        /// The warp both wave sets are read through.
        static let warpWaveA: SIMD2<Float> = [2.9, -1.8]
        static let warpWaveB: SIMD2<Float> = [2.2, 3.1]
        static let warpPhase: SIMD2<Float> = [1.4, 4.2]
        static let warpAmount: Float = 0.20

        /// Peak gradient of each part at unit scale, measured over the
        /// padded card. The solver divides each bar by these; a test
        /// re-measures them.
        static let swellPeak: Float = 6.286
        static let ripplePeak: Float = 15.353

        /// Both slope parts at one point, mirroring the shader's arm.
        static func parts(
            _ p: SIMD2<Float>
        ) -> (swell: SIMD2<Float>, ripple: SIMD2<Float>) {
            let argA = simd_dot(warpWaveA, p) + warpPhase.x
            let argB = simd_dot(warpWaveB, p) + warpPhase.y
            let warped = p + warpAmount * SIMD2<Float>(sin(argA), sin(argB))
            let cA = warpAmount * cos(argA)
            let cB = warpAmount * cos(argB)

            func gradient(
                _ waves: [SIMD2<Float>], _ phase: SIMD3<Float>, _ weight: SIMD3<Float>
            ) -> SIMD2<Float> {
                var g = SIMD2<Float>.zero
                for i in 0..<3 {
                    let w = weight[i] * cos(simd_dot(waves[i], warped) + phase[i])
                    g += waves[i] * w
                }
                // Chain rule through the warp.
                return SIMD2(
                    g.x * (1 + cA * warpWaveA.x) + g.y * (cB * warpWaveB.x),
                    g.x * (cA * warpWaveA.y) + g.y * (1 + cB * warpWaveB.y)
                )
            }

            return (
                gradient(swellWaves, swellPhase, swellWeight),
                gradient(rippleWaves, ripplePhase, rippleWeight)
            )
        }
    }

    /// The melt's peak slope. Well past the 0.030 ceiling on purpose: the
    /// ceiling protects a flat card's gleam from texture, and a melt is not
    /// a flat card. 0.50 is a 27-degree wave wall, which folds the light
    /// into tongues without tearing it into glitter.
    static let moltenSlope: Float = 0.50

    /// The ripples' share of the slope. Under a third reads as wavy polish;
    /// near half the tongues fray.
    static let moltenRippleShare: Float = 0.42

    /// How much melting tightens the highlight. A melt has no tooling
    /// marks, so its window is narrower than the solid metal's; 1.5 puts
    /// gold at the knee near 100 where the band stops narrowing.
    static let moltenFocus: Float = 1.5

    /// Coefficients for the molten arm at one drawn size.
    ///
    /// Slots: `a` = (frequency scale, swell amplitude, ripple amplitude, 0).
    /// Each amplitude is divided by its part's peak and the scale, so the
    /// slopes hold their bars on any card size.
    func moltenCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)
        let scale = pointsPerUnit / Self.referencePointsPerUnit
        let safeScale = max(scale, 1.0e-3)

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            scale,
            Self.moltenSlope * (1 - Self.moltenRippleShare)
                / (MoltenFlow.swellPeak * safeScale),
            Self.moltenSlope * Self.moltenRippleShare
                / (MoltenFlow.ripplePeak * safeScale),
            0
        )
        return coefficients
    }

    /// The hammer field, mirrored from the shader so the solver can hold the
    /// dents' slope at its bar. The weld test keeps the copies equal.
    ///
    /// Round dents on a jittered hex lattice: each a bowl `-(1 - r²/R²)²`
    /// inside its radius, so the slope is continuous and zero at the rim.
    /// Radius and position jitter per cell, so no lattice shows.
    enum HammerField {
        /// Dent spacing on the reference card, surface units. 0.26 is 46pt.
        static let pitch: Float = 0.26
        /// Nominal dent radius, surface units. Neighbours overlap a little.
        static let radius: Float = 0.165
        /// Position jitter, as a fraction of pitch.
        static let jitter: Float = 0.34
        /// Radius jitter: 0.8 to 1.2 of nominal.
        static let radiusSpread: Float = 0.40

        /// Peak gradient at unit scale, measured over the padded card.
        static let peak: Float = 11.664

        static func hash(_ i: Float, _ j: Float, _ a: Float, _ b: Float) -> Float {
            let x: Float = sin(i * a + j * b) * 43758.5453
            return x - floor(x)
        }

        /// The dents' slope at one point, mirroring the shader's arm.
        static func slope(_ p: SIMD2<Float>) -> SIMD2<Float> {
            let a1 = SIMD2<Float>(pitch, 0)
            let a2 = SIMD2<Float>(pitch * 0.5, pitch * 0.8660254)
            // Inverse of the lattice basis, for the cell index.
            let det: Float = a1.x * a2.y - a2.x * a1.y
            let lu: Float = (a2.y * p.x - a2.x * p.y) / det
            let lv: Float = (-a1.y * p.x + a1.x * p.y) / det
            let i0: Float = floor(lu)
            let j0: Float = floor(lv)

            var g = SIMD2<Float>.zero
            for di in -1...2 {
                for dj in -1...2 {
                    let i: Float = i0 + Float(di)
                    let j: Float = j0 + Float(dj)
                    let jx: Float = (hash(i, j, 127.1, 311.7) - 0.5) * jitter * pitch
                    let jy: Float = (hash(i, j, 269.5, 183.3) - 0.5) * jitter * pitch
                    let centre = a1 * i + a2 * j + SIMD2<Float>(jx, jy)
                    let spread: Float = 1 - radiusSpread / 2 + radiusSpread * hash(i, j, 419.2, 371.9)
                    let r: Float = radius * spread
                    let d = p - centre
                    let q: Float = simd_dot(d, d) / (r * r)
                    if q < 1 {
                        g += d * (4 * (1 - q) / (r * r))
                    }
                }
            }
            return g
        }
    }

    /// The dents' peak slope, past the 0.030 ceiling on purpose. A dent is
    /// coarse enough to shade itself: the wall away from the light darkens
    /// through the diffuse term, and each dent flashes on its own. 0.18 is a
    /// 10-degree bowl wall.
    static let hammerSlope: Float = 0.18

    /// Coefficients for the hammered arm at one drawn size.
    ///
    /// Slots: `a` = (frequency scale, slope amplitude, 0, 0). The amplitude
    /// is divided by the field's peak and the scale, so the dents keep their
    /// size and depth on any card.
    func hammerCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)
        let scale = pointsPerUnit / Self.referencePointsPerUnit

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            scale,
            Self.hammerSlope / (HammerField.peak * max(scale, 1.0e-3)),
            0,
            0
        )
        return coefficients
    }

    /// Coefficients for the pinstripe arm at one drawn size.
    ///
    /// Slots: `a` = (phase.x, phase.y, slope, ink), `b` = (across.x, across.y,
    /// wall, 0). Phase advances one turn per pitch, measured in points, so the
    /// stripes are the same width on any size of surface.
    func pinstripeCoefficients(size: CGSize) -> SurfaceFinishCoefficients {
        let pointsPerUnit = Self.pointsPerUnit(for: size)
        let phasePerPoint = 2 * Float.pi / Self.pinstripePitch
        let across = SIMD2<Float>(-sin(grainAngle), cos(grainAngle))

        var coefficients = SurfaceFinishCoefficients()
        coefficients.a = SIMD4(
            across.x * phasePerPoint * pointsPerUnit,
            across.y * phasePerPoint * pointsPerUnit,
            Self.pinstripeSlope,
            Self.pinstripeInk
        )
        coefficients.b = SIMD4(across.x, across.y, Self.pinstripeWall, 0)
        return coefficients
    }
}
