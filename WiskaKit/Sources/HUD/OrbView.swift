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

/// The Magical Orb: a ball of plasma fire (a Metal shader, `OrbFire.metal`) with a few drifting
/// sparks. Driven by the voice (`VoiceEnergy` and the pitch bands, from the microphone frames the
/// app already has). Redraws at full rate only while something moves; idle it ticks slowly.
struct OrbView: View {
    let model: OrbModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = VoiceEnergy.Clock()
    @State private var bands = BandClock()
    @State private var flames = FlameClock()

    var body: some View {
        let _ = model.revision
        let idle = model.presence.mood() == .idle && model.sampleLevel == nil
        TimelineView(.animation(minimumInterval: idle ? 1.0 / 20 : nil, paused: idle && reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let audio = model.sampleLevel?(t) ?? model.presence.audio
            let energy = clock.advance(to: timeline.date, level: audio.level)
            let shares = bands.advance(to: timeline.date, audio: audio)
            let mood = model.sampleLevel == nil ? model.presence.mood(at: timeline.date) : .listening(command: false)
            let pose = OrbMotion.pose(at: t, mood: mood, energy: energy, reduceMotion: reduceMotion)
            let phase = flames.advance(to: timeline.date, speed: pose.flameSpeed)
            ZStack {
                // A soft glow underneath: the orb never vanishes, even if the shader can't load.
                Canvas { context, size in
                    OrbRenderer.drawGlow(in: &context, size: size, pose: pose, colour: model.colour)
                }
                Rectangle()
                    .fill(.white)
                    .visualEffect { content, proxy in
                        content.colorEffect(OrbRenderer.fire(size: proxy.size, phase: phase, pose: pose,
                                                             bands: shares, colour: model.colour))
                    }
                Canvas { context, size in
                    OrbRenderer.drawSparks(in: &context, size: size, t: t, pose: pose, bands: shares,
                                           colour: model.colour)
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
    static let particleCount = 14

    static func fire(size: CGSize, phase: Double, pose: OrbPose, bands: [CGFloat], colour: Highlight) -> Shader {
        let (outer, inner) = colours(pose, colour)
        return ShaderLibrary.bundle(shaderBundle)[dynamicMember: shaderName](
            .float2(size), .float(Float(phase)), .float(Float(pose.intensity)),
            .float(Float(OrbMotion.fireRadius * pose.coreScale)), .float(Float(pose.ripple)),
            .color(outer), .color(inner), .floatArray(bands.map(Float.init)))
    }

    /// The fire's outer and inner colour: the highlight's two ends, or reds for an error.
    static func colours(_ pose: OrbPose, _ colour: Highlight) -> (outer: Color, inner: Color) {
        pose.isError ? (Color(hex: 0xC2304A), AuroraTheme.danger) : (AuroraTheme.end(colour), AuroraTheme.start(colour))
    }

    /// How much the voice's bands push the edge out at angle `a` (radians, 0 = right, −π/2 = top):
    /// low pitches at the top, high ones at the bottom, mirrored left and right — as the shader does,
    /// softened across neighbouring bands.
    static func bandValue(at a: Double, bands: [CGFloat]) -> CGFloat {
        guard bands.count > 1 else { return 0 }
        let u = (sin(a) + 1) / 2
        let x = u * Double(bands.count - 1)
        func smoothed(_ i: Int) -> CGFloat {
            let at = { bands[max(0, min(bands.count - 1, $0))] }
            return 0.25 * at(i - 1) + 0.5 * at(i) + 0.25 * at(i + 1)
        }
        let i = Int(x.rounded(.down)), f = CGFloat(x - Double(i))
        return smoothed(i) * (1 - f) + smoothed(min(i + 1, bands.count - 1)) * f
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

    /// Embers: sparks that float up off the fire and fade, slowly. While you speak each one
    /// shines with the pitch band where it rose; otherwise they glow softly.
    static func drawSparks(in context: inout GraphicsContext, size: CGSize, t: Double, pose: OrbPose,
                           bands: [CGFloat], colour: Highlight) {
        guard pose.particleOpacity > 0 else { return }
        let half = min(size.width, size.height) / 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let (_, inner) = colours(pose, colour)
        let voiced = bands.contains { $0 > 0.02 }
        for i in 0..<particleCount {
            let seed = Double(i) * 1.618
            // Each ember's life runs 0 → 1 and starts over: rise, sway, fade in and out.
            let rate = 0.12 * Double(pose.particleSpeed) * (0.7 + 0.15 * Double(i % 3))
            let life = (Seed.hash(seed) + t * rate).truncatingRemainder(dividingBy: 1)
            let start = Seed.hash(seed + 0.3) * 2 * .pi
            let origin = CGPoint(x: centre.x + half * 0.4 * CGFloat(cos(start)),
                                 y: centre.y + half * 0.3 * CGFloat(sin(start)))
            let sway = half * 0.05 * CGFloat(sin(t * 0.6 + seed * 2))
            let p = CGPoint(x: origin.x + sway * CGFloat(life), y: origin.y - half * 0.55 * CGFloat(life))
            let shine = voiced ? 0.35 + 0.65 * Double(bandValue(at: start, bands: bands)) : 0.75
            let fade = sin(.pi * life) * shine * Double(pose.particleOpacity)
            let dot = max(0.7, half * 0.012 * (i.isMultiple(of: 3) ? 1.5 : 1)) * CGFloat(1 - 0.4 * life)
            context.fill(circle(p, dot * 2.6), with: .color(inner.opacity(0.3 * fade)))
            context.fill(circle(p, dot), with: .color(Color(red: 1, green: 0.97, blue: 0.9).opacity(fade)))
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
