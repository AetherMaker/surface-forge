import simd

/// The light directions the shader needs, and the arithmetic behind them.
///
/// No state and no hardware. Everything here is a pure function of a device
/// attitude and a surface's proportion, which is what makes the whole lighting
/// model testable without a device.
///
/// Quaternions stay on this side. The shader receives two resolved unit vectors.
nonisolated enum SurfaceShading {
    // MARK: - The lights

    // There are two, and they point in different directions. Conflating them is
    // the fastest way to end up with no visible highlight at all, so both carry
    // their derivation.

    /// The **diffuse** light, and the frame device tilt rotates against. Up, to
    /// the right, and tipped toward the viewer.
    static let canonicalAxis = simd_normalize(SIMD3<Float>(0.45, 0.25, 0.86))

    /// The **specular** light at rest, aimed at the mirror of the eye rather
    /// than at the lamp.
    ///
    /// That distinction is the difference between a gleam and nothing. On a flat
    /// surface `canonicalAxis` sits about 44 degrees off the mirror direction
    /// everywhere, so there is nowhere the half vector can meet the normal.
    ///
    /// Solved, not chosen. For a directional light `L` over a flat surface with
    /// a virtual eye at `(0, ey, ez)`, the specular peak lands at
    ///
    ///     p.x = ez * L.x / L.z
    ///     p.y = ey + ez * L.y / L.z
    ///
    /// Putting the resting gleam at `p = (-0.40, 0)`, which is 30% in from the
    /// leading edge and vertically centred, gives the components below.
    static let neutralKeyDirection: SIMD3<Float> = {
        let eye = virtualEye(halfHeight: referenceHalfHeight)
        let restingGleam = SIMD2<Double>(-0.40, 0)
        let lz = 0.941
        let lx = restingGleam.x * lz / eye.z
        let ly = (restingGleam.y - eye.y) * lz / eye.z

        return simd_normalize(SIMD3<Float>(Float(lx), Float(ly), Float(lz)))
    }()

    /// The diffuse axis at rest.
    ///
    /// Spelled once, because the freeze in ``lights(keyDirection:diffuseAxis:gleam:)``
    /// is only sound if every caller agrees where rest is.
    static let restingDiffuseAxis = lifted(canonicalAxis, minimumZ: diffuseMinimumZ)

    /// The proportion `neutralKeyDirection` was solved against, height over
    /// width.
    ///
    /// A surface of a different shape still lights correctly, because
    /// ``virtualEye(halfHeight:)`` re-solves per surface. What drifts is only
    /// *where* the resting gleam sits: further from this ratio, the further the
    /// highlight strays from the 30%-in mark it was placed at. Noticeable on a
    /// square or a tall surface, invisible near this one.
    static let referenceHalfHeight = 220.0 / 353.0

    /// Radians of panel rotation per radian of device tilt.
    ///
    /// The reflection vector varies about 30 degrees edge to edge, and the
    /// specular point travels `ez * sec^2` of a half-width per radian of light
    /// rotation, so the gleam crosses the whole surface in roughly 29 degrees of
    /// light. Against a 0.9 motion influence, 1.25 carries it clean off one edge
    /// and back over a 15-degree wrist tilt.
    static let keyReflectionTiltGain: Float = 1.25

    /// The specular panel may never sink below the surface, or the coat goes
    /// black on a hard tilt.
    static let keyReflectionMinimumZ: Float = 0.20

    /// The diffuse frame's floor. Gentler duty, harder clamp: this one only has
    /// to keep the diffuse term from collapsing.
    static let diffuseMinimumZ: Float = 0.45

    // MARK: - The virtual eye

    /// The shading eye in surface half-widths, solved from the `dot(N, V)`
    /// envelope rather than picked.
    ///
    /// Solved here rather than per fragment. `halfHeight` is uniform across the
    /// surface, so the shader was re-solving one quadratic per pixel for a value
    /// that never varies, and the compiler cannot hoist it because it cannot
    /// know the uniform.
    static func virtualEye(halfHeight h: Double) -> (y: Double, z: Double) {
        let maximumNdotV = 0.980
        let minimumNdotV = 0.873

        let e = (1 / (maximumNdotV * maximumNdotV) - 1).squareRoot()
        let c = 1 / (minimumNdotV * minimumNdotV) - 1

        let a = c - e * e
        let b = 4 * h * e
        let k = 1 + 4 * h * h
        let z = (b + (b * b + 4 * a * k).squareRoot()) / (2 * a)

        return (y: h + e * z, z: z)
    }

    // MARK: - Tilt

    /// The specular panel's direction under the current device tilt: the
    /// canonical-to-device rotation applied to the neutral panel, at
    /// ``keyReflectionTiltGain``.
    ///
    /// Returns exactly the neutral at the neutral hold.
    static func keyDirection(deviceAxis: SIMD3<Float>) -> SIMD3<Float> {
        let axis = lifted(deviceAxis, minimumZ: diffuseMinimumZ)
        let rotationAxis = simd_cross(canonicalAxis, axis)
        let rotationAxisLength = simd_length(rotationAxis)

        guard rotationAxisLength > 1e-5, rotationAxisLength.isFinite else {
            return neutralKeyDirection
        }

        let angle = acos(min(max(simd_dot(canonicalAxis, axis), -1), 1))
        let rotation = simd_quatf(
            angle: angle * keyReflectionTiltGain,
            axis: rotationAxis / rotationAxisLength
        )

        return lifted(
            normalized(rotation.act(neutralKeyDirection), fallback: neutralKeyDirection),
            minimumZ: keyReflectionMinimumZ
        )
    }

    // MARK: - Fading the reflection out

    /// The pair of directions to hand the shader at a partial gleam.
    ///
    /// At 1, the live pair unchanged. At 0, exactly the rest pair, and that is
    /// the point rather than a nicety: it makes the material's output
    /// independent of the live pose the moment the reflection is out, so the
    /// light can be put back where the design wants it with nothing on screen
    /// moving.
    ///
    /// Gleam alone cannot buy that. It gates the window, the coat's specular and
    /// the sheen, but not the substrate's ambient and diffuse terms, which are
    /// the surface's entire body colour. An axis snapping home from a hard tilt
    /// would still step that by about a tenth. Interpolating the directions
    /// closes it on the CPU, with no extra uniform and no branch per fragment.
    ///
    /// A normalized lerp rather than a slerp: both inputs are lifted, so they
    /// share a hemisphere and can never be antipodal, and across this range the
    /// two paths differ by well under a degree.
    static func lights(
        keyDirection: SIMD3<Float>,
        diffuseAxis: SIMD3<Float>,
        gleam: Double
    ) -> (key: SIMD3<Float>, diffuse: SIMD3<Float>) {
        let amount = Float(min(max(gleam, 0), 1))

        // Bit-exact passthrough at full gleam. Live tracking is the common case
        // and must not pick up a rounding error it did not have.
        guard amount < 1 else { return (keyDirection, diffuseAxis) }

        return (
            key: normalized(
                simd_mix(neutralKeyDirection, keyDirection, SIMD3<Float>(repeating: amount)),
                fallback: neutralKeyDirection
            ),
            diffuse: normalized(
                simd_mix(restingDiffuseAxis, diffuseAxis, SIMD3<Float>(repeating: amount)),
                fallback: restingDiffuseAxis
            )
        )
    }

    // MARK: - Helpers

    /// Clamps an axis's elevation and renormalizes its planar part, so a hostile
    /// or hard-tilted direction can never sink below the surface, or through it.
    static func lifted(_ proposedAxis: SIMD3<Float>, minimumZ: Float) -> SIMD3<Float> {
        let axis = normalized(proposedAxis, fallback: canonicalAxis)
        let z = min(max(axis.z, minimumZ), 1)

        // The fallback has to be normalized too. The canonical axis's planar
        // part is only 0.513 long, so handing it over raw would rescale the
        // whole direction and return a non-unit axis, which the shader dots
        // against. That changes the specular's intensity rather than its aim,
        // and it is reached whenever the axis is exactly edge-on.
        let planar = normalized(
            SIMD2<Float>(axis.x, axis.y),
            fallback: normalized(
                SIMD2<Float>(canonicalAxis.x, canonicalAxis.y),
                fallback: SIMD2<Float>(1, 0)
            )
        )

        return SIMD3<Float>(planar * (max(1 - z * z, 0)).squareRoot(), z)
    }

    static func normalized(
        _ value: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared.isFinite, lengthSquared > 1e-8 else { return fallback }
        return value * rsqrt(lengthSquared)
    }

    static func normalized(
        _ value: SIMD2<Float>,
        fallback: SIMD2<Float>
    ) -> SIMD2<Float> {
        let lengthSquared = simd_length_squared(value)
        guard lengthSquared.isFinite, lengthSquared > 1e-8 else { return fallback }
        return value * rsqrt(lengthSquared)
    }
}
