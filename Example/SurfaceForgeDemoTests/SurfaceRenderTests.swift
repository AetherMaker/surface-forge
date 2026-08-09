import SurfaceForge
import SwiftUI
import Testing
import UIKit

// Renders a surface for real and reads its pixels back.
//
// These live in the demo app because they need a window scene, which a SwiftPM
// test bundle does not have. Without one nothing reaches the render server and
// every pixel reads back black.
//
// They use only the public API, so they check what an adopter gets rather than
// what the internals happen to do.

/// Draws a view through the render server and returns its middle band.
///
/// `ImageRenderer` cannot do this job: it does not run Metal view effects, so it
/// would return the bare stock and report success while the material never ran.
@MainActor
private func rawPixels<V: View>(
    of view: V,
    size: CGSize
) async -> (pixels: [UInt8], width: Int, height: Int) {
    let host = UIHostingController(rootView: view)
    host.safeAreaRegions = []
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

    guard let cg = image.cgImage else { return ([], 0, 0) }

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
    else { return ([], 0, 0) }

    context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    return (raw, width, height)
}

/// The middle band, away from the corners the mask rounds off and away from the
/// rim's hairline.
@MainActor
private func renderedPixels<V: View>(
    of view: V,
    size: CGSize = CGSize(width: 353, height: 220)
) async -> [(r: Int, g: Int, b: Int)] {
    let raw = await rawPixels(of: view, size: size)
    guard !raw.pixels.isEmpty else { return [] }

    var pixels: [(r: Int, g: Int, b: Int)] = []
    for y in (raw.height / 3)..<(2 * raw.height / 3) {
        for x in (raw.width / 3)..<(2 * raw.width / 3) {
            let i = (y * raw.width + x) * 4
            pixels.append((Int(raw.pixels[i]), Int(raw.pixels[i + 1]), Int(raw.pixels[i + 2])))
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

// MARK: - Legibility

/// Where the ink block sits, and where the bare surface beside it is read.
///
/// Placed, not found. The test draws the block at a known offset and measures
/// that rectangle, rather than searching the render for dark pixels.
private enum InkPatch {
    static let size = CGSize(width: 120, height: 60)
    /// `contentPadding` is 20, and the block is top-leading inside that.
    static let ink = CGRect(x: 20, y: 20, width: 120, height: 60)
    /// Same rows, clear of the block and clear of the far edge.
    static let bare = CGRect(x: 170, y: 20, width: 120, height: 60)
}

/// A surface carrying one solid block of `.primary`, which is what a user's text
/// resolves to.
@MainActor
private func inkedSurface(
    _ material: SurfaceMaterial,
    lightOffset: Double,
    inkStyle: HierarchicalShapeStyle = .primary
) -> some View {
    Surface(material: material) {
        Rectangle()
            .foregroundStyle(inkStyle)
            .frame(width: InkPatch.size.width, height: InkPatch.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: 353, height: 220)
    .surfaceLightOffset(lightOffset)
    .surfaceTiltSource(.fixed(pitch: -8, roll: 14))
}

/// How far the ink sits below the surface beside it, in luma levels.
///
/// Positive means the ink is darker, which is the readable direction. Near zero
/// means the ink has been washed out by the light crossing it.
@MainActor
private func inkContrast<V: View>(of view: V) async -> Int {
    let raw = await rawPixels(of: view, size: CGSize(width: 353, height: 220))
    guard !raw.pixels.isEmpty else { return 0 }

    func read(_ rect: CGRect) -> Double {
        var sum = 0.0
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                guard x < raw.width, y < raw.height else { continue }
                let i = (y * raw.width + x) * 4
                sum += luminance(
                    (Int(raw.pixels[i]), Int(raw.pixels[i + 1]), Int(raw.pixels[i + 2]))
                )
                count += 1
            }
        }
        return count == 0 ? 0 : sum / Double(count)
    }

    return Int(read(InkPatch.bare) - read(InkPatch.ink))
}

@MainActor
@Suite("What a surface renders")
struct SurfaceRenderTests {
    @Test("The harness draws anything at all")
    func harnessDrawsAnything() async {
        // A broken harness and a broken shader both read back as all black.
        // Without this there is no telling them apart.
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
    /// Any change to the shader, the stock, the lights or a tint moves one of
    /// these, and this says which and by how much. Update them deliberately,
    /// never to make a run go green.
    static let reference: [String: (r: Int, g: Int, b: Int)] = [
        "Gold": (241, 227, 164),
        "Silver": (240, 240, 241),
        "Rose gold": (241, 227, 216),
        "Copper": (240, 210, 185),
        "Brass": (239, 233, 195),
        "Gunmetal": (218, 221, 225),
    ]

    /// How far the ink must sit below the surface beside it, in luma levels, with
    /// the light at its worst position.
    ///
    /// Halfway between two measured points. At full legibility damping the worst
    /// material reads 72; with the damping switched off it falls to 48. 60 sits
    /// clear of both by the same margin, and far above the 8 levels a surface
    /// with no ink on it produces from its own gradient.
    static let minimumInkContrast = 60

    /// Writes the render with the two sampled rectangles drawn on it.
    ///
    /// Keep this. Every other test here reduces the screen to a number, and a
    /// number cannot show that the rectangle was in the wrong place.
    ///
    ///     find ~/Library/Developer/CoreSimulator -name sampled-regions.png
    @Test("Save a picture of the sampled regions")
    func saveSampledRegions() async {
        let size = CGSize(width: 353, height: 220)
        let view = inkedSurface(.gold, lightOffset: -1)

        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.frame = CGRect(origin: .zero, size: size)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.windowScene = scene
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        for _ in 0..<12 { try? await Task.sleep(for: .milliseconds(50)) }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let annotated = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)

            ctx.cgContext.setLineWidth(2)
            ctx.cgContext.setStrokeColor(UIColor.systemRed.cgColor)
            ctx.cgContext.stroke(InkPatch.ink)
            ctx.cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
            ctx.cgContext.stroke(InkPatch.bare)
        }

        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sampled-regions.png")
        try? annotated.pngData()?.write(to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Text stays readable with the light sitting on it")
    func inkStaysReadableUnderTheLight() async {
        // Light at the left edge, which is where the ink block is. Anywhere else
        // the gleam is not crossing the text and the question does not arise.
        for material in SurfaceMaterial.all {
            let contrast = await inkContrast(of: inkedSurface(material, lightOffset: -1))
            #expect(
                contrast >= Self.minimumInkContrast,
                "\(material.name) leaves the ink only \(contrast) levels below the surface"
            )
        }
    }

    @Test("The contrast measure reads near zero with no text present")
    func contrastMeasureHasAFloor() async {
        // The control for the test above. A measure that always returned a
        // healthy number would pass that test forever without reading anything.
        let blank = await inkContrast(of: surface(.gold))
        #expect(blank < 15, "a surface with no text reported \(blank) levels of contrast")
    }

    @Test("Paler text reads as less contrast")
    func palerTextReadsAsLessContrast() async {
        // The second control, in the other direction: the measure must move when
        // the ink changes, not only when the light does.
        let dark = await inkContrast(of: inkedSurface(.gold, lightOffset: 0))
        let pale = await inkContrast(
            of: inkedSurface(.gold, lightOffset: 0, inkStyle: .quaternary)
        )

        #expect(pale < dark, "pale ink \(pale) did not read below dark ink \(dark)")
    }

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
