import SurfaceForge
import SwiftUI

/// The room: one movable spotlight, ten exhibits travelling through it.
struct RoomView: View {
    @State private var model = RoomModel()

    var body: some View {
        GeometryReader { room in
            ZStack {
                background(in: room.size)
                carousel(in: room.size)

                if let exhibit = model.focusedExhibit {
                    FocusView(exhibit: exhibit, model: model, roomSize: room.size)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottomTrailing) { drawerButton }
        .sheet(isPresented: $model.showsDrawer) {
            ControlsDrawer(model: model)
        }
        // The room's own light, set once: every surface below shares it.
        .surfaceGleam(model.gleam)
        .surfaceLean(model.lean)
    }

    /// Where the spotlight hangs on the room's wall.
    private func spotlightX(in size: CGSize) -> CGFloat {
        size.width * (0.5 + 0.3 * model.spotlightBias)
    }

    /// A pool of light under the spotlight. Pure gradient, no assets.
    private func background(in size: CGSize) -> some View {
        RadialGradient(
            colors: [.white.opacity(0.06), .clear],
            center: UnitPoint(x: 0.5 + 0.3 * model.spotlightBias, y: 0.5),
            startRadius: 0,
            endRadius: size.width * 0.55
        )
        .ignoresSafeArea()
    }

    private func carousel(in size: CGSize) -> some View {
        // Equal slots are what make viewAligned snapping centre correctly.
        let slotWidth = min(500, size.width * 0.78)

        return ScrollView(.horizontal) {
            LazyHStack(spacing: 18) {
                ForEach(model.exhibits) { exhibit in
                    GeometryReader { geo in
                        ExhibitView(exhibit: exhibit, model: model, width: slotWidth)
                            // Per surface on purpose: the light stays in the
                            // room and each piece carries its own position
                            // through it.
                            .surfaceLightOffset(LightGeometry.offset(
                                midX: geo.frame(in: .named("room")).midX,
                                spotlightX: spotlightX(in: size),
                                span: size.width / 2
                            ))
                            .surfaceTiltSource(model.tiltSource(for: exhibit))
                            .opacity(model.focusedID == exhibit.id ? 0 : 1)
                            .onTapGesture {
                                withAnimation(.spring(duration: 0.35)) {
                                    model.focus(exhibit)
                                }
                            }
                    }
                    .frame(
                        width: slotWidth,
                        height: slotWidth / exhibit.ratio + 50
                    )
                    // The wings recede: smaller, dimmer, turned slightly away.
                    // Visual-only transforms, so no shader uniform ever rides
                    // this animation.
                    .scrollTransition(axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(1 - 0.1 * abs(phase.value))
                            .rotation3DEffect(
                                .degrees(-8 * phase.value),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.5
                            )
                            .opacity(1 - 0.35 * abs(phase.value))
                    }
                }
            }
            .scrollTargetLayout()
        }
        .coordinateSpace(name: "room")
        .contentMargins(.horizontal, (size.width - slotWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $model.centeredID)
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    private var drawerButton: some View {
        Button {
            model.showsDrawer = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(14)
                .background(.white.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(20)
        .opacity(model.focusedID == nil ? 1 : 0)
    }
}

#Preview {
    RoomView()
        .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
}
