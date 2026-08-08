import SwiftUI

/// A surface that behaves like a physical object: a metallic material whose
/// reflections respond as you move and tilt the device.
///
/// ```swift
/// Surface(material: .gold) {
///     VStack(alignment: .leading) {
///         Text("MEMBER").font(.caption).foregroundStyle(.secondary)
///         Spacer()
///         Text("A21 4471").monospacedDigit()
///     }
/// }
/// .frame(width: 353, height: 220)
/// ```
///
/// Size comes from `frame(width:height:)`. Placement, layout, spacing and
/// right-to-left all come from plain SwiftUI inside the content builder. The
/// content container fills the surface's bounds before `contentPadding` is
/// applied inside it, so `Spacer()` and alignments behave normally.
///
/// **Content is read as luminance.** Every material in this version is metallic,
/// and a metallic material keeps the lightness of your content and discards its
/// colour, so a blue element appears as the material's own colour at blue's
/// brightness. `.primary`, `.secondary` and `.tertiary` keep their relative
/// hierarchy, so most content needs no colour work at all.
public struct Surface<Content: View>: View {
    private let material: SurfaceMaterial
    private let cornerRadius: CGFloat
    private let contentPadding: CGFloat
    private let content: Content

    @Environment(\.surfaceTiltSource) private var tiltSource
    @Environment(\.surfaceGleam) private var gleam
    @Environment(\.surfaceLightOffset) private var lightOffset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// One model per surface. The motion hardware behind it is shared, so ten of
    /// these on screen still read the device once.
    @State private var reflection = SurfaceReflectionModel()
    @State private var isOnScreen = false

    /// - Parameters:
    ///   - material: What the surface is made of.
    ///   - cornerRadius: Continuous, squircle corners. The default suits a
    ///     card-sized surface; a much smaller or larger one wants its own, which
    ///     is why this is a parameter rather than a constant.
    ///   - contentPadding: The inset between your content and the surface's edge.
    ///     Enough to clear the default corner radius.
    ///   - content: Drawn into the material. Greys.
    public init(
        material: SurfaceMaterial = .gold,
        cornerRadius: CGFloat = 22,
        contentPadding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // The order is load-bearing: material, rim, silhouette, lean.
        return printedContent
            .surfaceMetal(
                material,
                keyDirection: reflection.keyDirection,
                diffuseAxis: reflection.diffuseAxis,
                gleam: gleam,
                lightOffset: lightOffset
            )
            .overlay {
                // After the material, so the rim stays a true hairline instead of
                // being retinted and swallowed by the metal.
                //
                // Handed the same light the material just took. A rim that sources
                // its own light disagrees with the gleam beside it.
                shape.stroke(
                    SurfaceRim.gradient(
                        keyDirection: reflection.keyDirection,
                        reduceMotion: reduceMotion
                    ),
                    lineWidth: SurfaceStyle.rimWidth
                )
            }
            .mask {
                // Cut last and cut soft. Both departures from a plain
                // `clipShape` before the material, and both load-bearing. See
                // SurfaceStyle.silhouetteFeather, and the shader's first act,
                // which is to un-premultiply: at a coverage pixel with alpha near
                // 0.004 the incoming half-precision colour carries enormous
                // relative error, and that divide amplifies it straight into the
                // shading. Cutting afterwards means the material never sees a
                // partial pixel.
                shape
                    .fill(.white)
                    .blur(radius: SurfaceStyle.silhouetteFeather)
            }
            .rotation3DEffect(
                .radians(reflection.tiltAngle),
                axis: (x: reflection.tiltAxis.x, y: reflection.tiltAxis.y, z: 0),
                perspective: SurfaceStyle.tiltPerspective
            )
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onChange(of: isOnScreen, initial: true) { updateSampling() }
            .onChange(of: scenePhase) { updateSampling() }
            .onChange(of: reduceMotion, initial: true) {
                reflection.setReduceMotion(reduceMotion)
            }
            .onChange(of: tiltSource, initial: true) {
                reflection.setTiltSource(tiltSource)
            }
    }

    /// The stock with the content on it, before any light reaches either.
    private var printedContent: some View {
        ZStack {
            SurfaceStyle.stock

            content
                // Resolves SwiftUI's own hierarchy to greys that stay legible once
                // the metal lifts the surface around them, so there is no
                // package-specific colour API to learn.
                .foregroundStyle(
                    SurfaceStyle.ink,
                    SurfaceStyle.inkSecondary,
                    SurfaceStyle.inkTertiary
                )
                // The material discards chroma anyway. Doing it here as well means
                // an Xcode preview shows what actually ships, rather than letting
                // an author work in colour and be surprised at runtime.
                .grayscale(1)
                // Fills the surface first, then `padding` insets it. The other
                // order pads the content's natural size instead, and `Spacer()`
                // stops reaching the edges.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(contentPadding)
        }
    }

    /// Motion must not run while the surface is off screen or the app is in the
    /// background, because it keeps sampling and spending power regardless.
    private func updateSampling() {
        reflection.setActive(isOnScreen && scenePhase == .active)
    }
}

// MARK: - Gleam and light

extension EnvironmentValues {
    @Entry var surfaceGleam: Double = 1
    @Entry var surfaceLightOffset: Double = 0
}

extension View {
    /// How much of the reflection shows, from `0` to `1`.
    ///
    /// At `0` the surface is flat matte and its appearance stops depending on
    /// device pose entirely. At `1` the material's full reflection response.
    ///
    /// Propagates through the environment, so it can be set once high in a tree.
    public func surfaceGleam(_ amount: Double) -> some View {
        environment(\.surfaceGleam, amount)
    }

    /// Where the light sits, as the resting highlight's distance from centre.
    ///
    /// `0` centres it, `-1` puts it at the left edge and `+1` at the right.
    /// Values outside that range clamp.
    ///
    /// This moves both of the surface's lights together, so the shading and the
    /// highlight keep agreeing about which side the light is on. Moving only one
    /// is what makes a surface look subtly wrong.
    ///
    /// Propagates through the environment, and that is deliberate rather than
    /// convenient: two surfaces on screen are in the same room, and one lit from
    /// the left beside one lit from the right is a bug. Set it once high in a
    /// tree and every surface below agrees.
    public func surfaceLightOffset(_ offset: Double) -> some View {
        environment(\.surfaceLightOffset, offset)
    }
}

// MARK: - Previews

#Preview("Materials") {
    // `.fixed` rather than `.deviceMotion`: a preview has no motion data, so the
    // surface would sit at its resting reflection and never move.
    ScrollView {
        VStack(spacing: 24) {
            ForEach(SurfaceMaterial.all, id: \.name) { material in
                Surface(material: material) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(material.name.uppercased())
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("A21 4471")
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                .frame(height: 200)
            }
        }
        .padding(24)
    }
    .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
}

#Preview("Gleam") {
    VStack(spacing: 24) {
        ForEach([0.0, 0.5, 1.0], id: \.self) { amount in
            Surface {
                Text("GLEAM \(amount, format: .number.precision(.fractionLength(1)))")
                    .font(.headline)
            }
            .frame(height: 140)
            .surfaceGleam(amount)
        }
    }
    .padding(24)
    .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
}
