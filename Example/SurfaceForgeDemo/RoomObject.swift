import SurfaceForge
import SwiftUI

/// One exhibit: its surface, and a placard the way a museum labels a piece.
struct ExhibitView: View {
    let exhibit: Exhibit
    let model: RoomModel
    let width: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Surface(
                material: model.dressedMaterial(for: exhibit),
                cornerRadius: exhibit.cornerRadius
            ) {
                ExhibitContent(design: exhibit.design, model: model, exhibit: exhibit)
            }
            .frame(width: width, height: width / exhibit.ratio)

            Placard(name: exhibit.finish.name)
                .padding(.top, 14)
        }
    }
}

/// The label under a piece: a hairline and small tracked capitals. Quiet on
/// purpose, so the metal does the talking.
struct Placard: View {
    let name: String

    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .frame(width: 26, height: 1)
                .foregroundStyle(.white.opacity(0.22))
            Text(name.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// Ten designs, so the ten finishes each dress something worth engraving.
struct ExhibitContent: View {
    let design: Exhibit.Design
    let model: RoomModel
    let exhibit: Exhibit

    var body: some View {
        switch design {
        case .membershipCard: membershipCard
        case .eventTicket: eventTicket
        case .bankCard: bankCard
        case .keyCard: keyCard
        case .expeditionPass: expeditionPass
        case .giftCard: giftCard
        case .plaque: plaque
        case .shopTag: shopTag
        case .boardingPass: boardingPass
        case .recordClub: recordClub
        }
    }

    /// This is the README's front page. Change either only together.
    private var membershipCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MEMBER SINCE")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("2019")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.baseMaterial(for: exhibit).name.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("4471 0982 3310")
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var eventTicket: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SURFACEFORGE LIVE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                Text("Hall 3 · Door B")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("AUG 14 · 21:00")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            DashedRule()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .frame(width: 1)
                .foregroundStyle(.tertiary)
            VStack(spacing: 2) {
                Text("ROW")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("G12")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
            }
        }
    }

    private var bankCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRIVATE BANKING")
                .font(.system(size: 11, weight: .semibold))
                .tracking(3)
            Spacer()
            Text("EST. 1897")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("A. MERIDIAN")
                .font(.system(size: 16, weight: .medium))
                .tracking(1)
                .foregroundStyle(.secondary)
        }
    }

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ACCESS")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(4)
                Spacer()
                Circle()
                    .strokeBorder(.secondary, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }
            Spacer()
            Text("LEVEL 9 · ALL DOORS")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var expeditionPass: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SUMMIT CLUB")
                .font(.system(size: 12, weight: .semibold))
                .tracking(3)
            Spacer()
            Text("EXPEDITION Nº 07")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("36°34′ N · 51°25′ E")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var giftCard: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("FOR YOU")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .tracking(4)
            Text("maison dorée")
                .font(.system(size: 11, design: .serif).italic())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var plaque: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("EXCELLENCE")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .tracking(6)
            Rectangle()
                .frame(width: 64, height: 1)
                .foregroundStyle(.secondary)
            Text("AWARDED MMXXVI")
                .font(.system(size: 10, design: .serif))
                .tracking(3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var shopTag: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MACHINE SHOP")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                Spacer()
                Text("BAY 4 · LATHE")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Nº 118")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var boardingPass: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BOARDING PASS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 24) {
                passColumn("GATE", "B44")
                passColumn("SEAT", "12A")
                passColumn("GROUP", "1")
                Spacer()
            }
        }
    }

    private var recordClub: some View {
        VStack(spacing: 4) {
            Spacer()
            Text("RECORD CLUB")
                .font(.system(size: 13, weight: .semibold))
                .tracking(4)
            Text("33⅓ · SIDE A")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func passColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .monospacedDigit()
        }
    }
}

/// The ticket's perforation line.
private struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}
