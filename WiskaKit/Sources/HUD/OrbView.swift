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
    /// Two tilted rings orbit the sphere; their back halves pass behind it, for depth.
    static let ringTilts: [Double] = [0.45, -0.75]
    /// Lightning flickers to a new shape this many times a second.
    static let boltRate: Double = 9

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

        rings(in: &context, centre: centre, core: core, t: t, pose: pose, colour: end, front: false)

        // Aura: two strands that ripple and twist with the voice, out of step with each other.
        for strand in 0..<2 {
            var aura = Path()
            let phase = Double(strand) * 1.9
            let speed = 1 + Double(pose.ripple) * 9            // louder = faster churn
            for step in 0...96 {
                let a = Double(step) / 96 * 2 * .pi
                let wave = sin(3 * a + t * 2.1 * speed + phase) * 0.5 + sin(5 * a - t * 3.3 * speed) * 0.3
                    + sin(8 * a + t * 5.2 * speed + phase) * 0.2
                let r = core * OrbMotion.auraRadius * (1 + pose.ripple * CGFloat(wave) * (strand == 0 ? 1 : 0.7))
                let p = CGPoint(x: centre.x + r * CGFloat(cos(a)), y: centre.y + r * CGFloat(sin(a)))
                step == 0 ? aura.move(to: p) : aura.addLine(to: p)
            }
            context.stroke(aura, with: .color((strand == 0 ? start : end).opacity((0.25 + 0.5 * pose.glow)
                    * (strand == 0 ? 1 : 0.6))),
                           lineWidth: max(1, core * (strand == 0 ? 0.06 : 0.035)))
        }

        // Core: a lit sphere whose highlight slowly drifts around, like flowing light.
        let drift = reduceMotion ? 0 : t * 0.5
        let light = CGPoint(x: centre.x + core * 0.3 * CGFloat(cos(drift + 2.3)),
                            y: centre.y + core * 0.3 * CGFloat(sin(drift + 2.3)))
        context.fill(circle(centre, core), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.95), start, end]),
            center: light, startRadius: 0, endRadius: core * 1.25))
        context.stroke(circle(centre, core), with: .color(.white.opacity(0.25)), lineWidth: 0.75)

        rings(in: &context, centre: centre, core: core, t: t, pose: pose, colour: start, front: true)

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

        lightning(in: &context, centre: centre, core: core, t: t, pose: pose, colour: start)

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

    /// Tilted rings seen in perspective (flattened ellipses), each carrying a bright bead. Drawn in
    /// two passes: the far halves before the core (dim, hidden by it), the near halves after.
    private static func rings(in context: inout GraphicsContext, centre: CGPoint, core: CGFloat, t: Double,
                              pose: OrbPose, colour: Color, front: Bool) {
        guard pose.ringOpacity > 0 else { return }
        let rx = core * OrbMotion.ringRadius
        for (index, tilt) in ringTilts.enumerated() {
            let ry = rx * CGFloat(0.22 + 0.06 * sin(t * 0.7 + Double(index)))
            let turn = tilt + t * 0.12 * Double(pose.ringSpeed > 0 ? 1 : 0)
            func point(_ theta: Double) -> CGPoint {
                let x = rx * CGFloat(cos(theta)), y = ry * CGFloat(sin(theta))
                return CGPoint(x: centre.x + x * CGFloat(cos(turn)) - y * CGFloat(sin(turn)),
                               y: centre.y + x * CGFloat(sin(turn)) + y * CGFloat(cos(turn)))
            }
            // The near half is θ in 0…π (towards the viewer), the far half π…2π.
            var path = Path()
            let from = front ? 0.0 : Double.pi
            for step in 0...48 {
                let p = point(from + Double.pi * Double(step) / 48)
                step == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            let opacity = Double(pose.ringOpacity) * (front ? 0.85 : 0.35)
            context.stroke(path, with: .color(colour.opacity(opacity)), lineWidth: max(0.8, core * 0.035))
            // The bead travels the ring; it's brighter and bigger on the near side.
            let theta = (t * pose.ringSpeed * (index == 0 ? 1 : -1.3) + Double(index) * 2)
                .truncatingRemainder(dividingBy: 2 * .pi)
            let near = sin(theta) >= 0
            guard near == front else { continue }
            let bead = max(1.2, core * (near ? 0.085 : 0.05))
            let p = point(theta)
            context.fill(circle(p, bead * 2.2), with: .color(colour.opacity(0.25 * opacity)))
            context.fill(circle(p, bead), with: .color(.white.opacity(near ? 0.95 : 0.4)))
        }
    }

    /// Jagged bolts that crackle out from the sphere's edge and flicker to new shapes several times a
    /// second; the louder the voice, the more of them. Each is a blurred coloured stroke under a thin white one.
    private static func lightning(in context: inout GraphicsContext, centre: CGPoint, core: CGFloat, t: Double,
                                  pose: OrbPose, colour: Color) {
        guard pose.boltChance > 0, pose.maxBolts > 0 else { return }
        let flicker = (t * boltRate).rounded(.down)
        for i in 0..<pose.maxBolts {
            let seed = flicker * 7.31 + Double(i) * 3.17
            guard Seed.hash(seed) < pose.boltChance else { continue }
            let angle = Seed.hash(seed + 0.11) * 2 * .pi
            let length = 0.55 + 0.4 * Seed.hash(seed + 0.23)          // reaches 1.55…1.95 core radii
            var bolt = Path()
            let segments = 6
            for s in 0...segments {
                let along = CGFloat(s) / CGFloat(segments)
                let r = core * (1 + CGFloat(length) * along)
                let jitter = s == 0 ? 0 : core * 0.13 * CGFloat(Seed.hash(seed + Double(s) * 0.37) - 0.5) * 2
                let a = angle + Double(along) * 0.25 * (Seed.hash(seed + 0.5) - 0.5)
                let p = CGPoint(x: centre.x + r * CGFloat(cos(a)) - jitter * CGFloat(sin(a)),
                                y: centre.y + r * CGFloat(sin(a)) + jitter * CGFloat(cos(a)))
                s == 0 ? bolt.move(to: p) : bolt.addLine(to: p)
            }
            var glow = context
            glow.addFilter(.blur(radius: max(1, core * 0.08)))
            glow.stroke(bolt, with: .color(colour.opacity(0.9)),
                        style: StrokeStyle(lineWidth: max(1.5, core * 0.1), lineCap: .round, lineJoin: .round))
            context.stroke(bolt, with: .color(.white.opacity(0.9)),
                           style: StrokeStyle(lineWidth: max(0.6, core * 0.025), lineCap: .round, lineJoin: .round))
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
