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

    /// What the material is called when something has to say.
    public let name: String

    init(tint: SIMD3<Float>, name: String) {
        self.tint = tint
        self.name = name
    }

    // MARK: - The metals

    // The tint says *which* metal, not how metal behaves, so it is the one thing
    // that varies without re-solving the shader's calibrated set. Each is three
    // floats and nothing else.

    public static let gold = SurfaceMaterial(
        tint: SIMD3(1.00, 0.72, 0.22),
        name: "Gold"
    )

    /// Keeps a faint cool cast rather than being pure white, because a perfectly
    /// neutral metal reads as grey plastic.
    public static let silver = SurfaceMaterial(
        tint: SIMD3(0.95, 0.97, 1.00),
        name: "Silver"
    )

    public static let roseGold = SurfaceMaterial(
        tint: SIMD3(1.00, 0.72, 0.60),
        name: "Rose gold"
    )

    public static let copper = SurfaceMaterial(
        tint: SIMD3(0.98, 0.55, 0.35),
        name: "Copper"
    )

    public static let brass = SurfaceMaterial(
        tint: SIMD3(0.94, 0.79, 0.42),
        name: "Brass"
    )

    /// The dark near-neutral. Silver is the bright one; this is the same absence
    /// of hue at a much lower value, which is what separates gunmetal from grey
    /// silver.
    public static let gunmetal = SurfaceMaterial(
        tint: SIMD3(0.62, 0.65, 0.70),
        name: "Gunmetal"
    )

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
