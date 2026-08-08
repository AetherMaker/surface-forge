import SurfaceForge
import SwiftUI

/// One surface and the controls that drive it.
///
/// The same shape the eventual Mac app takes: a live preview above, every knob
/// below. Tilt the phone and the reflection follows; the sliders are what makes
/// it reviewable where there is no motion sensor.
struct DemoView: View {
    @State private var material = SurfaceMaterial.gold
    @State private var gleam = 1.0
    @State private var lightOffset = 0.0
    @State private var usesDeviceMotion = true
    @State private var pitch = -8.0
    @State private var roll = 14.0
    @State private var cornerRadius = 22.0

    private var tiltSource: SurfaceTiltSource {
        usesDeviceMotion ? .deviceMotion : .fixed(pitch: pitch, roll: roll)
    }

    var body: some View {
        VStack(spacing: 0) {
            preview
            Divider()
            controls
        }
        .background(Color(white: 0.10).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var preview: some View {
        Surface(material: material, cornerRadius: cornerRadius) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MEMBER SINCE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("2019")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(material.name.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("4471 0982 3310")
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: 353)
        .aspectRatio(353.0 / 220.0, contentMode: .fit)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .surfaceGleam(gleam)
        .surfaceLightOffset(lightOffset)
        .surfaceTiltSource(tiltSource)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                materialPicker

                slider("Light offset", value: $lightOffset, in: -1...1)
                slider("Gleam", value: $gleam, in: 0...1)
                slider("Corner radius", value: $cornerRadius, in: 0...60, unit: "pt")

                Toggle("Follow the device", isOn: $usesDeviceMotion)
                    .font(.system(size: 13, weight: .medium))

                if !usesDeviceMotion {
                    slider("Pitch", value: $pitch, in: -45...45, unit: "°")
                    slider("Roll", value: $roll, in: -45...45, unit: "°")
                }
            }
            .padding(20)
        }
        .frame(height: 300)
    }

    private var materialPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SurfaceMaterial.all, id: \.name) { candidate in
                    Button {
                        material = candidate
                    } label: {
                        Circle()
                            .fill(candidate.approximateColor)
                            .frame(width: 34, height: 34)
                            .overlay {
                                Circle().strokeBorder(
                                    .white.opacity(candidate == material ? 0.9 : 0),
                                    lineWidth: 2
                                )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

#Preview {
    DemoView()
}
