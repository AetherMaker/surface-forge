import SwiftUI

/// What a surface is made of before any light reaches it, and the numbers that
/// shape its edge and its lean.
///
/// Every colour here is a grey, and that is a requirement rather than a palette
/// choice: a metallic material takes the luminance of what it is handed and
/// discards chroma, so a coloured value arrives as metal of the same lightness.
enum SurfaceStyle {
    /// The surface's own colour, and the single lever that sets how deep the
    /// metal reads.
    ///
    /// The shader multiplies the material's tint by this, so a bright surface
    /// yields pale champagne and a darker one a richer metal. At 0.96, gold
    /// renders (237, 210, 131), too light and too thin. At 0.88 it lands nearer
    /// (214, 187, 114), which reads as struck metal and leaves the gleam
    /// somewhere to travel.
    static let stock = Color(white: 0.88)

    /// What `.primary` resolves to inside a surface. Dark enough to stay legible
    /// once the metal has lifted the surface around it.
    static let ink = Color(white: 0.13)

    /// What `.secondary` resolves to.
    static let inkSecondary = Color(white: 0.30)

    /// What `.tertiary` resolves to. Light enough to recede, dark enough to
    /// survive the gleam crossing it.
    static let inkTertiary = Color(white: 0.44)

    /// How wide the rim is.
    ///
    /// A hairline, so the edge reads as where the surface stops rather than as a
    /// border someone drew around it.
    static let rimWidth: CGFloat = 0.8

    /// A sub-pixel feather on the silhouette.
    ///
    /// A hard mask does not survive the 3D transform applied after it. Under a
    /// hard clip the tilted edge holds flat, jumps a whole device pixel, holds
    /// flat again, with no partial-coverage pixel anywhere: the one-bit
    /// staircase. `drawingGroup()` does not rescue it, because the jagged edge is
    /// inside the layer rather than at its boundary.
    ///
    /// A feather gives the re-rasterisation an actual gradient to sample. At
    /// 0.4pt it is under a single device pixel at any scale factor, so it never
    /// reads as blur. If anything it reads as a real edge rather than a vector
    /// boundary.
    static let silhouetteFeather: CGFloat = 0.4

    /// Foreshortening for the surface's own lean.
    ///
    /// The lean is small, at most 9 degrees, and a shallower perspective leaves
    /// almost no depth cue at that range: the surface reads as sliding rather than
    /// turning. 0.68 is enough to see the near edge come forward, and still short
    /// of where glyph shear becomes visible at this angle.
    static let tiltPerspective: CGFloat = 0.68
}

/// Where the light sits along the surface's edge.
nonisolated enum SurfaceRim {
    /// The gradient's start, the lit edge, and its end, the dark one, in unit
    /// space.
    ///
    /// The y flip converts the shader's frame, where v is up, into SwiftUI's,
    /// where y is down. The same flip `surfaceCoordinates` applies. Without it the
    /// bright edge lands on the wrong side and the surface appears lit from below.
    static func ends(
        keyDirection: SIMD3<Float>
    ) -> (toward: UnitPoint, away: UnitPoint) {
        let planar = SIMD2<Float>(keyDirection.x, -keyDirection.y)
        let direction = SurfaceShading.normalized(planar, fallback: SIMD2<Float>(-1, 0))

        // Unit space, centre out. Half a diagonal each way, so the ramp spans the
        // surface whatever its proportion.
        return (
            toward: UnitPoint(
                x: 0.5 + Double(direction.x) * 0.5,
                y: 0.5 + Double(direction.y) * 0.5
            ),
            away: UnitPoint(
                x: 0.5 - Double(direction.x) * 0.5,
                y: 0.5 - Double(direction.y) * 0.5
            )
        )
    }

    /// The hairline itself.
    ///
    /// White rather than metal-coloured: this is the coat's specular on a cut
    /// edge, and the coat is a dielectric. The metal's colour is already carried
    /// by the surface behind it.
    static func gradient(
        keyDirection: SIMD3<Float>,
        reduceMotion: Bool
    ) -> LinearGradient {
        let ends = ends(keyDirection: keyDirection)

        // `toward` is the start, so location 0 is the edge the light is on. The
        // opposite arrangement is the easy mistake and it is self-consistent
        // enough to survive a glance: the surface still has one bright edge and
        // one dark one, they are simply the wrong way round, and it reads as the
        // light having moved to the other side of the room.
        return LinearGradient(
            stops: [
                .init(color: .white.opacity(reduceMotion ? 0 : 0.30), location: 0),
                // Neutral at the middle, so neither end bleeds across the surface.
                .init(color: .black.opacity(0.16), location: 0.5),
                .init(color: .black.opacity(reduceMotion ? 0.16 : 0.30), location: 1),
            ],
            startPoint: ends.toward,
            endPoint: ends.away
        )
    }
}
