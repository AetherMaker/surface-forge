<div align="center">

# SurfaceForge

**SwiftUI + Metal surfaces that react to device tilt.**

![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-000000?style=flat-square&logo=apple&logoColor=white)
![No dependencies](https://img.shields.io/badge/dependencies-none-4C566A?style=flat-square)
![MIT](https://img.shields.io/badge/licence-MIT-4C566A?style=flat-square)

<img src="https://github.com/user-attachments/assets/7e474e05-4c14-4081-99f1-6670fbf3b710" width="520" alt="A gold surface catching the light as the phone tilts">

</div>

<br>

The surface above, in full:

```swift
import SurfaceForge

Surface(material: .gold, cornerRadius: 22, contentPadding: 20) {
    VStack(alignment: .leading, spacing: 2) {
        Text("MEMBER SINCE")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
        Text("2019")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)

        Spacer()

        Text("GOLD")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
        Text("4471 0982 3310")
            .font(.system(size: 26, weight: .semibold))
            .monospacedDigit()
    }
}
.frame(width: 353, height: 220)
```

Every line after `Surface` is plain SwiftUI. Size, placement, layout and spacing
are yours; the package only owns the surface and its light.

| Parameter | Default | |
|---|---|---|
| `material` | `.gold` | What the surface is made of. |
| `cornerRadius` | `22` | Continuous, squircle corners. |
| `contentPadding` | `20` | Inset between your content and the surface's edge. |

Your content fills the surface's bounds **first**, and `contentPadding` insets it
after, so `Spacer()` and alignments reach the edges as you would expect.

## Install

**Xcode.** File → Add Package Dependencies, then paste:

```
https://github.com/AetherMaker/surface-forge
```

**Package.swift.**

```swift
.package(url: "https://github.com/AetherMaker/surface-forge", from: "0.1.0")
```

## Materials

`.gold` &nbsp;`.silver` &nbsp;`.roseGold` &nbsp;`.copper` &nbsp;`.brass` &nbsp;`.gunmetal`

```swift
SurfaceMaterial.all          // every built-in, in order. For a picker.
material.name                // "Rose gold"
material.approximateColor    // a flat Color for a swatch, not what the surface looks like

SurfaceMaterial.custom(tint: .init(red: 0.8, green: 0.9, blue: 1), name: "Platinum")
```

**A custom tint should be richer and more saturated than the metal you want.**
The shader multiplies it by your content's own luminance, which both lifts and
desaturates it. Gold is stored as `(1.00, 0.72, 0.22)` and renders near
`(214, 187, 114)`.

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
