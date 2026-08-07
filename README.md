# SurfaceForge

A SwiftUI surface that behaves like a physical object: a metallic material whose
reflections respond as you move and tilt the device.

**Not a card library. Not a template gallery. A surface with a material on it.**

> **Status: v1 in progress.** The API below is the target, not what ships today.
> Nothing here is stable yet.

## Install

```swift
.package(url: "https://github.com/AetherMaker/surface-forge", from: "1.0.0")
```

## Use

```swift
import SurfaceForge

Surface(material: .gold, cornerRadius: 22, contentPadding: 20) {
    VStack(alignment: .leading, spacing: 6) {
        Text("MEMBER").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text("A21 4471").monospacedDigit()
    }
}
.frame(width: 353, height: 220)
```

Size, placement, layout and spacing come from plain SwiftUI. The content
container fills the surface, then `contentPadding` is applied inside it, so
`Spacer()` and alignments behave normally.

## Content is read as luminance

Every material in v1 is metallic, and metallic materials keep the lightness of
your content and discard its colour. A blue element appears as the material's
own colour at that element's brightness.

Use SwiftUI's `.primary`, `.secondary` and `.tertiary`. They keep their relative
hierarchy after desaturation, so there is no SurfaceForge colour API to learn.

Full-colour content lands in v2. If you need a coloured logo on the surface
today, this package cannot do it yet.

## Materials

`.gold` `.silver` `.roseGold` `.copper` `.brass` `.gunmetal` `.custom(tint:)`

## Tilt

```swift
.surfaceTiltSource(.deviceMotion)          // follows the device
.surfaceTiltSource(.fixed(pitch: -15, roll: 20))
```

Previews and the Simulator have no motion data, so `.deviceMotion` leaves the
surface at rest there. Use `.fixed` to see the reflection, and for repeatable
screenshots and tests.

```swift
.surfaceGleam(0)   // flat matte, no pose-dependent reflection
.surfaceGleam(1)   // full
```

## Requirements

iOS 17. No dependencies. No bundled assets.

## Licence

MIT
