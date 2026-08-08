import SwiftUI

/// What moves a surface's reflection.
///
/// A struct rather than an enum so later versions can add a drag-driven or
/// drifting source without breaking an exhaustive `switch`.
public struct SurfaceTiltSource: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case deviceMotion
        case fixed(pitch: Double, roll: Double)
    }

    let kind: Kind

    /// Follows the device's live attitude through Core Motion.
    ///
    /// Previews and the Simulator report no motion, so the surface holds its
    /// resting reflection there. Use ``fixed(pitch:roll:)`` to see the material
    /// move away from hardware.
    public static let deviceMotion = SurfaceTiltSource(kind: .deviceMotion)

    /// Holds the surface at one angle, in degrees.
    ///
    /// Repeatable, so it also drives screenshots and tests.
    ///
    /// - Parameters:
    ///   - pitch: Positive tips the top edge away from the viewer.
    ///   - roll: Positive tips the right edge away.
    public static func fixed(pitch: Double, roll: Double) -> SurfaceTiltSource {
        SurfaceTiltSource(kind: .fixed(pitch: pitch, roll: roll))
    }

    @MainActor
    func makeAttitudeSource() -> any SurfaceAttitudeSource {
        switch kind {
        case .deviceMotion:
            SurfaceDeviceMotionSource()
        case let .fixed(pitch, roll):
            SurfaceFixedMotionSource(pitch: pitch, roll: roll)
        }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    @Entry var surfaceTiltSource: SurfaceTiltSource = .deviceMotion
}

extension View {
    /// Sets what moves the reflection on surfaces in this hierarchy.
    public func surfaceTiltSource(_ source: SurfaceTiltSource) -> some View {
        environment(\.surfaceTiltSource, source)
    }
}
