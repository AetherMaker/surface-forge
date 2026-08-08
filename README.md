# SurfaceForge

SwiftUI surfaces that react to device tilt, shaded in Metal.

https://github.com/user-attachments/assets/ef373ca7-d45a-4819-9e08-88a90d639ce7

> **New.** Everything below is built and tested, but nothing has been tagged yet,
> so treat the API as unstable until 1.0.

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

Every surface on screen reads the device once, through one shared motion source
that starts with the first surface and stops with the last. A `ScrollView` of them
costs the same battery as one.

## Light

```swift
.surfaceLightOffset(0)      // centred, the default
.surfaceLightOffset(-0.6)   // toward the left edge
.surfaceLightOffset(1)      // at the right edge
```

Where the light sits, given as where its resting highlight lands. `-1` is the
left edge and `+1` the right.

This moves both of the surface's lights together, the one that shades it and the
one it reflects, so they keep agreeing about which side the light is on.

```swift
.surfaceGleam(0)   // flat matte, no pose-dependent reflection
.surfaceGleam(1)   // full
```

Both propagate through the environment, and that is deliberate rather than
convenient: two surfaces on screen are in the same room, so one lit from the left
beside one lit from the right is a bug. Set either once high in a tree and every
surface below agrees.

## Demo

`Example/SurfaceForgeDemo.xcodeproj` is one surface with a control for every knob.
It builds and runs on a Simulator with no Apple account and no signing setup.

## Requirements

iOS 17. No dependencies. No bundled assets.

## Licence

MIT
