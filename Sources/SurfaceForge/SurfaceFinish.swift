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

    /// Every built-in finish, for pickers and galleries.
    public static let all: [SurfaceFinish] = [
        .polished, .brushed, .pinstripe, .carbonTwill, .topographic,
        .basketweave, .clousDeParis, .knurling, .sandblasted, .sunburst,
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
