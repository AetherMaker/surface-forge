import SurfaceForge
import SwiftUI

/// One piece in the room: a finish, worn by an object and metal that suit it.
struct Exhibit: Identifiable, Hashable {
    var id: String { finish.name }

    let finish: SurfaceFinish
    let design: Design
    let material: SurfaceMaterial
    let ratio: CGFloat
    let cornerRadius: CGFloat

    enum Design: Hashable {
        case membershipCard, eventTicket, bankCard, keyCard, expeditionPass
        case giftCard, plaque, shopTag, boardingPass, recordClub
    }

    /// Every ratio stays near the card's calibrated 353:220; squares let the
    /// resting highlight drift.
    static let all: [Exhibit] = [
        Exhibit(finish: .polished, design: .membershipCard, material: .gold,
                ratio: 353 / 220, cornerRadius: 22),
        Exhibit(finish: .brushed, design: .eventTicket, material: .silver,
                ratio: 2.0, cornerRadius: 14),
        Exhibit(finish: .pinstripe, design: .bankCard, material: .brass,
                ratio: 353 / 220, cornerRadius: 22),
        Exhibit(finish: .carbonTwill, design: .keyCard, material: .gunmetal,
                ratio: 353 / 220, cornerRadius: 16),
        Exhibit(finish: .topographic, design: .expeditionPass, material: .copper,
                ratio: 1.8, cornerRadius: 14),
        Exhibit(finish: .basketweave, design: .giftCard, material: .roseGold,
                ratio: 353 / 220, cornerRadius: 20),
        Exhibit(finish: .clousDeParis, design: .plaque, material: .gold,
                ratio: 353 / 220, cornerRadius: 4),
        Exhibit(finish: .knurling, design: .shopTag, material: .gunmetal,
                ratio: 1.9, cornerRadius: 10),
        Exhibit(finish: .sandblasted, design: .boardingPass, material: .silver,
                ratio: 1.8, cornerRadius: 16),
        Exhibit(finish: .sunburst, design: .recordClub, material: .brass,
                ratio: 353 / 220, cornerRadius: 22),
    ]
}

/// The room's state: ten exhibits, one under the light.
@MainActor @Observable
final class RoomModel {
    let exhibits = Exhibit.all

    var centeredID: String? = Exhibit.all.first?.id
    var focusedID: String?

    var gleam = 1.0

    /// Where the spotlight hangs, -1 left wall to +1 right wall. The knob that
    /// replaced the old light-offset slider: it moves the room's light, and
    /// every card's own offset follows from standing where it stands.
    var spotlightBias = 0.0

    var followsDevice = true
    var fixedPitch = -8.0
    var fixedRoll = 14.0

    var showsDrawer = false

    /// Per-exhibit dressing, so an edit made in focus rides back to the room.
    private var materials: [String: SurfaceMaterial] = [:]
    private var grainAngles: [String: Double] = [:]

    var roomTiltSource: SurfaceTiltSource {
        followsDevice ? .deviceMotion : .fixed(pitch: fixedPitch, roll: fixedRoll)
    }

    /// The pose a released drag settles toward, and the pose the wings hold.
    var restPose: (pitch: Double, roll: Double) {
        followsDevice ? (0, 0) : (fixedPitch, fixedRoll)
    }

    /// Only the piece under the light lives with the device; the wings hold
    /// still, the way pieces in a case do while you lean toward one.
    func tiltSource(for exhibit: Exhibit) -> SurfaceTiltSource {
        centeredID == exhibit.id
            ? roomTiltSource
            : .fixed(pitch: restPose.pitch, roll: restPose.roll)
    }

    // MARK: - Dressing

    func baseMaterial(for exhibit: Exhibit) -> SurfaceMaterial {
        materials[exhibit.id] ?? exhibit.material
    }

    func setMaterial(_ material: SurfaceMaterial, for exhibit: Exhibit) {
        materials[exhibit.id] = material
    }

    func grainAngle(for exhibit: Exhibit) -> Double {
        grainAngles[exhibit.id] ?? 0
    }

    func setGrainAngle(_ angle: Double, for exhibit: Exhibit) {
        grainAngles[exhibit.id] = angle
    }

    func dressedMaterial(for exhibit: Exhibit) -> SurfaceMaterial {
        baseMaterial(for: exhibit)
            .finish(exhibit.finish.aimed(at: .degrees(grainAngle(for: exhibit))))
    }

    // MARK: - Focus

    func focus(_ exhibit: Exhibit) {
        centeredID = exhibit.id
        focusedID = exhibit.id
    }

    func unfocus() {
        focusedID = nil
    }

    var focusedExhibit: Exhibit? {
        exhibits.first { $0.id == focusedID }
    }
}
