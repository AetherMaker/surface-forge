import SwiftUI
import Testing

@testable import SurfaceForge

@Suite("Brushing")
struct SurfaceBrushingTests {
    @Test("Brushing never hands the shader a value that is not a number")
    func brushingStaysFinite() {
        // The polished guarantee rests on one identity: `mix(1, stretch, 0)`
        // returns an exact 1.0. That holds for a finite stretch and fails for a
        // NaN one, and the only way a NaN reaches the shader is through these two
        // parameters, so this is the whole failure mode.
        //
        // Cheap on purpose. The render test proves the same thing on a GPU and
        // takes a simulator and two minutes; this fails in a second.
        for degrees in [Double.nan, .infinity, -.infinity, 1e300, -1e300, 37] {
            let material = SurfaceMaterial.gold.finish(.brushed(angle: .degrees(degrees)))

            #expect(material.highlightStretch == 1, "brushed is not fully brushed")
            #expect(
                material.grainAngle.isFinite,
                "angle \(degrees)° produced \(material.grainAngle)"
            )
        }
    }

    @Test("A whole turn of the grain is the same grain")
    func grainWrapsRatherThanClamps() {
        // An axis, not a heading. Clamping would have pinned every angle past one
        // turn to the same edge value and quietly killed the grain there.
        let base = SurfaceMaterial.gold.finish(.brushed(angle: .degrees(30)))
        let turned = SurfaceMaterial.gold.finish(.brushed(angle: .degrees(390)))

        #expect(
            abs(base.grainAngle - turned.grainAngle) < 1e-5,
            "30° gave \(base.grainAngle) and 390° gave \(turned.grainAngle)"
        )
    }

    @Test("Brushing at zero is the polished material exactly")
    func zeroBrushingIsTheSameMaterial() {
        // The CPU half of the exactness claim. If this is not exactly zero the
        // shader's `mix` has nothing to discard and the guarantee is gone before
        // the GPU sees it.
        for material in SurfaceMaterial.all {
            #expect(SurfaceMaterial.gold.finish(.polished).highlightStretch == 0)
            #expect(material.finish(.polished).highlightStretch == 0)
        }
    }
}
