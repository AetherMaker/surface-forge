import SwiftUI

/// The knobs that survived: room lighting only. Dressing lives on the piece.
struct ControlsDrawer: View {
    @Bindable var model: RoomModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            slider("Gleam", value: $model.gleam, in: 0...1)
            // Moves the spotlight itself; each piece's own offset follows
            // from standing where it stands.
            slider("Light position", value: $model.spotlightBias, in: -1...1)

            Toggle("Follow the device", isOn: $model.followsDevice)
                .font(.system(size: 13, weight: .medium))

            if !model.followsDevice {
                slider("Pitch", value: $model.fixedPitch, in: -45...45, unit: "°")
                slider("Roll", value: $model.fixedRoll, in: -45...45, unit: "°")
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationDetents([.height(280)])
        .presentationBackgroundInteraction(.enabled(upThrough: .height(280)))
        .presentationBackground(Color(white: 0.12))
        .preferredColorScheme(.dark)
    }

    private func slider(
        _ label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        unit: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value.wrappedValue, format: .number.precision(.fractionLength(unit.isEmpty ? 2 : 0)))\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13, weight: .medium))

            Slider(value: value, in: range)
        }
    }
}
