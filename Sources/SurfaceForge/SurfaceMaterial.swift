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

    /// How the surface is worked. Polished unless ``finish(_:)`` said otherwise.
    ///
    /// Polished is not an approximation of no finish. It renders the pixel the
    /// material rendered before finishes existed.
    let surfaceFinish: SurfaceFinish

    /// What the material is called when something has to say.
    public let name: String

    /// How far the highlight stretches: `0` is polished and round, `1`
    /// stretches it along the grain axis to about 1.7 times its polished
    /// length. It only ever spreads, so the band keeps the material's own
    /// width against the grain.
    var highlightStretch: Float { surfaceFinish.stretch }

    /// Which way the brush ran, in radians from the surface's long axis.
    var grainAngle: Float { surfaceFinish.grainAngle }

    init(
        tint: SIMD3<Float>,
        highlightTightness: Float = 60,
        finish: SurfaceFinish = .polished,
        name: String
    ) {
        self.tint = tint
        self.highlightTightness = highlightTightness
        self.surfaceFinish = finish
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

    // MARK: - Finish

    /// The same metal, worked differently.
    ///
    /// Everything else about the material is unchanged: a brushed gold is the same
    /// gold. ``SurfaceFinish/polished`` renders exactly what the material rendered
    /// before finishes existed.
    public func finish(_ finish: SurfaceFinish) -> SurfaceMaterial {
        SurfaceMaterial(
            tint: tint,
            highlightTightness: highlightTightness,
            finish: finish,
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

        // Clamped, because a wide-gamut colour converts to sRGB components
        // outside 0...1 and the shader's per-channel headroom math assumes
        // they are inside it. An out-of-range channel would clip against the
        // substrate clamp stripe by stripe and shift hue under a finish.
        return SIMD3(
            Float(min(max(components[0], 0), 1)),
            Float(min(max(components[1], 0), 1)),
            Float(min(max(components[2], 0), 1))
        )
    }
}
