import Core
import SwiftUI

@MainActor @Observable
final class OrbModel {
    var colour: Highlight = .aurora
    /// Bumped on every new content, so a paused timeline (reduced motion) redraws.
    var revision = 0
    @ObservationIgnored let presence = Presence()
    /// Previews drive the orb with a made-up voice instead of the microphone.
    @ObservationIgnored var sampleLevel: ((Double) -> AudioLevel)?
}

/// The Magical Orb: a ball of plasma fire (a Metal shader, `OrbFire.metal`). Driven by the voice (`VoiceEnergy` and the pitch bands, from the microphone frames the
/// app already has). Redraws at full rate only while something moves; idle it ticks slowly.
struct OrbView: View {
    let model: OrbModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = VoiceEnergy.Clock()
    @State private var bands = BandClock()
    @State private var flames = FlameClock()
    @State private var waves = FlameClock()
    @State private var transition = TransitionClock()

    var body: some View {
        let _ = model.revision
        let idle = model.presence.mood() == .idle && model.sampleLevel == nil
        TimelineView(.animation(minimumInterval: idle ? 1.0 / 30 : nil, paused: idle && reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let audio = model.sampleLevel?(t) ?? model.presence.audio
            let energy = clock.advance(to: timeline.date, level: audio.level)
            let shares = bands.advance(to: timeline.date, audio: audio)
            let mood = model.sampleLevel == nil ? model.presence.mood(at: timeline.date) : .listening(command: false)
            let pose = transition.advance(to: timeline.date, mood: mood,
                                          target: OrbMotion.pose(at: t, mood: mood, energy: energy,
                                                                 reduceMotion: reduceMotion))
            let phase = flames.advance(to: timeline.date, speed: pose.flameSpeed)
            let wavePhase = waves.advance(to: timeline.date, speed: pose.waveSpeed)
            ZStack {
                // A soft glow underneath: the orb never vanishes, even if the shader can't load.
                Canvas { context, size in
                    OrbRenderer.drawGlow(in: &context, size: size, pose: pose, colour: model.colour)
                }
                Canvas { context, size in
                    OrbRenderer.drawWaves(in: &context, size: size, phase: wavePhase, pose: pose, colour: model.colour)
                }
                Rectangle()
                    .fill(.white)
                    .visualEffect { content, proxy in
                        content.colorEffect(OrbRenderer.fire(size: proxy.size, phase: phase, pose: pose,
                                                             bands: shares, colour: model.colour))
                    }
            }
            .compositingGroup()
        }
    }
}

/// The flames' own clock: advances at the pose's speed, so changing speed never jumps the fire.
final class FlameClock {
    private(set) var phase: Double = 0
    private var last: Date?

    func advance(to now: Date, speed: Double) -> Double {
        let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 20) } ?? 0
        last = now
        phase += dt * speed
        return phase
    }
}

/// Steps `OrbTransition` with the real frame time.
final class TransitionClock {
    private var transition = OrbTransition()
    private var last: Date?

    func advance(to now: Date, mood: Presence.Mood, target: OrbPose) -> OrbPose {
        let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 20) } ?? 0
        last = now
        return transition.pose(for: target, mood: mood, dt: dt)
    }
}

/// The voice's pitch bands, smoothed more gently than the waveform's bars, for the orb's shape.
final class BandClock {
    private var motion: WaveformMotion = {
        var motion = WaveformMotion()
        motion.attackTime = 0.06
        motion.releaseTime = 0.35
        return motion
    }()
    private var last: Date?

    func advance(to now: Date, audio: AudioLevel) -> [CGFloat] {
        let dt = last.map { min(now.timeIntervalSince($0), 1.0 / 20) } ?? 0
        last = now
        motion.step(audio, dt: dt)
        return motion.shares
    }
}

enum OrbRenderer {
    static let shaderName = "orbFire"
    /// The bundle holding the compiled shader (the HUD module's resources).
    static let shaderBundle = Bundle.module

    static func fire(size: CGSize, phase: Double, pose: OrbPose, bands: [CGFloat], colour: Highlight) -> Shader {
        let (outer, inner) = colours(pose, colour)
        return ShaderLibrary.bundle(shaderBundle)[dynamicMember: shaderName](
            .float2(size), .float(Float(phase)), .float(Float(pose.intensity)),
            .float(Float(OrbMotion.fireRadius * pose.coreScale)), .float(Float(pose.ripple)),
            .color(outer), .color(inner), .floatArray(bands.map(Float.init)))
    }

    /// The fire's outer and inner colour: the highlight's two ends, blending to reds for an error.
    static func colours(_ pose: OrbPose, _ colour: Highlight) -> (outer: Color, inner: Color) {
        let red = Double(pose.redness)
        guard red > 0 else { return (AuroraTheme.end(colour), AuroraTheme.start(colour)) }
        return (AuroraTheme.end(colour).mix(with: Color(hex: 0xC2304A), by: red),
                AuroraTheme.start(colour).mix(with: AuroraTheme.danger, by: red))
    }

    static func drawGlow(in context: inout GraphicsContext, size: CGSize, pose: OrbPose, colour: Highlight) {
        let half = min(size.width, size.height) / 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = half * 0.95
        let (outer, inner) = colours(pose, colour)
        context.fill(circle(centre, radius), with: .radialGradient(
            Gradient(stops: [.init(color: inner.opacity(0.5 * pose.glow), location: 0),
                             .init(color: outer.opacity(0.3 * pose.glow), location: 0.35),
                             .init(color: outer.opacity(0), location: 1)]),
            center: centre, startRadius: 0, endRadius: radius))
    }

    /// Wavy borders floating round the fire: soft glowing rings that undulate out of step with
    /// each other, slowly when idle and bigger and quicker with the voice.
    static func drawWaves(in context: inout GraphicsContext, size: CGSize, phase: Double, pose: OrbPose,
                          colour: Highlight) {
        let half = min(size.width, size.height) / 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let fire = half * OrbMotion.fireRadius * pose.coreScale
        let (outer, inner) = colours(pose, colour)
        for index in 0..<pose.waveCount {
            let base = fire * OrbMotion.waveRadius(index)
            let k = Double(index)
            var path = Path()
            for step in 0...120 {
                let a = Double(step) / 120 * 2 * .pi
                let wave = 0.6 * sin(3 * a + phase * (1 + 0.3 * k) + k * 2.1)
                    + 0.4 * sin(5 * a - phase * (1.3 - 0.2 * k) + k)
                let r = base * (1 + pose.waveAmplitude * CGFloat(wave))
                let p = CGPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y + r * CGFloat(sin(a)))
                step == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            let tint = index.isMultiple(of: 2) ? inner : outer
            let strength = Double(pose.waveOpacity) * (1 - 0.22 * k)
            var glow = context
            glow.addFilter(.blur(radius: max(1, half * 0.025)))
            glow.stroke(path, with: .color(tint.opacity(0.6 * strength)), lineWidth: max(1.5, half * 0.03))
            context.stroke(path, with: .color(tint.opacity(strength)), lineWidth: max(0.8, half * 0.01))
        }
    }

    private static func circle(_ centre: CGPoint, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
    }
}

/// The orb with a made-up voice, for Settings ▸ Appearance. Never touches the microphone.
public struct OrbPreview: View {
    let colour: Highlight
    let side: CGFloat
    @State private var model = OrbModel()

    public init(colour: Highlight, side: CGFloat) {
        self.colour = colour
        self.side = side
    }

    public var body: some View {
        OrbView(model: model)
            .frame(width: side, height: side)
            .onAppear {
                model.sampleLevel = { t in SampleVoice.level(at: t) }
                model.colour = colour
                model.revision += 1
            }
            .onChange(of: colour) { model.colour = colour }
    }
}
