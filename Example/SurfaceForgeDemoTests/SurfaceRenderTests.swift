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

/// How sharply the highlight falls off, measured across the surface.
///
/// The reference table reads the middle of the card, which is the highlight's
/// peak, and at a peak a tight highlight and a broad one are both at full
/// brightness. Sharpness only shows in the *falloff*, so it needs its own
/// reading.
///
/// Returns the drop in luma from the brightest column to the dimmest, sampling
/// nine columns across the width. A hard highlight falls away fast and gives a
/// large number; a matte one barely falls at all.
@MainActor
private func highlightFalloff<V: View>(of view: V) async -> Int {
    let raw = await rawPixels(of: view, size: CGSize(width: 353, height: 220))
    guard !raw.pixels.isEmpty else { return 0 }

    var columns: [Double] = []
    for column in 0..<9 {
        // Inset from both ends, clear of the rounded corners and the rim.
        let x0 = 30 + (raw.width - 60) * column / 9
        let x1 = 30 + (raw.width - 60) * (column + 1) / 9
        var sum = 0.0
        var count = 0
        for y in (raw.height / 3)..<(2 * raw.height / 3) {
            for x in x0..<x1 {
                let i = (y * raw.width + x) * 4
                sum += luminance(
                    (Int(raw.pixels[i]), Int(raw.pixels[i + 1]), Int(raw.pixels[i + 2]))
                )
                count += 1
            }
        }
        columns.append(count == 0 ? 0 : sum / Double(count))
    }

    guard let high = columns.max(), let low = columns.min() else { return 0 }
    return Int(high - low)
}

/// How far the bright band spreads across the surface and up it, in pixels.
///
/// Weighted by how far each pixel sits above the surface's own mean, so the band
/// is measured and the dim surround is not. A round highlight spreads about
/// equally both ways; a stretched one spreads further along the axis it stretches.
@MainActor
private func highlightSpread<V: View>(of view: V) async -> (across: Double, up: Double) {
    let raw = await rawPixels(of: view, size: CGSize(width: 353, height: 220))
    guard !raw.pixels.isEmpty else { return (0, 0) }

    var luma = [Double](repeating: 0, count: raw.width * raw.height)
    for i in 0..<(raw.width * raw.height) {
        let p = i * 4
        luma[i] = luminance(
            (Int(raw.pixels[p]), Int(raw.pixels[p + 1]), Int(raw.pixels[p + 2]))
        )
    }

    let mean = luma.reduce(0, +) / Double(luma.count)
    // Only what is brighter than average carries the band. Squared, so the core
    // counts for more than the shoulder and the measure follows the peak rather
    // than the threshold.
    var weightSum = 0.0, cx = 0.0, cy = 0.0
    for y in 0..<raw.height {
        for x in 0..<raw.width {
            let w = max(luma[y * raw.width + x] - mean, 0)
            let w2 = w * w
            weightSum += w2
            cx += w2 * Double(x)
            cy += w2 * Double(y)
        }
    }
    guard weightSum > 0 else { return (0, 0) }
    cx /= weightSum
    cy /= weightSum

    var vx = 0.0, vy = 0.0
    for y in 0..<raw.height {
        for x in 0..<raw.width {
            let w = max(luma[y * raw.width + x] - mean, 0)
            let w2 = w * w
            vx += w2 * (Double(x) - cx) * (Double(x) - cx)
            vy += w2 * (Double(y) - cy) * (Double(y) - cy)
        }
    }
    return ((vx / weightSum).squareRoot(), (vy / weightSum).squareRoot())
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
private func surface(
    _ material: SurfaceMaterial,
    gleam: Double = 1,
    roll: Double = 14
) -> some View {
    Surface(material: material) { Color.clear }
        .frame(width: 353, height: 220)
        .surfaceGleam(gleam)
        .surfaceTiltSource(.fixed(pitch: -8, roll: roll))
}

/// Every pixel, not the middle band.
///
/// The band is where the gleam sits, which is the right window for reading a
/// material's colour. The grain rides the window lobe, which covers the whole
/// surface, so a test that only reads the middle third can miss it entirely.
@MainActor
private func wholePlate<V: View>(of view: V) async -> [(r: Int, g: Int, b: Int)] {
    let raw = await rawPixels(of: view, size: CGSize(width: 353, height: 220))
    guard !raw.pixels.isEmpty else { return [] }

    var pixels: [(r: Int, g: Int, b: Int)] = []
    pixels.reserveCapacity(raw.width * raw.height)
    for i in stride(from: 0, to: raw.width * raw.height * 4, by: 4) {
        pixels.append((Int(raw.pixels[i]), Int(raw.pixels[i + 1]), Int(raw.pixels[i + 2])))
    }
    return pixels
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

    @Test("A matte material spreads its band wider than a polished one")
    func matteSpreadsWiderThanPolished() async {
        // The whole point of per-material tightness. Gunmetal is the widest at 18
        // and gold the tightest that still has room to show it at 70, so this
        // pair is the largest gap the six produce: 20 against 26.
        //
        // An ordering rather than six pinned numbers, because several of the
        // materials sit one or two levels apart and a test that tight would be
        // noise. This one fails as soon as the tightness values are flattened.
        let matte = await highlightFalloff(of: surface(.gunmetal))
        let polished = await highlightFalloff(of: surface(.gold))

        #expect(
            polished - matte >= 4,
            "gold falls off by \(polished) and gunmetal by \(matte), too close to tell apart"
        )
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

    @Test("Text stays readable on a brushed surface too")
    func inkStaysReadableWhenBrushed() async {
        // Brushing reshapes the gleam that crosses the text, so the legibility
        // floor has to be met again rather than inherited. Both grains, because
        // one stands the band up across the text and the other lays it along.
        //
        // Same worst case as the polished test: the light at the left edge, which
        // is where the ink block is.
        for material in SurfaceMaterial.all {
            for degrees in [0.0, 90.0] {
                let brushed = material.brushed(1, angle: .degrees(degrees))
                let contrast = await inkContrast(of: inkedSurface(brushed, lightOffset: -1))

                #expect(
                    contrast >= Self.minimumInkContrast,
                    """
                    \(material.name) brushed at \(Int(degrees))° leaves the ink only \
                    \(contrast) levels below the surface
                    """
                )
            }
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

    // MARK: - Brushing

    @Test("Brushing at zero renders exactly what polished renders")
    func zeroBrushingIsExactlyPolished() async {
        // The guarantee the whole brushing change rests on, asked of the GPU
        // instead of argued on paper. Every material is pinned to a reference
        // colour, so an exponent that drifts by one float quietly recolours
        // every surface already shipped.
        //
        // The grain angle is what makes this a real comparison. A material and
        // its own `brushed(0)` carry identical uniforms, so rendering both would
        // only prove the GPU is deterministic: no change to the exponent could
        // ever fail it, because it would move both sides equally. Aiming the
        // grain elsewhere holds the amount at zero while changing what the
        // shader is handed, so the renders can only match if zero amount
        // genuinely discards the grain.
        //
        // The hostile angles are the test rather than decoration. Zero brushing is
        // exact because `mix(1, stretch, 0)` returns an exact 1.0, which is true
        // for a finite stretch and false for a NaN one, and only a non-finite
        // angle or amount can produce one. Those two cases are the whole failure
        // mode the guarantee has.
        //
        // Byte-identical, not within a tolerance. Both renders happen on this
        // machine in this run from the same fixed pose, so anything other than
        // equality is the brushed path's own arithmetic.
        let poses: [(label: String, roll: Double, gleam: Double)] = [
            ("rest", 0, 1), ("tilted", 14, 1), ("fading", 14, 0.45),
        ]
        let angles: [Angle] = [
            .degrees(37), .degrees(116), .degrees(249.5),
            .degrees(.nan), .degrees(.infinity), .degrees(1e300),
        ]

        for material in SurfaceMaterial.all {
            for pose in poses {
                let polished = await wholePlate(
                    of: surface(material, gleam: pose.gleam, roll: pose.roll)
                )
                #expect(!polished.isEmpty, "\(material.name) rendered nothing")

                for angle in angles {
                    let unbrushed = await wholePlate(
                        of: surface(
                            material.brushed(0, angle: angle),
                            gleam: pose.gleam,
                            roll: pose.roll
                        )
                    )
                    let differing = zip(polished, unbrushed).filter { $0.0 != $0.1 }.count
                    #expect(
                        differing == 0,
                        """
                        \(material.name) at \(pose.label), grain \(angle.degrees)°: \
                        zero brushing moved \(differing) of \(polished.count) pixels
                        """
                    )
                }

                // The other half of the same guarantee.
                let nanAmount = await wholePlate(
                    of: surface(material.brushed(.nan), gleam: pose.gleam, roll: pose.roll)
                )
                #expect(
                    zip(polished, nanAmount).filter { $0.0 != $0.1 }.count == 0,
                    "\(material.name) at \(pose.label): a NaN amount is not polished"
                )
            }
        }
    }

    @Test("Brushing at full strength does reach the surface")
    func fullBrushingReachesTheSurface() async {
        // The control for the test above, which would pass just as happily if the
        // grain never reached the shader at all.
        //
        // A quarter of the plate, not a thousand pixels. Through the sheen alone
        // this was 3108 to 5844 pixels and never more than 2 levels; with the
        // window brushed too it is about half of them and up to 12 levels. A bar
        // the sheen can clear on its own cannot tell that the window has come
        // loose, which is the failure worth catching.
        for material in SurfaceMaterial.all {
            let polished = await wholePlate(of: surface(material))
            let brushed = await wholePlate(of: surface(material.brushed(1)))

            let differing = zip(polished, brushed).filter { $0.0 != $0.1 }.count
            #expect(
                differing > polished.count / 4,
                "\(material.name): full brushing moved only \(differing) of \(polished.count) pixels"
            )
        }
    }

    @Test("The highlight stretches across the grain, not along it")
    func brushingStretchesAcrossTheGrain() async {
        // What brushing is for. Every other brushing test here says it does no
        // harm; this one says it does the thing.
        //
        // A groove scatters light across itself, so a brush running left to right
        // gives a highlight standing up, and one running top to bottom gives a
        // highlight lying flat. Compares the two grains against each other rather
        // than against pinned numbers, because the surface's own bow already
        // biases the band toward the vertical and that bias is not what is under
        // test.
        //
        // Measured, up over across: the bow alone gives 1.36 to 1.46, brushing
        // left to right takes it to 1.83 to 2.16, and brushing top to bottom flips
        // it to 0.58 to 0.61. About a 3.6-fold swing in aspect between the two
        // grains.
        for material in SurfaceMaterial.all {
            let horizontalBrush = await highlightSpread(
                of: surface(material.brushed(1, angle: .zero))
            )
            let verticalBrush = await highlightSpread(
                of: surface(material.brushed(1, angle: .degrees(90)))
            )

            let standing = horizontalBrush.up / max(horizontalBrush.across, 0.001)
            let lying = verticalBrush.up / max(verticalBrush.across, 0.001)

            #expect(
                standing > lying * 1.2,
                """
                \(material.name): brushing left-to-right gave an up/across ratio of \
                \(standing), brushing top-to-bottom gave \(lying). The grain is not \
                turning the highlight.
                """
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
