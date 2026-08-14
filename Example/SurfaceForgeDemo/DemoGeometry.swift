import SwiftUI

/// Where the room's light falls on an object, from where the object stands.
enum LightGeometry {
    /// The shader's light travels only about 66% of the card at full offset,
    /// a known defect, so an ungained mapping gives up before the edge.
    /// 1.5 is roughly 1 / 0.66.
    static let gain = 1.5

    /// The light stays put; the object carries its own offset through it.
    /// An object right of the spotlight is lit on its left half, which is why
    /// the sign flips.
    static func offset(midX: CGFloat, spotlightX: CGFloat, span: CGFloat) -> Double {
        guard span > 0 else { return 0 }
        let raw = Double((spotlightX - midX) / span) * gain
        return min(max(raw, -1), 1)
    }
}

/// Finger travel into a surface pose.
enum TiltDragMapper {
    /// Past this the card would read as flipping over, not tilting.
    static let limit = 30.0

    /// Six points of travel per degree keeps a full tilt inside one thumb arc.
    static let pointsPerDegree = 6.0

    /// tanh rather than a clamp: linear under the finger, asymptotic at the
    /// limit, no corner mid-gesture.
    ///
    /// Signs: drag up tips the top away (positive pitch), drag right rolls
    /// right. Flipping either is a one-character change and a deliberate one,
    /// which is what the sign tests are for.
    static func pose(for translation: CGSize) -> (pitch: Double, roll: Double) {
        (
            pitch: limit * tanh(-translation.height / pointsPerDegree / limit),
            roll: limit * tanh(translation.width / pointsPerDegree / limit)
        )
    }
}
