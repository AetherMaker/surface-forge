import SurfaceForge
import SwiftUI
import Testing
import UIKit

// Renders a surface for real and reads its pixels back.
//
// These live in the demo app rather than in the package because they need a
// window scene, which a SwiftPM test bundle does not have. Without one nothing
// reaches the render server and every pixel reads back black, including a solid
// red control.
//
// They use only the public API, so they check what an adopter would get rather
// than what the internals happen to do.

/// Draws a view through the render server and returns its middle band.
///
/// `ImageRenderer` cannot do this job: it does not run Metal view effects, so it
/// would return the bare stock and report success while the material never ran.
@MainActor
private func renderedPixels<V: View>(
    of view: V,
    size: CGSize = CGSize(width: 353, height: 220)
) async -> [(r: Int, g: Int, b: Int)] {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    host.view.backgroundColor = .black

    let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.windowScene = scene
    window.rootViewController = host
    window.makeKeyAndVisible()
    window.layoutIfNeeded()

    // The material only runs once the model has a sample, and the fixed source
    // emits from a Task. Give the run loop enough turns for the sample to land
    // and for the resulting layout pass to draw.
    for _ in 0..<12 {
        try? await Task.sleep(for: .milliseconds(50))
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
    }

    guard let cg = image.cgImage else { return [] }

    let width = cg.width
    let height = cg.height
    var raw = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
        let context = CGContext(
            data: &raw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return [] }

    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

    // The middle band only, away from the corners the mask rounds off and away
    // from the rim's hairline.
    var pixels: [(r: Int, g: Int, b: Int)] = []
    for y in (height / 3)..<(2 * height / 3) {
        for x in (width / 3)..<(2 * width / 3) {
            let i = (y * width + x) * 4
            pixels.append((Int(raw[i]), Int(raw[i + 1]), Int(raw[i + 2])))
        }
    }
    return pixels
}

private func mean(_ pixels: [(r: Int, g: Int, b: Int)]) -> (r: Int, g: Int, b: Int) {
    guard !pixels.isEmpty else { return (0, 0, 0) }
    return (
        pixels.reduce(0) { $0 + $1.r } / pixels.count,
        pixels.reduce(0) { $0 + $1.g } / pixels.count,
        pixels.reduce(0) { $0 + $1.b } / pixels.count
    )
}

/// Rec. 601 luma, the same weighting the shader applies to content.
private func luminance(_ c: (r: Int, g: Int, b: Int)) -> Double {
    let r = Double(c.r) * 0.299
    let g = Double(c.g) * 0.587
    let b = Double(c.b) * 0.114
    return r + g + b
}

/// A bare surface with no content, so nothing but the material is under test.
@MainActor
private func surface(_ material: SurfaceMaterial, gleam: Double = 1) -> some View {
    Surface(material: material) { Color.clear }
        .frame(width: 353, height: 220)
        .surfaceGleam(gleam)
        .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
}

@MainActor
@Suite("What a surface renders")
struct SurfaceRenderTests {
    @Test("The harness draws anything at all")
    func harnessDrawsAnything() async {
        // The positive control, and the reason the rest of this file can be
        // trusted. Every test below reads pixels back, and "all black" is what
        // both a broken harness and a broken shader produce. Without this there
        // is no way to tell them apart.
        let control = mean(await renderedPixels(of: Color(red: 1, green: 0, blue: 0)))

        #expect(control.r > 200, "the harness itself drew nothing: \(control)")
        #expect(control.g < 60, "the harness drew something unexpected: \(control)")
    }

    @Test("Gold renders as gold, not as grey stock and not as magenta")
    func goldRendersAsGold() async {
        let c = mean(await renderedPixels(of: surface(.gold)))

        // Magenta is the probe's colour, and what a resolved-but-wrong shader
        // looks like.
        #expect(!(c.r > 200 && c.g < 60 && c.b > 200), "rendered magenta: \(c)")

        // Grey means the shader never ran. Gold separates its channels.
        #expect(c.r > c.g, "no warm cast, so the material did not run: \(c)")
        #expect(c.g > c.b, "no warm cast, so the material did not run: \(c)")
        #expect(c.r - c.b > 40, "too neutral to be gold: \(c)")

        #expect(c.r > 120 && c.r < 250, "gold landed at \(c)")
    }

    @Test("Silver stays near neutral where gold does not")
    func silverStaysNeutral() async {
        let silver = mean(await renderedPixels(of: surface(.silver)))
        let gold = mean(await renderedPixels(of: surface(.gold)))

        #expect(silver.r - silver.b < 20, "silver picked up a cast: \(silver)")
        #expect(gold.r - gold.b > silver.r - silver.b, "gold \(gold) vs silver \(silver)")
    }

    @Test("Every material renders a distinct colour")
    func everyMaterialIsDistinct() async {
        var seen: [String: (r: Int, g: Int, b: Int)] = [:]
        for material in SurfaceMaterial.all {
            seen[material.name] = mean(await renderedPixels(of: surface(material)))
        }

        for (nameA, a) in seen {
            for (nameB, b) in seen where nameA < nameB {
                let distance = abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
                #expect(distance > 8, "\(nameA) \(a) matches \(nameB) \(b)")
            }
        }
    }

    /// What each material renders on bare stock, at the fixed angle above.
    ///
    /// The point of the whole file. Any change to the shader, the stock, the
    /// lights or a tint moves one of these, and this says which and by how much.
    /// Update them deliberately, never to make a run go green.
    static let reference: [String: (r: Int, g: Int, b: Int)] = [
        "Gold": (241, 227, 164),
        "Silver": (240, 240, 241),
        "Rose gold": (241, 227, 216),
        "Copper": (240, 210, 185),
        "Brass": (239, 233, 195),
        "Gunmetal": (218, 221, 225),
    ]

    @Test("Every material renders the colour it is meant to")
    func materialsMatchTheirReference() async {
        // Six levels of tolerance. Tight enough to catch a real change, since
        // the materials are 20 to 40 levels apart in their strongest channel,
        // and loose enough to survive GPU differences between machines.
        let tolerance = 6

        for material in SurfaceMaterial.all {
            guard let want = Self.reference[material.name] else {
                Issue.record("\(material.name) has no reference colour")
                continue
            }

            let got = mean(await renderedPixels(of: surface(material)))
            let drift = max(abs(got.r - want.r), abs(got.g - want.g), abs(got.b - want.b))

            #expect(
                drift <= tolerance,
                "\(material.name) moved to \(got.r),\(got.g),\(got.b) from \(want.r),\(want.g),\(want.b)"
            )
        }
    }

    @Test("Gleam at zero drops the surface to a flat matte")
    func gleamZeroFlattensTheSurface() async {
        // The claim `surfaceGleam` makes, and one nothing else can check: at 0
        // the reflection is gone, so the surface must be duller than at 1.
        let lit = mean(await renderedPixels(of: surface(.gold, gleam: 1)))
        let matte = mean(await renderedPixels(of: surface(.gold, gleam: 0)))

        #expect(
            matte.r + matte.g + matte.b < lit.r + lit.g + lit.b,
            "matte \(matte) is not duller than lit \(lit)"
        )
    }
}
