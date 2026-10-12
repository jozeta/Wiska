import Core
import SwiftUI

@MainActor @Observable
final class OrbModel {
    var colour: Highlight = .aurora
    /// Bumped on every new content, so a paused timeline (reduced motion) redraws.
    var revision = 0
    @ObservationIgnored let presence = Presence()
    /// Previews drive the orb with a made-up voice instead of the microphone.
    @ObservationIgnored var sampleLevel: ((Double) -> Float)?
}

/// The Magical Orb: a luminous core in a soft glow, a rippling aura and a few drifting sparks.
/// Driven by the voice energy (`VoiceEnergy`, from the microphone frames the app already has).
/// Redraws at full rate only while something moves; idle it ticks slowly.
struct OrbView: View {
    let model: OrbModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = VoiceEnergy.Clock()

    var body: some View {
        let _ = model.revision
        let idle = model.presence.mood() == .idle && model.sampleLevel == nil
        TimelineView(.animation(minimumInterval: idle ? 1.0 / 20 : nil, paused: idle && reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = model.sampleLevel?(t) ?? model.presence.level
            let energy = clock.advance(to: timeline.date, level: level)
            let mood = model.sampleLevel == nil ? model.presence.mood(at: timeline.date) : .listening(command: false)
            let pose = OrbMotion.pose(at: t, mood: mood, energy: energy, reduceMotion: reduceMotion)
            Canvas { context, size in
                OrbRenderer.draw(in: &context, size: size, t: t, pose: pose, colour: model.colour,
                                 reduceMotion: reduceMotion)
            }
        }
    }
}

enum OrbRenderer {
    static let particleCount = 12

    static func draw(in context: inout GraphicsContext, size: CGSize, t: Double, pose: OrbPose,
                     colour: Highlight, reduceMotion: Bool) {
        let side = min(size.width, size.height)
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let core = side * OrbMotion.coreShare * pose.coreScale
        let start = pose.isError ? AuroraTheme.danger : AuroraTheme.start(colour)
        let end = pose.isError ? Color(hex: 0xC2304A) : AuroraTheme.end(colour)
        let outer = OrbMotion.outerRadius(pose, side: side)

        // Glow: soft light fading to nothing at the edge, so the window corners stay clear.
        context.fill(circle(centre, outer), with: .radialGradient(
            Gradient(stops: [.init(color: start.opacity(0.55 * pose.glow), location: 0),
                             .init(color: end.opacity(0.32 * pose.glow), location: 0.45),
                             .init(color: end.opacity(0), location: 1)]),
            center: centre, startRadius: core * 0.5, endRadius: outer))

        // Aura: a ring that ripples with the voice.
        var aura = Path()
        let auraRadius = core * 1.32
        for step in 0...72 {
            let a = Double(step) / 72 * 2 * .pi
            let wobble = pose.ripple * CGFloat(sin(3 * a + t * 2.1) * 0.6 + sin(5 * a - t * 3.3) * 0.4)
            let r = auraRadius * (1 + wobble)
            let p = CGPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y + r * CGFloat(sin(a)))
            step == 0 ? aura.move(to: p) : aura.addLine(to: p)
        }
        context.stroke(aura, with: .color(start.opacity(0.25 + 0.45 * pose.glow)), lineWidth: max(1, core * 0.06))

        // Core: a lit sphere whose highlight slowly drifts around, like flowing light.
        let drift = reduceMotion ? 0 : t * 0.5
        let light = CGPoint(x: centre.x + core * 0.3 * CGFloat(cos(drift + 2.3)),
                            y: centre.y + core * 0.3 * CGFloat(sin(drift + 2.3)))
        context.fill(circle(centre, core), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.95), start, end]),
            center: light, startRadius: 0, endRadius: core * 1.25))
        context.stroke(circle(centre, core), with: .color(.white.opacity(0.25)), lineWidth: 0.75)

        // Processing: two arcs chasing round the core.
        if pose.spinOpacity > 0 {
            let spin = reduceMotion ? 0 : t * 3
            for half in 0..<2 {
                var arc = Path()
                let from = Angle(radians: spin + Double(half) * .pi)
                arc.addArc(center: centre, radius: core * 1.55, startAngle: from,
                           endAngle: from + .degrees(95), clockwise: false)
                context.stroke(arc, with: .color(start.opacity(pose.spinOpacity)),
                               style: StrokeStyle(lineWidth: max(1.5, core * 0.09), lineCap: .round))
            }
        }

        // Sparks: a few points orbiting inside the glow, livelier with the voice.
        guard pose.particleOpacity > 0 else { return }
        for i in 0..<particleCount {
            let seed = Double(i) * 1.618
            let angle = seed * 2 * .pi + t * (0.25 + 0.15 * Double(i % 3)) * Double(pose.particleSpeed)
            let band = 0.5 + 0.5 * sin(t * 0.6 + seed * 3)
            let radius = core * (1.4 + 0.65 * CGFloat(band))
            let twinkle = 0.55 + 0.45 * sin(t * (2 + Double(i % 4)) + seed)
            let p = CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
            let dot = max(0.8, core * 0.045)
            context.fill(circle(p, dot), with: .color((i.isMultiple(of: 2) ? start : .white)
                .opacity(Double(pose.particleOpacity) * twinkle)))
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
                model.sampleLevel = { t in Float(max(0, 0.32 + 0.22 * sin(t * 1.7) + 0.08 * sin(t * 6.1))) }
                model.colour = colour
                model.revision += 1
            }
            .onChange(of: colour) { model.colour = colour }
    }
}
