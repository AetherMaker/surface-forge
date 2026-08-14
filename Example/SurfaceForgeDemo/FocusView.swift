import SurfaceForge
import SwiftUI

/// One exhibit under the light: drag to tilt it, dress it below.
struct FocusView: View {
    let exhibit: Exhibit
    let model: RoomModel
    let roomSize: CGSize

    @State private var tilt = TiltState.resting

    private enum TiltState: Equatable {
        case resting
        case dragging(pitch: Double, roll: Double)
        case settling(pitch: Double, roll: Double)
    }

    var body: some View {
        VStack(spacing: 26) {
            Spacer()

            focusedCard

            Placard(name: exhibit.finish.name)

            VStack(spacing: 16) {
                materialRow
                if exhibit.finish.hasDirection {
                    grainSlider
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The room dims behind the piece; tapping the dark puts it back.
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(duration: 0.35)) { model.unfocus() }
                }
        }
    }

    // MARK: - The piece

    private var focusedCard: some View {
        let width = min(roomSize.width - 40, 520)

        return Surface(
            material: model.dressedMaterial(for: exhibit),
            cornerRadius: exhibit.cornerRadius
        ) {
            ExhibitContent(design: exhibit.design, model: model, exhibit: exhibit)
        }
        .frame(width: width, height: width / exhibit.ratio)
        .modifier(draggedTilt)
        .gesture(tiltGesture)
    }

    /// Drag overrides the room's source while a finger is down or the spring
    /// is settling; resting hands the same code path back to the room, so the
    /// surface's identity never changes across the handover.
    private var draggedTilt: DraggedTilt {
        switch tilt {
        case .resting:
            DraggedTilt(
                pitch: model.restPose.pitch,
                roll: model.restPose.roll,
                overriding: false,
                restingSource: model.roomTiltSource
            )
        case .dragging(let pitch, let roll), .settling(let pitch, let roll):
            DraggedTilt(
                pitch: pitch,
                roll: roll,
                overriding: true,
                restingSource: model.roomTiltSource
            )
        }
    }

    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let pose = TiltDragMapper.pose(for: value.translation)
                // No animation: the finger is the animation.
                tilt = .dragging(pitch: pose.pitch, roll: pose.roll)
            }
            .onEnded { _ in
                withAnimation(
                    .spring(duration: 0.5, bounce: 0.25),
                    completionCriteria: .logicallyComplete
                ) {
                    tilt = .settling(
                        pitch: model.restPose.pitch,
                        roll: model.restPose.roll
                    )
                } completion: {
                    tilt = .resting
                }
            }
    }

    // MARK: - Dressing

    private var materialRow: some View {
        HStack(spacing: 10) {
            ForEach(SurfaceMaterial.all, id: \.name) { candidate in
                let selected = model.baseMaterial(for: exhibit).name == candidate.name
                Button {
                    // The material reaches the shader as uniforms, and
                    // interpolating two metals' tints mid-animation is not a
                    // metal. Disabling the transaction outright, so the focus
                    // spring in flight cannot adopt the change either.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        model.setMaterial(candidate, for: exhibit)
                    }
                } label: {
                    Circle()
                        .fill(candidate.approximateColor)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle().strokeBorder(
                                .white.opacity(selected ? 0.9 : 0),
                                lineWidth: 2
                            )
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grainSlider: some View {
        HStack(spacing: 12) {
            Text("Grain")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { model.grainAngle(for: exhibit) },
                    set: { model.setGrainAngle($0, for: exhibit) }
                ),
                in: 0...180
            )
            Text("\(Int(model.grainAngle(for: exhibit)))°")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 40)
    }
}

/// Interpolates pitch and roll SwiftUI-side while every frame reaches the
/// package as an exact `.fixed` pose: the environment carries no animatable
/// data, so the shader never sees an interpolated uniform. Per-frame source
/// swaps are cheap and exact, because the fixed source emits its sample
/// synchronously on start.
struct DraggedTilt: ViewModifier, Animatable {
    var pitch: Double
    var roll: Double
    var overriding: Bool
    var restingSource: SurfaceTiltSource

    // nonisolated: ViewModifier pulls the struct onto the main actor, and
    // Animatable's interpolation runs off it. Value-type reads of Sendable
    // fields, so there is nothing to race.
    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(pitch, roll) }
        set {
            pitch = newValue.first
            roll = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.surfaceTiltSource(
            overriding ? .fixed(pitch: pitch, roll: roll) : restingSource
        )
    }
}
