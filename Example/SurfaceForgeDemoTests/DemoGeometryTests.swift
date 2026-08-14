import SwiftUI
import Testing

@testable import SurfaceForgeDemo

@Suite("Light geometry")
struct LightGeometryTests {
    @Test("An object in the spotlight carries no offset")
    func spotlightIsZero() {
        #expect(LightGeometry.offset(midX: 200, spotlightX: 200, span: 200) == 0)
    }

    @Test("An object right of the light is lit on its left half")
    func signFollowsTheRoom() {
        #expect(LightGeometry.offset(midX: 300, spotlightX: 200, span: 200) < 0)
        #expect(LightGeometry.offset(midX: 100, spotlightX: 200, span: 200) > 0)
    }

    @Test("The offset clamps at the light's reach")
    func clampsAtFullDeflection() {
        #expect(LightGeometry.offset(midX: 1000, spotlightX: 0, span: 100) == -1)
        #expect(LightGeometry.offset(midX: -1000, spotlightX: 0, span: 100) == 1)
    }

    @Test("The offset falls as the object walks right")
    func monotoneInPosition() {
        var previous = Double.infinity
        for midX in stride(from: 0.0, through: 400.0, by: 50.0) {
            let offset = LightGeometry.offset(midX: midX, spotlightX: 200, span: 200)
            #expect(offset <= previous)
            previous = offset
        }
    }

    @Test("Full deflection lands before the object leaves the room")
    func gainCompensatesTheTravelDefect() {
        // The light travels only ~66% of a card at full offset, so the gleam
        // must peak at span/gain rather than at the room's edge. This is the
        // test that pins the compensation.
        let atGainPoint = LightGeometry.offset(
            midX: 200 - 200 / LightGeometry.gain,
            spotlightX: 200,
            span: 200
        )
        #expect(abs(atGainPoint - 1) < 1e-9)
    }
}

@Suite("Tilt drag mapping")
struct TiltDragMapperTests {
    @Test("No travel is no tilt")
    func restIsZero() {
        let pose = TiltDragMapper.pose(for: .zero)
        #expect(pose.pitch == 0 && pose.roll == 0)
    }

    @Test("Up is positive pitch, right is positive roll")
    func signContract() {
        let up = TiltDragMapper.pose(for: CGSize(width: 0, height: -40))
        let right = TiltDragMapper.pose(for: CGSize(width: 40, height: 0))

        #expect(up.pitch > 0 && up.roll == 0)
        #expect(right.roll > 0 && right.pitch == 0)
    }

    @Test("Any drag stays inside the tilt limit")
    func staysInsideTheLimit() {
        // At or under, not strictly under: tanh saturates to exactly 1.0 in
        // floating point, so an extreme drag lands exactly on the limit.
        for magnitude in [10.0, 100.0, 1000.0, 1e6] {
            let pose = TiltDragMapper.pose(
                for: CGSize(width: magnitude, height: -magnitude)
            )
            #expect(abs(pose.pitch) <= TiltDragMapper.limit)
            #expect(abs(pose.roll) <= TiltDragMapper.limit)
        }
    }

    @Test("Small drags read linearly")
    func nearLinearUnderTheFinger() {
        // Six points is one degree, within 2%, so the surface tracks the
        // finger before tanh's shoulder takes over.
        let pose = TiltDragMapper.pose(for: CGSize(width: 6, height: 0))
        #expect(abs(pose.roll - 1) < 0.02)
    }
}
