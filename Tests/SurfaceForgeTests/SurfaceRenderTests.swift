import SwiftUI
import Testing
import UIKit

@testable import SurfaceForge

/// Renders a surface through the real render server and reports its pixels.
///
/// `ImageRenderer` cannot do this job: it does not run Metal view effects, so it
/// would return the bare stock and report success while the material never ran.
/// Hosting in a window and reading back the drawn hierarchy is what actually
/// exercises the shader.
@MainActor
private func renderedPixels<V: View>(
    of view: V,
    size: CGSize = CGSize(width: 353, height: 220)
) async -> [(r: Int, g: Int, b: Int)] {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    host.view.backgroundColor = .black

    // A window with no scene draws nothing at all, and reads back as solid black
    // rather than as an error. That is indistinguishable from a shader that
    // renders black, which is why `harnessDrawsAnything` exists below.
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
    let r = pixels.reduce(0) { $0 + $1.r } / pixels.count
    let g = pixels.reduce(0) { $0 + $1.g } / pixels.count
    let b = pixels.reduce(0) { $0 + $1.b } / pixels.count
    return (r, g, b)
}

@MainActor
@Suite(
    "What a surface actually renders",
    .disabled(
        """
        Needs a host app. A SwiftPM test bundle has no window scene, so nothing \
        reaches the render server and every pixel reads back black, including \
        the positive control. Enable these once there is an app target to run \
        them in.
        """
    )
)
struct SurfaceRenderTests {
    /// A bare surface with no content, so nothing but the material is under test.
    private func surface(
        _ material: SurfaceMaterial,
        gleam: Double = 1
    ) -> some View {
        Surface(material: material) { Color.clear }
            .frame(width: 353, height: 220)
            .surfaceGleam(gleam)
            .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
    }

    @Test("The harness draws anything at all")
    func harnessDrawsAnything() async {
        // The positive control. Every other test here reads back pixels, and
        // "all black" is what both a broken harness and a broken shader produce.
        // Without this there is no way to tell them apart.
        let control = mean(
            await renderedPixels(of: Color(red: 1, green: 0, blue: 0))
        )

        #expect(control.r > 200, "the harness itself drew nothing: \(control)")
        #expect(control.g < 60, "the harness drew something unexpected: \(control)")
    }

    @Test("Gold renders as gold, not as grey stock and not as magenta")
    func goldRendersAsGold() async {
        let pixels = await renderedPixels(of: surface(.gold))
        let c = mean(pixels)

        #expect(!pixels.isEmpty, "nothing was drawn")

        // Magenta is the probe's colour, and it is what a resolved-but-wrong
        // shader looks like.
        #expect(!(c.r > 200 && c.g < 60 && c.b > 200), "rendered magenta: \(c)")

        // Grey stock means the shader never ran. Gold has to separate its
        // channels.
        #expect(c.r > c.g, "no warm cast, so the material did not run: \(c)")
        #expect(c.g > c.b, "no warm cast, so the material did not run: \(c)")
        #expect(c.r - c.b > 40, "too neutral to be gold: \(c)")

        // And it must not have gone black or blown out.
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
                #expect(distance > 8, "\(nameA) \(a) is indistinguishable from \(nameB) \(b)")
            }
        }
    }

    @Test("Gunmetal is darker than every other material")
    func gunmetalIsDarkest() async {
        // The one built-in that changes the surface's value rather than its hue,
        // so this pins the claim its doc comment makes.
        let gunmetal = mean(await renderedPixels(of: surface(.gunmetal)))
        let gunmetalLuma = gunmetal.r + gunmetal.g + gunmetal.b

        for material in SurfaceMaterial.all where material.name != "Gunmetal" {
            let other = mean(await renderedPixels(of: surface(material)))
            #expect(
                gunmetalLuma < other.r + other.g + other.b,
                "gunmetal \(gunmetal) is not darker than \(material.name) \(other)"
            )
        }
    }
}
