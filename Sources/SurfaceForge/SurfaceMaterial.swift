import SwiftUI
import simd

/// What a surface is made of.
///
/// A struct with static members rather than an enum, so later versions can add a
/// material without breaking an exhaustive `switch` in code that already ships.
///
/// **Every built-in material is metallic.** Metallic materials read content as
/// luminance: lightness is preserved and colour is discarded, so a blue element
/// appears as the material's own colour at blue's brightness. That belongs to
/// these materials rather than to ``Surface``, and other kinds may treat content
/// differently.
public struct SurfaceMaterial: Sendable, Hashable {
    /// The metal's reflectance hue, pushed past where it should sit.
    ///
    /// **Stored richer than the metal you want to see**, because the shader
    /// multiplies this by the content's own luminance, about 0.87 after the
    /// diffuse term, which both lifts and desaturates it. Gold's stored
    /// `(1.00, 0.72, 0.22)` renders near (214, 187, 114). Reading these as
    /// literal colours is the easiest way to be confused by this type.
    let tint: SIMD3<Float>

    /// How tight the travelling band is. Higher is narrower and harder edged.
    ///
    /// A polished metal returns a small hard band; a rough one scatters the same
    /// light into a wide soft one. Measured across the surface, 15 gives a
    /// falloff of 16 luma levels and 60 gives 26. Past about 100 the band stops
    /// narrowing, so the useful range runs downward from there.
    let highlightTightness: Float

    /// How far the highlight stretches across the grain.
    ///
    /// `0` is polished: the highlight stays round. `1` makes it three times longer
    /// than it is wide. A brushed metal is a field of parallel grooves, and a
    /// groove scatters light across itself but not along itself, so the highlight
    /// spreads one way and stays tight the other. Measured across the surface, `1`
    /// takes gold's band from 8.1 degrees each way to 13.8 by 4.7.
    ///
    /// Zero is not an approximation of polished. It renders the pixel a polished
    /// material rendered before this existed.
    let highlightStretch: Float

    /// Which way the brush ran, in radians from the surface's long axis.
    ///
    /// The highlight stretches across this rather than along it, because that is
    /// what a groove does to light. Only read when ``highlightStretch`` is above
    /// zero.
    let grainAngle: Float

    /// What the material is called when something has to say.
    public let name: String

    init(
        tint: SIMD3<Float>,
        highlightTightness: Float = 60,
        highlightStretch: Float = 0,
        grainAngle: Float = 0,
        name: String
    ) {
        self.tint = tint
        self.highlightTightness = highlightTightness
        self.highlightStretch = highlightStretch
        self.grainAngle = grainAngle
        self.name = name
    }

    // MARK: - The metals

    // Each carries a hue and a tightness. The tint says which metal it is; the
    // tightness says how polished it is, which is what separates a hard bright
    // band from a wide soft one.

    public static let gold = SurfaceMaterial(
        tint: SIMD3(1.00, 0.72, 0.22),
        highlightTightness: 70,
        name: "Gold"
    )

    /// The most reflective of the six, and it gets the hardest highlight.
    ///
    /// Its tint keeps a faint cool cast rather than being pure white, because a
    /// perfectly neutral metal reads as grey plastic.
    public static let silver = SurfaceMaterial(
        tint: SIMD3(0.95, 0.97, 1.00),
        highlightTightness: 110,
        name: "Silver"
    )

    /// Gold alloyed toward copper, and it takes light the same way gold does.
    public static let roseGold = SurfaceMaterial(
        tint: SIMD3(1.00, 0.72, 0.60),
        highlightTightness: 65,
        name: "Rose gold"
    )

    /// Softer than the golds. A broader, dimmer highlight is most of what
    /// separates copper from rose gold, since their hues are close.
    public static let copper = SurfaceMaterial(
        tint: SIMD3(0.98, 0.55, 0.35),
        highlightTightness: 35,
        name: "Copper"
    )

    public static let brass = SurfaceMaterial(
        tint: SIMD3(0.94, 0.79, 0.42),
        highlightTightness: 50,
        name: "Brass"
    )

    /// The dark near-neutral, and the only matte one. Silver is the bright hard
    /// metal; this is the same absence of hue at a much lower value with a
    /// highlight to match.
    public static let gunmetal = SurfaceMaterial(
        tint: SIMD3(0.62, 0.65, 0.70),
        highlightTightness: 18,
        name: "Gunmetal"
    )

    // MARK: - Brushing

    /// The same metal, brushed.
    ///
    /// The highlight stretches into a band across the grain instead of staying
    /// round, which is most of what separates brushed metal from polished.
    ///
    /// `angle` is the direction the brush ran, from the surface's long axis:
    /// `.zero` brushes left to right, `.degrees(90)` top to bottom. `amount` runs
    /// from `0` for polished to `1` for fully brushed.
    ///
    /// A diagonal grain reads a little weaker than an axis-aligned one, because
    /// the surface's own bow already biases the highlight toward the vertical.
    public func brushed(_ amount: Double = 1, angle: Angle = .zero) -> SurfaceMaterial {
        // Sanitized here rather than in the shader. The polished guarantee is that
        // `mix(1, stretch, 0)` returns an exact 1.0, which holds for a finite
        // stretch and only for a finite one, so one NaN arriving through either
        // parameter would take it away.
        //
        // `remainder` rather than a clamp, because a grain is an axis and any
        // whole turn of it is the same grain.
        let clamped = amount.isFinite ? min(max(amount, 0), 1) : 0
        let radians = angle.radians.isFinite
            ? angle.radians.remainder(dividingBy: 2 * .pi)
            : 0

        return SurfaceMaterial(
            tint: tint,
            highlightTightness: highlightTightness,
            highlightStretch: Float(clamped),
            grainAngle: Float(radians),
            name: name
        )
    }

    /// A metal of your own.
    ///
    /// Pick a colour richer and more saturated than the metal you want, for the
    /// reason ``tint`` describes: what you pass is multiplied by content
    /// luminance before it reaches the screen.
    public static func custom(tint: Color, name: String = "Custom") -> SurfaceMaterial {
        let resolved = resolve(tint)
        return SurfaceMaterial(tint: resolved, name: name)
    }

    /// Every built-in material, for pickers and galleries.
    public static let all: [SurfaceMaterial] = [
        .gold, .silver, .roseGold, .copper, .brass, .gunmetal,
    ]

    // MARK: - A fill, where a material cannot run

    /// A flat approximation, for anything that needs a colour rather than a
    /// material: an accessibility swatch, a legend, a test.
    ///
    /// **Not what a surface looks like**, and deliberately not used to draw one.
    /// The whole argument of this package is that a metal is a lighting model
    /// rather than a fill. This is the fill you would settle for if you could not
    /// run the shader.
    public var approximateColor: Color {
        let lit = tint * 0.87
        return Color(
            red: Double(min(lit.x, 1)),
            green: Double(min(lit.y, 1)),
            blue: Double(min(lit.z, 1))
        )
    }

    // MARK: - Helpers

    private static func resolve(_ color: Color) -> SIMD3<Float> {
        // `resolve` needs an environment, and a custom tint has no view to take
        // one from. UIColor's conversion is the honest path for a plain colour.
        let components = UIColor(color).cgColor
            .converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?
            .components

        guard let components, components.count >= 3 else {
            return SurfaceMaterial.gold.tint
        }

        return SIMD3(
            Float(components[0]),
            Float(components[1]),
            Float(components[2])
        )
    }
}
