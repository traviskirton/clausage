import SwiftUI

/// Pull to refresh on the Usage screen (design handoff: iOS Pull to Refresh). The indicator sits in the gap the pull opens
/// between the navigation bar and the header, centered in it, so it never covers content. Crossing the threshold only
/// changes the indicator and plays a haptic; the refresh starts when the finger lifts.
///
/// Observable on its own, so the per-frame `pull` only redraws the indicator, not the screen.
@Observable @MainActor final class PullState {
    enum Phase { case idle, pulling, armed, updating, updated, failed }

    static let threshold: CGFloat = 88
    static let holdHeight: CGFloat = 72
    /// Space between the bar and the header at rest.
    static let restGap: CGFloat = 14
    /// 26pt tally, 6pt gap, 14pt label line.
    static let indicatorHeight: CGFloat = 46

    /// Live overscroll, ≥ 0.
    private(set) var pull: CGFloat = 0
    private(set) var phase: Phase = .idle
    /// The content's top margin while updating: 72, animated with the spring, then back to 0.
    var hold: CGFloat = 0
    /// The Ember slash, 0 → 1, on success.
    var slash: CGFloat = 0
    /// The finger is on the scroll view.
    var interacting = false
    /// A fetch finished while the finger was down; its numbers go in on release.
    var pendingApply = false

    var busy: Bool { phase == .updating || phase == .updated || phase == .failed }

    func track(_ p: CGFloat) {
        pull = max(0, p)
        guard !busy else { return }
        phase = pull >= Self.threshold ? .armed : (pull > 0 ? .pulling : .idle)
    }

    func set(_ p: Phase) { phase = p }

    /// After the spring back: no strokes, no slash.
    func reset() {
        slash = 0
        phase = pull >= Self.threshold ? .armed : (pull > 0 ? .pulling : .idle)
    }

    /// Strokes on while pulling: 1 at 30, 2 at 50, 3 at 70, 4 at the threshold.
    var strokes: Int {
        switch phase {
        case .idle, .pulling: return pull >= 70 ? 3 : pull >= 50 ? 2 : pull >= 30 ? 1 : 0
        case .armed, .updating, .updated, .failed: return 4
        }
    }
}

struct PullIndicator: View {
    let state: PullState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // While updating the content is held 72pt down; keep the indicator centered in that gap as it springs back.
        let gap = max(state.pull, state.hold)
        VStack(spacing: 6) {
            if state.phase == .updating && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.18)) { ctx in
                    let step = Int(ctx.date.timeIntervalSinceReferenceDate / 0.18) % 4
                    PullTally(strokes: step + 1, failed: false, slash: 0)
                }
            } else {
                PullTally(strokes: state.strokes, failed: state.phase == .failed, slash: state.slash)
            }
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(labelColor)
                .lineLimit(1).frame(height: 14)
                .contentTransition(.opacity)
        }
        .frame(height: PullState.indicatorHeight)
        .frame(maxWidth: .infinity)
        .offset(y: (PullState.restGap + gap - PullState.indicatorHeight) / 2)
        .opacity(Double(min(max((gap - 22) / 22, 0), 1)))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.impact(weight: .light), trigger: state.phase == .armed) { _, armed in armed }
        .sensoryFeedback(.success, trigger: state.phase == .updated) { _, done in done }
        .sensoryFeedback(.error, trigger: state.phase == .failed) { _, failed in failed }
    }

    private var label: String {
        switch state.phase {
        case .idle, .pulling: return "Pull to refresh"
        case .armed: return "Release to refresh"
        case .updating: return "Updating…"
        case .updated: return "Updated just now"
        case .failed: return "Couldn’t update"
        }
    }

    private var labelColor: Color {
        switch state.phase {
        case .armed, .updated: return Color("Ink")
        case .failed: return Color("Ink2")
        default: return Color("Ink3")
        }
    }
}

/// The brand tally without its slash at 26pt: four hand-drawn strokes, then the Ember slash drawing in on success.
struct PullTally: View {
    let strokes: Int
    let failed: Bool
    let slash: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                let on = i < strokes
                TallyPath(index: i)
                    .stroke(color(on), style: StrokeStyle(lineWidth: 9 * 26 / 100, lineCap: .round))
                    .animation(.linear(duration: 0.12), value: on)
            }
            TallyPath(index: 4)
                .trim(from: 0, to: slash)
                .stroke(Color("Ember"), style: StrokeStyle(lineWidth: 10 * 26 / 100, lineCap: .round))
        }
        .frame(width: 26, height: 26)
    }

    private func color(_ on: Bool) -> Color {
        if failed { return on ? Color("StrokeMuted") : Color("Ink").opacity(0.22) }
        return on ? Color("Ink") : Color("Ink").opacity(0.14)
    }
}

/// Strokes 0–3 and the slash (4), in the mark's 100×100 drawing.
private struct TallyPath: Shape {
    let index: Int
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        let curves: [(CGPoint, CGPoint, CGPoint)] = [
            (p(30, 24), p(28, 50), p(28, 76)),
            (p(42, 23), p(42, 50), p(41, 77)),
            (p(54, 24), p(55, 50), p(54, 76)),
            (p(66, 23), p(66, 50), p(67, 77)),
            (p(16, 66), p(48, 53), p(84, 33)),
        ]
        let c = curves[index]
        var path = Path()
        path.move(to: c.0)
        path.addQuadCurve(to: c.2, control: c.1)
        return path
    }
}
