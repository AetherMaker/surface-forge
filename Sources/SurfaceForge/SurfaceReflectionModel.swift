import Observation
import SwiftUI
import simd

/// Turns device attitude into the two light directions the shader wants, plus
/// the small 3D tilt the surface itself carries.
///
/// One of these per surface. The hardware behind it is shared, see
/// ``SurfaceSharedMotion``.
@MainActor
@Observable
final class SurfaceReflectionModel {
    // MARK: Feel

    /// 0.65 read as a permanent 35% haircut on every tilt angle, and the
    /// material never felt coupled to the hand. 0.9 keeps a whisper of
    /// stabilization while the axis genuinely follows the device.
    static let deviceMotionInfluence: Float = 0.9

    /// How long the axis takes to hand over from the resting direction to the
    /// live one, so picking the phone up does not snap the gleam.
    static let influenceRampDuration: TimeInterval = 0.20

    /// Expressed as a time constant rather than as a per-sample blend, so the
    /// response survives any sample rate and the filter cannot silently change
    /// character when the update interval is touched.
    ///
    /// 93.4 ms. Its predecessor at 0.22 s put a quarter second of lag between
    /// hand and gleam, which was the single biggest reason the material read as
    /// detached.
    static let filterTimeConstant: Float = 0.0934

    /// How quickly a held posture becomes the new level, once the device is
    /// actually still.
    ///
    /// Only this short because it is gated. Relaxing unconditionally chased the
    /// device mid-tilt and cancelled part of the motion it was reporting, so it
    /// had to run at 1.8 s to stay out of the way, and at 1.8 s the settle read
    /// as nothing happening.
    static let restRelaxTimeConstant: Float = 0.30

    /// Angular speed, in radians per second, that counts as fully moving.
    ///
    /// 0.55 puts an ordinary deliberate tilt into saturation while leaving a
    /// hand at rest below the deadband. Higher values sit above the speeds
    /// people actually tilt a phone at, which lets the resting reference keep
    /// relaxing through a gesture and eat it.
    static let referenceAngularSpeed: Float = 0.55

    /// Asymmetric on purpose. The surface must register movement the instant it
    /// starts, but must not decide you have stopped the moment you pause
    /// mid-gesture. The slow release is also what gives the return its beat.
    static let activationAttack: Float = 0.08
    static let activationRelease: Float = 0.25

    /// Radians of counter-rotation per radian of deviation from rest.
    ///
    /// Well under the light's own 1.25, so the gleam leads and the surface
    /// follows. Light is fast, mass is slow.
    ///
    /// Applied to the deviation from a slowly adapting rest pose rather than to
    /// absolute attitude, so it governs how hard the surface reacts to movement,
    /// not how far it leans when you hold still.
    static func tiltGain(reduceMotion: Bool) -> Float {
        reduceMotion ? 0 : 0.60
    }

    /// Where the counter-rotation asymptotes. 9 degrees.
    static func tiltCeiling(reduceMotion: Bool) -> Float {
        reduceMotion ? 0 : 9 * .pi / 180
    }

    // MARK: Published

    private(set) var keyDirection = SurfaceShading.neutralKeyDirection
    private(set) var diffuseAxis = SurfaceShading.restingDiffuseAxis

    /// For `rotation3DEffect`. Radians, with the axis already in SwiftUI's
    /// screen convention.
    private(set) var tiltAngle: Double = 0
    private(set) var tiltAxis = SIMD2<Double>(0, 0)

    // MARK: State

    /// Built on first use, not in `init`.
    ///
    /// `State.init(wrappedValue:)` takes a plain value rather than an
    /// autoclosure, so `@State private var model = SurfaceReflectionModel()` runs this
    /// initializer on every construction of the view that declares it and
    /// SwiftUI discards all but the first. Nothing the source owns is needed
    /// before `start()`, so nothing is built before then.
    private var source: any SurfaceAttitudeSource {
        if let builtSource { return builtSource }

        let source = injectedSource ?? tiltSource.makeAttitudeSource()
        source.sampleHandler = { [weak self] sample in
            self?.consume(sample)
        }
        source.failureHandler = { [weak self] in
            self?.handleFailure()
        }

        builtSource = source
        return source
    }

    /// A computed property over an optional rather than `lazy`, so the stop
    /// paths can ask whether a source exists without creating one to ask.
    @ObservationIgnored
    private var builtSource: (any SurfaceAttitudeSource)?

    @ObservationIgnored
    private var tiltSource: SurfaceTiltSource

    /// Held rather than adopted, so injection stays eager-free too. A test's
    /// double is no reason to wire handlers before the model is used.
    @ObservationIgnored
    private var injectedSource: (any SurfaceAttitudeSource)?

    private var reduceMotion = false
    private var isActive = false

    private var neutralOrientation: simd_quatf?
    private var neutralTimestamp: TimeInterval?
    private var lastSampleTimestamp: TimeInterval?
    private var filteredAxis = SurfaceShading.canonicalAxis
    private var filteredPlanar = SIMD2<Float>(0, 0)
    /// The adapting level the surface's tilt is measured against.
    private var restingPlanar = SIMD2<Float>(0, 0)
    private var previousPlanar = SIMD2<Float>(0, 0)
    /// 0 while the device is still, 1 while it is being turned.
    private var activation: Float = 0

    init(tiltSource: SurfaceTiltSource = .deviceMotion) {
        self.tiltSource = tiltSource
    }

    /// Drives the model from a source of the caller's choosing, for tests.
    init(source: any SurfaceAttitudeSource) {
        tiltSource = .deviceMotion
        injectedSource = source
    }

    // MARK: Lifecycle

    /// Starts or stops sampling, and only that.
    ///
    /// Driven by the view from `scenePhase` and `onAppear`/`onDisappear`. Motion
    /// sampling must not run while the surface is off screen or the app is
    /// backgrounded, because it keeps sampling and spending power regardless.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        active ? start() : stopSampling()
    }

    func setReduceMotion(_ enabled: Bool) {
        guard enabled != reduceMotion else { return }
        reduceMotion = enabled

        if enabled {
            stopSampling()
            resetToRest()
        } else if isActive {
            start()
        }
    }

    /// Swaps what drives the reflection, for when the environment value changes.
    func setTiltSource(_ newSource: SurfaceTiltSource) {
        guard newSource != tiltSource else { return }
        tiltSource = newSource

        builtSource?.stop()
        builtSource = nil
        resetToRest()

        if isActive { start() }
    }

    /// A source that was never built cannot be sampling, so asking for one in
    /// order to stop it would only undo the deferral above.
    private func stopSampling() {
        builtSource?.stop()
    }

    private func start() {
        guard !reduceMotion else {
            resetToRest()
            return
        }

        // Clearing the neutral means the first sample after a return from
        // background re-levels the surface in the hand actually holding it,
        // rather than against an attitude captured ten minutes ago.
        clearFilters()
        source.start()
    }

    private func handleFailure() {
        // A jump, and accepted. Motion that fails mid-session is not a designed
        // state, and going matte forever would be worse than a step.
        stopSampling()
        resetToRest()
    }

    /// Everything the filters carry between samples. Touches nothing the shader
    /// can see.
    private func clearFilters() {
        neutralOrientation = nil
        neutralTimestamp = nil
        lastSampleTimestamp = nil
        filteredAxis = SurfaceShading.canonicalAxis
        filteredPlanar = .zero
        restingPlanar = .zero
        previousPlanar = .zero
        activation = 0
    }

    /// Puts the light back where the design wants it.
    ///
    /// The two directions are `float3` shader uniforms and SwiftUI cannot
    /// interpolate them, so every call here is a teleport.
    /// ``SurfaceShading/lights(keyDirection:diffuseAxis:gleam:)`` is what makes
    /// it a harmless one, by rendering the material blind to both directions
    /// once the reflection is out.
    private func parkLight() {
        keyDirection = SurfaceShading.neutralKeyDirection
        diffuseAxis = SurfaceShading.restingDiffuseAxis
        tiltAngle = 0
        // `tiltAxis` deliberately not cleared, see `updateTilt`.
    }

    private func resetToRest() {
        clearFilters()
        parkLight()
    }

    // MARK: Sampling

    private func consume(_ sample: SurfaceAttitudeSample) {
        guard !reduceMotion else { return }
        guard isFinite(sample.orientation), sample.timestamp.isFinite else {
            resetToRest()
            return
        }

        // The first live sample defines level. Whatever attitude the phone is in
        // when the surface appears becomes the rest pose, so the gleam starts
        // where it was designed to sit rather than wherever the hand happens to
        // be.
        //
        // A deterministic sample is the exception, and has to be: adopting it as
        // the neutral would make the relative rotation identity and the light
        // would never move. Anchoring it to identity makes the sample an
        // absolute angle, which is the whole point of asking for one.
        if neutralOrientation == nil {
            neutralOrientation = sample.isDeterministic
                ? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
                : sample.orientation
            neutralTimestamp = sample.timestamp

            guard sample.isDeterministic else {
                lastSampleTimestamp = sample.timestamp
                return
            }
        }

        guard let neutral = neutralOrientation else { return }
        guard sample.timestamp > (lastSampleTimestamp ?? -.greatestFiniteMagnitude) else {
            return
        }

        let relative = sample.orientation * neutral.inverse

        // The reflection axis is an external light expressed in the device's own
        // frame, so it counter-rotates as the device rotates. That inverse is
        // the material's whole physical claim: the surface is glued to the
        // phone, the light stays in the room.
        let deviceAxis = SurfaceShading.normalized(
            relative.inverse.act(SurfaceShading.canonicalAxis),
            fallback: SurfaceShading.canonicalAxis
        )

        let deltaTime = Float(
            max(sample.timestamp - (lastSampleTimestamp ?? sample.timestamp), 1.0 / 240.0)
        )
        let blend = sample.isDeterministic
            ? 1
            : 1 - exp(-deltaTime / Self.filterTimeConstant)

        filteredAxis = guardedBlend(from: filteredAxis, to: deviceAxis, amount: blend)

        let ramp: Float
        if sample.isDeterministic {
            ramp = 1
        } else {
            let elapsed = max(sample.timestamp - (neutralTimestamp ?? sample.timestamp), 0)
            ramp = min(max(Float(elapsed / Self.influenceRampDuration), 0), 1)
        }

        let effective = guardedBlend(
            from: SurfaceShading.canonicalAxis,
            to: filteredAxis,
            amount: Self.deviceMotionInfluence * ramp
        )

        diffuseAxis = SurfaceShading.lifted(
            effective,
            minimumZ: SurfaceShading.diffuseMinimumZ
        )
        keyDirection = SurfaceShading.keyDirection(deviceAxis: effective)

        // Note the asymmetry with the light above, which stays anchored to the
        // fixed neutral. A reflection depends on where the light actually is, so
        // the gleam must not drift back to a rest pose. Only the surface, which
        // is an object that settles, does.
        updateTilt(relative: relative, blend: blend, deltaTime: deltaTime)

        lastSampleTimestamp = sample.timestamp
    }

    // MARK: The surface's own tilt

    private func updateTilt(relative: simd_quatf, blend: Float, deltaTime: Float) {
        // The counter-rotation as a rotation vector, the quaternion log map.
        //
        // Working in the log map is what lets the z component be dropped
        // cleanly. Zeroing the z of an axis-and-angle pair would keep the full
        // angle and turn a pure in-plane twist into a full-magnitude tip. Here,
        // dropping z removes exactly the twist and nothing else.
        let rotation = Self.rotationVector(relative.inverse)

        // Only the in-plane axes survive. A rotation about z is the phone
        // spinning in its own plane, and the surface is printed on that plane,
        // so it spins with it and must not counter-rotate. Doing so reads as the
        // surface sliding around its own centre.
        let planar = SIMD2<Float>(rotation.x, rotation.y)
        filteredPlanar += (planar - filteredPlanar) * blend

        updateActivation(
            angularSpeed: simd_length(planar - previousPlanar) / deltaTime,
            deltaTime: deltaTime
        )
        previousPlanar = planar

        // The surface settles back to flat wherever you hold still.
        //
        // Measuring tilt against a neutral captured when the surface appeared
        // meant that pose, usually a hand at some reading angle, was the only
        // one that read as level. Set the phone on a desk and it sat visibly
        // tilted. Anchoring to gravity only moves the problem: desk-flat becomes
        // level but holding the phone upright to read then sits permanently at
        // the ceiling. No single fixed reference makes both postures level.
        //
        // So the reference adapts, but only while the device is still. That gate
        // is the trick. An ungated reference chases you mid-gesture and cancels
        // part of the motion it is supposed to report, which is why the tilt read
        // as weak. Frozen during movement, the surface gets the full gain, and
        // the moment you stop, the reference catches up and it returns to flat.
        //
        // Cubed, so the gate is a switch rather than a dimmer. A linear
        // stillness leaves the reference running at 78% through a real gesture,
        // most of the way to having no gate at all. Cubing collapses that to 5%
        // and pushes the effective time constant past six seconds. At true rest
        // the term is 1 and the quick return is untouched.
        let stillness = pow(1 - activation, 3)
        let restingBlend = (1 - exp(-deltaTime / Self.restRelaxTimeConstant)) * stillness
        restingPlanar += (filteredPlanar - restingPlanar) * restingBlend

        let deviation = filteredPlanar - restingPlanar
        let magnitude = simd_length(deviation)

        // The angle goes to zero, the axis is left alone. `rotation3DEffect`
        // interpolates its angle but not its axis, so clearing the axis in the
        // same update collapses the residual lean instantly about a degenerate
        // (0, 0, 0) rather than letting it spring flat about the axis it had. At
        // angle 0 a stale axis is the identity transform and costs nothing.
        guard magnitude > 1e-6 else {
            tiltAngle = 0
            return
        }

        let gain = Self.tiltGain(reduceMotion: reduceMotion)
        let ceiling = Self.tiltCeiling(reduceMotion: reduceMotion)

        guard ceiling > 1e-6 else {
            tiltAngle = 0
            return
        }

        // `tanh`, not `min`. Its derivative at zero is exactly `gain`, so small
        // tilts stay linear and honest, and the response asymptotes at the
        // ceiling with no corner. A hard clamp puts a visible kink in the motion
        // the instant the wrist crosses the saturation angle: the surface stops
        // dead mid-gesture.
        tiltAngle = Double(ceiling * tanh(magnitude * gain / ceiling))

        // Core Motion's device frame is +x right, +y toward the top of the
        // screen, +z out of the glass. `rotation3DEffect`'s axis is +x right, +y
        // down, +z out. Only y flips.
        tiltAxis = SIMD2<Double>(
            Double(deviation.x / magnitude),
            Double(-deviation.y / magnitude)
        )
    }

    /// How much the device is being turned right now, 0...1.
    ///
    /// This is the signal that tells the resting reference when it is allowed to
    /// move. Without it the reference and the gesture fight each other.
    private func updateActivation(angularSpeed: Float, deltaTime: Float) {
        var target = min(max(angularSpeed / Self.referenceAngularSpeed, 0), 1)

        // A deadband with hysteresis. Sensor noise never quite reaches zero, and
        // without this the reference would sit permanently half frozen on a
        // device lying untouched on a desk, which is exactly the case the whole
        // mechanism exists to serve.
        if activation <= 0.015, target < 0.025 {
            target = 0
        } else if target < 0.015 {
            target = 0
        }

        let timeConstant = target > activation
            ? Self.activationAttack
            : Self.activationRelease
        activation += (target - activation) * (1 - exp(-deltaTime / timeConstant))
    }

    /// The quaternion log map's axis-angle vector.
    ///
    /// `atan2` rather than `2 * asin`: exact past 90 degrees, where `asin` folds
    /// back on itself. The shortest-arc branch matters because a quaternion and
    /// its negation are the same rotation but their log maps differ by a half
    /// turn, and without it the surface snaps through 180 degrees at the wrap.
    nonisolated static func rotationVector(_ quaternion: simd_quatf) -> SIMD3<Float> {
        let imaginary = quaternion.imag
        let length = simd_length(imaginary)
        guard length > 1e-6 else { return .zero }

        var angle = 2 * atan2(length, quaternion.real)
        if angle > .pi { angle -= 2 * .pi }

        return imaginary * (angle / length)
    }

    // MARK: Helpers

    private func guardedBlend(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        amount: Float
    ) -> SIMD3<Float> {
        let a = SurfaceShading.normalized(start, fallback: SurfaceShading.canonicalAxis)
        let b = SurfaceShading.normalized(end, fallback: SurfaceShading.canonicalAxis)

        // Nearly antipodal axes have no well-defined interpolation. Bail to the
        // rest direction rather than spinning through an arbitrary one.
        guard simd_dot(a, b) > -0.95 else { return SurfaceShading.canonicalAxis }

        return SurfaceShading.normalized(
            simd_mix(a, b, SIMD3<Float>(repeating: amount)),
            fallback: SurfaceShading.canonicalAxis
        )
    }

    private func isFinite(_ quaternion: simd_quatf) -> Bool {
        let vector = quaternion.vector
        return simd_length_squared(vector) > 1e-8
            && vector.x.isFinite
            && vector.y.isFinite
            && vector.z.isFinite
            && vector.w.isFinite
    }
}
