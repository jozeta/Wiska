import Core
import SwiftUI

@MainActor @Observable
final class ClippyModel {
    var highlight: Highlight = .aurora
    /// Bumped on every new mood, so a paused timeline (reduced motion) redraws.
    var revision = 0
    /// The words heard so far; kept while the dictation is transcribed, cleared when it ends.
    var text = ""
    /// What the bubble says above the words.
    var status = ""
    var isError = false
    /// The bubble sits above Clippy (tail down) or below it (tail up).
    var bubbleAbove = true
    var tailX: CGFloat = ClippyController.bubbleSize.width / 2
    @ObservationIgnored let presence = Presence()
    /// Where the pupils should point to follow the mouse (nil = not following).
    @ObservationIgnored var pointerLook: (() -> CGPoint?)?
    /// Following the pointer keeps the timeline running while idle (even with Reduce Motion).
    var followsPointer = false
    /// Previews drive Clippy with a made-up voice instead of the microphone.
    @ObservationIgnored var sampleLevel: ((Double) -> Float)?
}

/// The character: an original drawing of a bent-wire paperclip with big eyes and heavy brows,
/// posed every frame by `ClippyMotion`. Runs at full rate only while dictating.
struct ClippyView: View {
    let model: ClippyModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = VoiceEnergy.Clock()

    var body: some View {
        let _ = model.revision
        let idle = model.presence.mood() == .idle && model.sampleLevel == nil
        TimelineView(.animation(minimumInterval: idle ? 1.0 / 24 : nil,
                                paused: idle && reduceMotion && !model.followsPointer)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let level = model.sampleLevel?(t) ?? model.presence.level
            let energy = clock.advance(to: timeline.date, level: level)
            let mood = model.sampleLevel == nil ? model.presence.mood(at: timeline.date) : .listening(command: false)
            let pose = ClippyMotion.pose(at: t, mood: mood, energy: energy, reduceMotion: reduceMotion,
                                         pointer: model.followsPointer ? model.pointerLook?() : nil)
            Canvas { context, size in
                ClippyRenderer.draw(in: &context, size: size, pose: pose)
            }
        }
    }
}

enum ClippyRenderer {
    /// The drawing's own units; the clip is centred and scaled into whatever size it gets.
    static let design = CGSize(width: 60, height: 100)
    /// Room above the clip for its hops.
    static let headroom: CGFloat = 12

    static let wireLight = Color(hex: 0xF3F5F8)
    static let wireDark = Color(hex: 0x9AA4B1)
    static let outline = Color(hex: 0x262A31)

    /// The bent wire: an inner U, up over a rounded top, then a wider outer U.
    static let wire: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 24, y: 30))
        path.addLine(to: CGPoint(x: 24, y: 72))
        arc(&path, centre: CGPoint(x: 31, y: 72), radius: 7, from: 180, to: 0)
        path.addLine(to: CGPoint(x: 38, y: 20))
        arc(&path, centre: CGPoint(x: 28, y: 20), radius: 10, from: 0, to: -180)
        path.addLine(to: CGPoint(x: 18, y: 82))
        arc(&path, centre: CGPoint(x: 30, y: 82), radius: 12, from: 180, to: 0)
        path.addLine(to: CGPoint(x: 42, y: 36))
        return path
    }()

    /// Traces an arc point by point (y grows downward; angles in degrees, swept from → to).
    private static func arc(_ path: inout Path, centre: CGPoint, radius: CGFloat, from: Double, to: Double) {
        for step in 1...16 {
            let a = (from + (to - from) * Double(step) / 16) * .pi / 180
            path.addLine(to: CGPoint(x: centre.x + radius * CGFloat(cos(a)), y: centre.y + radius * CGFloat(sin(a))))
        }
    }

    static func draw(in context: inout GraphicsContext, size: CGSize, pose: ClippyPose) {
        let scale = min(size.width / design.width, (size.height - headroom) / design.height)
        // Pivot on the bottom of the clip: lean, hop and flex from there.
        let base = CGPoint(x: size.width / 2, y: size.height - 2)
        if pose.sleeping { snore(in: context, at: CGPoint(x: base.x + 30 * scale, y: base.y - 40 * scale), scale: scale) }
        context.translateBy(x: base.x + pose.shiftX * scale, y: base.y + pose.bounce * scale)
        context.rotate(by: .degrees(pose.tilt))
        context.scaleBy(x: scale * (2 - pose.squash), y: scale * pose.squash)
        // Cartwheels and turns happen around the clip's middle.
        context.translateBy(x: 0, y: -46)
        context.rotate(by: .degrees(pose.spin))
        context.scaleBy(x: pose.turn, y: 1)
        context.translateBy(x: -design.width / 2, y: -50)

        let round = StrokeStyle(lineWidth: 5.4, lineCap: .round, lineJoin: .round)
        context.stroke(wire, with: .color(outline.opacity(0.75)), style: round)
        context.stroke(wire, with: .linearGradient(Gradient(colors: [wireLight, wireDark]),
                                                   startPoint: CGPoint(x: 16, y: 0), endPoint: CGPoint(x: 44, y: 100)),
                       style: StrokeStyle(lineWidth: 3.6, lineCap: .round, lineJoin: .round))

        guard pose.turn > 0.15 else { return }       // turned away: just the wire
        for (index, x) in [CGFloat(21), 37].enumerated() {
            eye(in: &context, centre: CGPoint(x: x, y: 33), pose: pose)
            brow(in: &context, eyeX: x, inward: index == 0 ? 1 : -1, pose: pose)
        }
    }

    /// A few "z"s floating up while he naps.
    private static func snore(in context: GraphicsContext, at origin: CGPoint, scale: CGFloat) {
        let t = Date().timeIntervalSinceReferenceDate
        for i in 0..<3 {
            let life = (t * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let size = (7 + 4 * CGFloat(i)) * scale * 0.6
            let p = CGPoint(x: origin.x + CGFloat(life) * 10 * scale, y: origin.y - CGFloat(life) * 26 * scale)
            context.draw(Text("z").font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white.opacity(sin(.pi * life) * 0.9)), at: p)
        }
    }

    private static func eye(in context: inout GraphicsContext, centre: CGPoint, pose: ClippyPose) {
        let width: CGFloat = 11, height: CGFloat = 13
        if pose.happy {
            var smile = Path()
            smile.move(to: CGPoint(x: centre.x - 4.5, y: centre.y + 2))
            smile.addQuadCurve(to: CGPoint(x: centre.x + 4.5, y: centre.y + 2),
                               control: CGPoint(x: centre.x, y: centre.y - 5))
            context.stroke(smile, with: .color(outline), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            return
        }
        let open = max(0.08, pose.eyeOpen)
        let rect = CGRect(x: centre.x - width / 2, y: centre.y - height * open / 2, width: width, height: height * open)
        context.fill(Path(ellipseIn: rect), with: .color(.white))
        context.stroke(Path(ellipseIn: rect), with: .color(outline), lineWidth: 1.3)
        guard open > 0.3 else { return }
        let pupil = CGPoint(x: centre.x + pose.look.x * 2.4, y: centre.y + pose.look.y * 3 * open)
        context.fill(Path(ellipseIn: CGRect(x: pupil.x - 2.6, y: pupil.y - 2.6, width: 5.2, height: 5.2)),
                     with: .color(outline))
        context.fill(Path(ellipseIn: CGRect(x: pupil.x - 1.6, y: pupil.y - 2, width: 1.5, height: 1.5)),
                     with: .color(.white))
    }

    /// `inward`: +1 when the brow's inner end is to its right (the left eye).
    private static func brow(in context: inout GraphicsContext, eyeX: CGFloat, inward: CGFloat, pose: ClippyPose) {
        let lift = pose.brow * 3.2
        let knit = min(0, pose.brow) * -3          // a frown pulls the inner ends down
        let inner = CGPoint(x: eyeX + inward * 5, y: 24 - lift + knit)
        let outer = CGPoint(x: eyeX - inward * 5, y: 24 - lift - knit * 0.3)
        var path = Path()
        path.move(to: outer)
        path.addQuadCurve(to: inner, control: CGPoint(x: eyeX, y: min(inner.y, outer.y) - 2.2))
        context.stroke(path, with: .color(outline), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
    }
}

/// The speech bubble: the live preview under a short status line, in the classic pale-yellow
/// assistant style. Long text keeps its newest lines in view (older ones fade out at the top).
struct ClippyBubbleView: View {
    let model: ClippyModel
    static let maxTextHeight: CGFloat = 108
    /// Room at the sides (and the far edge) for the bubble's shadow.
    static let sideInset: CGFloat = 6

    /// The bubble shape is inset from the panel, so the tail's x moves by the same amount.
    static func shapeTailX(panelTailX: CGFloat) -> CGFloat { panelTailX - sideInset }

    var body: some View {
        let shape = BubbleShape(tailX: Self.shapeTailX(panelTailX: model.tailX), tailDown: model.bubbleAbove)
        VStack(alignment: .leading, spacing: 4) {
            Text(model.status)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.isError ? Color(hex: 0xB3261E) : AuroraTheme.color(model.highlight, at: 0.6)
                    .mix(with: .black, by: 0.35))
            if !model.text.isEmpty {
                Text(model.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x1C1F24))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: Self.maxTextHeight, alignment: .bottom)
                    .clipped()
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)],
                                       startPoint: .top, endPoint: .bottom)
                    }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .padding(model.bubbleAbove ? .bottom : .top, BubbleShape.tailHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Color(hex: 0xFFFFE1)).shadow(color: .black.opacity(0.3), radius: 4, y: 2))
        .overlay(shape.stroke(Color(hex: 0x262A31), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.bubbleAbove ? .bottom : .top)
        .padding(.horizontal, Self.sideInset).padding(model.bubbleAbove ? .top : .bottom, Self.sideInset)
    }
}

/// A rounded rectangle with a little tail pointing at Clippy.
struct BubbleShape: Shape {
    var tailX: CGFloat
    var tailDown: Bool
    static let tailHeight: CGFloat = 10
    static let radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let body = tailDown ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - Self.tailHeight)
            : CGRect(x: rect.minX, y: rect.minY + Self.tailHeight, width: rect.width, height: rect.height - Self.tailHeight)
        var path = Path(roundedRect: body, cornerRadius: Self.radius)
        path.addPath(Self.tail(at: tailX, in: rect, down: tailDown))
        return path
    }

    static let tailHalfWidth: CGFloat = 7

    /// A triangle whose tip is at `x` on the edge facing Clippy, its base even on both sides.
    static func tail(at x: CGFloat, in rect: CGRect, down: Bool) -> Path {
        let x = min(max(x, rect.minX + radius + tailHalfWidth), rect.maxX - radius - tailHalfWidth)
        let base = down ? rect.maxY - tailHeight - 0.5 : rect.minY + tailHeight + 0.5
        var tail = Path()
        tail.move(to: CGPoint(x: x - tailHalfWidth, y: base))
        tail.addLine(to: CGPoint(x: x, y: down ? rect.maxY : rect.minY))
        tail.addLine(to: CGPoint(x: x + tailHalfWidth, y: base))
        tail.closeSubpath()
        return tail
    }
}

/// Clippy with a made-up voice and a sample bubble, for Settings ▸ Appearance.
/// Never touches the microphone.
public struct ClippyPreview: View {
    let highlight: Highlight
    var showsBubble: Bool
    var height: CGFloat
    @State private var model = ClippyModel()

    public init(highlight: Highlight, showsBubble: Bool = true, height: CGFloat = 94) {
        self.highlight = highlight
        self.showsBubble = showsBubble
        self.height = height
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showsBubble {
                ClippyBubbleView(model: model).frame(width: 190).fixedSize(horizontal: false, vertical: true)
            }
            ClippyView(model: model).frame(width: height, height: height)
        }
        .onAppear {
            model.sampleLevel = { t in Float(max(0, 0.3 + 0.25 * sin(t * 1.9) + 0.1 * sin(t * 7.3))) }
            model.status = "Listening…"
            model.text = "It looks like you're writing a letter."
            model.tailX = 95 + ClippyBubbleView.sideInset
            model.highlight = highlight
            model.revision += 1
        }
        .onChange(of: highlight) { model.highlight = highlight }
    }
}
