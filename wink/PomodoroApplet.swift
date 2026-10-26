//
//  PomodoroApplet.swift
//  wink
//

import AudioToolbox
import SwiftUI

/// Focus/break cycles that repeat until stopped. Lives in `AppModel` so it keeps running when you leave the applet.
@Observable
final class PomodoroModel {
    enum Phase {
        case focus
        case rest

        var next: Phase { self == .focus ? .rest : .focus }
    }

    enum State: Equatable {
        case stopped
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
    }

    static let defaultFocusMinutes = 20
    static let defaultBreakMinutes = 5

    private(set) var phase: Phase = .focus
    private(set) var state: State = .stopped
    /// Length of the current phase, read from Settings when the phase starts.
    private(set) var phaseDuration: TimeInterval = TimeInterval(defaultFocusMinutes * 60)

    private var phaseTask: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    func start() {
        phase = .focus
        beginPhase()
    }

    func pause() {
        guard case .running(let endDate) = state else { return }
        phaseTask?.cancel()
        state = .paused(remaining: max(endDate.timeIntervalSinceNow, 0))
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        run(for: remaining)
    }

    func stop() {
        phaseTask?.cancel()
        phase = .focus
        state = .stopped
    }

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .stopped: Self.minutes(for: phase) * 60
        case .running(let endDate): max(endDate.timeIntervalSince(date), 0)
        case .paused(let remaining): remaining
        }
    }

    /// 0 at the start of a phase, 1 at its end.
    func progress(at date: Date) -> Double {
        guard state != .stopped, phaseDuration > 0 else { return 0 }
        return min(max(1 - remaining(at: date) / phaseDuration, 0), 1)
    }

    private func beginPhase() {
        phaseDuration = Self.minutes(for: phase) * 60
        run(for: phaseDuration)
    }

    private func run(for remaining: TimeInterval) {
        state = .running(endDate: .now + remaining)
        phaseTask?.cancel()
        phaseTask = Task {
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            // Two short buzzes mark the switch; the next phase starts on its own.
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            try? await Task.sleep(for: .milliseconds(600))
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            withAnimation(.smooth) {
                phase = phase.next
                beginPhase()
            }
        }
    }

    private static func minutes(for phase: Phase) -> TimeInterval {
        let key = phase == .focus ? SettingsKey.pomodoroFocusMinutes : SettingsKey.pomodoroBreakMinutes
        let fallback = phase == .focus ? defaultFocusMinutes : defaultBreakMinutes
        return TimeInterval(UserDefaults.standard.object(forKey: key) as? Int ?? fallback)
    }
}

/// The current phase, a ring that fills as it runs with the time left inside, and play/pause and stop.
struct PomodoroApplet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro

        VStack(spacing: pt(12)) {
            Text(pomodoro.phase == .focus ? "Focus" : "Break")
                .font(.wink(26))
                .foregroundStyle(WinkTheme.secondaryText)

            TimelineView(.animation(minimumInterval: 0.25, paused: !pomodoro.isRunning)) { context in
                ZStack {
                    Circle()
                        .stroke(WinkTheme.track, lineWidth: pt(10))
                    Circle()
                        .trim(from: 0, to: pomodoro.progress(at: context.date))
                        .stroke(WinkTheme.primaryText, style: StrokeStyle(lineWidth: pt(10), lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Self.format(pomodoro.remaining(at: context.date)))
                        .font(.wink(44))
                        .monospacedDigit()
                        .foregroundStyle(WinkTheme.primaryText)
                }
                .frame(width: pt(160), height: pt(160))
            }

            HStack(spacing: pt(24)) {
                switch pomodoro.state {
                case .stopped:
                    IconButton(systemImage: "play", label: "Start", size: 80) { pomodoro.start() }
                case .running:
                    IconButton(systemImage: "pause", label: "Pause", size: 80) { pomodoro.pause() }
                    IconButton(systemImage: "stop", label: "Stop", size: 80) { pomodoro.stop() }
                case .paused:
                    IconButton(systemImage: "play", label: "Resume", size: 80) { pomodoro.resume() }
                    IconButton(systemImage: "stop", label: "Stop", size: 80) { pomodoro.stop() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
    }

    /// Minutes and seconds, e.g. "19:42".
    static func format(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// An outline tomato drawn to match the regular-weight SF Symbols around it.
struct TomatoIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let lineWidth = proxy.size.width * 0.085
            TomatoShape()
                .stroke(WinkTheme.icon, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                .padding(lineWidth / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A slightly squat round body with a leafy crown and a short stem.
private struct TomatoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()
        // Body.
        path.addEllipse(in: CGRect(x: rect.minX, y: rect.minY + 0.22 * h, width: w, height: 0.78 * h))

        // Crown: four leaves fanning out from where the stem meets the top.
        let crown = point(0.5, 0.3)
        for tip in [point(0.18, 0.24), point(0.34, 0.42), point(0.66, 0.42), point(0.82, 0.24)] {
            path.move(to: crown)
            path.addQuadCurve(to: tip, control: CGPoint(x: (crown.x + tip.x) / 2, y: min(crown.y, tip.y) - 0.04 * h))
        }

        // Stem, curving slightly to the right.
        path.move(to: crown)
        path.addQuadCurve(to: point(0.6, 0.02), control: point(0.5, 0.1))
        return path
    }
}

#Preview {
    WindowPreview {
        PomodoroApplet()
    }
}

#Preview("Tomato icon") {
    TomatoIcon()
        .frame(width: 120, height: 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
}
