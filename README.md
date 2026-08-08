<div align="center">

# SurfaceForge

**SwiftUI surfaces that react to device tilt, shaded in Metal.**

![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white)
![No dependencies](https://img.shields.io/badge/dependencies-none-4C566A?style=flat-square)
![MIT](https://img.shields.io/badge/licence-MIT-4C566A?style=flat-square)

</div>

https://github.com/user-attachments/assets/ef373ca7-d45a-4819-9e08-88a90d639ce7

<br>

```swift
import SurfaceForge

Surface(material: .gold) {
    VStack(alignment: .leading) {
        Text("MEMBER").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text("4471 0982 3310").monospacedDigit()
    }
}
.frame(width: 353, height: 220)
```

That is the whole API for a working surface. Size, placement, layout and spacing
come from plain SwiftUI.

## Install

```swift
.package(url: "https://github.com/AetherMaker/surface-forge", from: "1.0.0")
```

## Materials

`.gold` &nbsp;`.silver` &nbsp;`.roseGold` &nbsp;`.copper` &nbsp;`.brass` &nbsp;`.gunmetal` &nbsp;`.custom(tint:)`

## Light

```swift
.surfaceLightOffset(0)     // centred. -1 is the left edge, +1 the right
.surfaceGleam(1)           // 0 is flat matte, 1 is the full reflection
```

Both move **all** of a surface's lighting together, so the shading and the
highlight never disagree about which side the light is on.

They propagate through the environment, and that is deliberate: two surfaces on
screen are in the same room, so one lit from the left beside one lit from the
right is a bug. Set either once, high in a tree.

## Tilt

```swift
.surfaceTiltSource(.deviceMotion)                 // follows the device
.surfaceTiltSource(.fixed(pitch: -15, roll: 20))  // a held angle
```

Previews and the Simulator have no motion data, so `.deviceMotion` holds the
resting reflection there. `.fixed` is how you see the material move without
hardware, and how you get a repeatable screenshot or test.

Every surface on screen reads the device **once**, through one shared source
that starts with the first and stops with the last. A `ScrollView` of them costs
what one costs.

## Content is read as luminance

Every material here is metallic, and metal keeps the lightness of your content
and discards its colour. A blue element appears as the material's own colour at
blue's brightness.

Use `.primary`, `.secondary` and `.tertiary`. They keep their relative hierarchy
through the material, so there is no colour API to learn.

**Full-colour content is not supported yet.** If you need a coloured logo on the
surface, this cannot do it today.

<details>
<summary><b>Why a shader, and not a gradient</b></summary>

<br>

A moving gradient gets most of the way there and breaks in four places.

**A gradient's band is always the same shape.** Here the highlight is a specular
lobe over a normal that varies per pixel across a cylindrical bow and three
plane waves at irrational angles, so the band compresses and shimmers as it
crosses.

**A view cannot read what is behind it.** The material multiplies your content's
own luminance, so a light surface turns metal while dark text stays dark.
Legibility falls out of the model instead of being hand-authored twice.

**The gleam crosses your text.** Behind the content it is occluded and reads as
printed metallic art; in front it erases the text. Here it passes over and is
damped by how dark each pixel is.

**No SwiftUI primitive has a view vector**, so a gradient's edges behave exactly
like its middle. Fresnel needs one.

</details>

<details>
<summary><b>Demo app</b></summary>

<br>

`Example/SurfaceForgeDemo.xcodeproj` is one surface with a control for every
knob. It runs on a Simulator with no Apple account and no signing setup.

</details>

## Requirements

iOS 17. No dependencies. No bundled assets.

## Licence

MIT
