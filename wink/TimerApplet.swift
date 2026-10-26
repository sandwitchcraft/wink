//
//  TimerApplet.swift
//  wink
//

import AudioToolbox
import SwiftUI

/// Countdown state. Lives in `AppModel` so a timer keeps running when you leave the applet.
@Observable
final class TimerModel {
    enum Phase: Equatable {
        case choosing
        case running(endDate: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    private(set) var phase: Phase = .choosing
    private(set) var minutes = 0
    /// Called when a countdown reaches zero.
    var onFinish: (() -> Void)?

    private var finishTask: Task<Void, Never>?
    private var buzzTask: Task<Void, Never>?

    private var duration: TimeInterval { TimeInterval(minutes * 60) }

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    var isFinished: Bool { phase == .finished }

    func start(minutes: Int) {
        self.minutes = minutes
        run(for: duration)
    }

    func pause() {
        guard case .running(let endDate) = phase else { return }
        finishTask?.cancel()
        phase = .paused(remaining: max(endDate.timeIntervalSinceNow, 0))
    }

    func resume() {
        guard case .paused(let remaining) = phase else { return }
        run(for: remaining)
    }

    func stop() {
        finishTask?.cancel()
        phase = .choosing
    }

    /// Stops the buzzing after a finished timer and goes back to choosing.
    func acknowledge() {
        buzzTask?.cancel()
        phase = .choosing
    }

    /// 0 at the start, 1 when the time is up.
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let remaining: TimeInterval = switch phase {
        case .choosing: duration
        case .running(let endDate): endDate.timeIntervalSince(date)
        case .paused(let remaining): remaining
        case .finished: 0
        }
        return min(max(1 - remaining / duration, 0), 1)
    }

    private func run(for remaining: TimeInterval) {
        phase = .running(endDate: .now + remaining)
        finishTask?.cancel()
        finishTask = Task {
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func finish() {
        withAnimation(.smooth) { phase = .finished }
        onFinish?()
        // Buzz every couple of seconds until the user taps.
        buzzTask = Task {
            while !Task.isCancelled {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Pick a duration from a scrolling list, then watch a pill fill with white as it runs.
struct TimerApplet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let timer = model.timer

        ZStack {
            switch timer.phase {
            case .choosing:
                TimerPicker { minutes in
                    withAnimation(.smooth) { timer.start(minutes: minutes) }
                }
                // Zooms in past the viewer as the countdown takes over.
                .transition(.scale(scale: 1.3).combined(with: .opacity))
            case .running, .paused, .finished:
                TimerCountdown(timer: timer)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .onDisappear {
            if timer.isFinished { timer.acknowledge() }
        }
    }
}

private struct TimerPicker: View {
    let start: (Int) -> Void

    private static let durations = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.fixed(pt(136)), spacing: pt(24)), GridItem(.fixed(pt(136)))],
                spacing: pt(24)
            ) {
                ForEach(Self.durations, id: \.self) { minutes in
                    Button {
                        start(minutes)
                    } label: {
                        VStack(spacing: 0) {
                            Text(minutes, format: .number)
                                .font(.wink(56))
                                .monospacedDigit()
                                .foregroundStyle(WinkTheme.primaryText)
                            Text("min")
                                .font(.wink(18))
                                .foregroundStyle(WinkTheme.secondaryText)
                        }
                        .frame(width: pt(136), height: pt(136))
                        .background(Circle().strokeBorder(WinkTheme.track, lineWidth: pt(3)))
                        .contentShape(Circle())
                    }
                    .buttonStyle(NoHighlightButtonStyle())
                    .accessibilityLabel("\(minutes) minutes")
                }
            }
            .padding(.vertical, pt(16))
        }
        .scrollIndicators(.hidden)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
    }
}

/// A big number with a small "min" on the same baseline.
private struct MinutesLabel: View {
    let minutes: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: pt(8)) {
            Text(minutes, format: .number)
                .font(.wink(72))
                .monospacedDigit()
                .foregroundStyle(WinkTheme.primaryText)
            Text("min")
                .font(.wink(20))
                .foregroundStyle(WinkTheme.secondaryText)
        }
    }
}

private struct TimerCountdown: View {
    let timer: TimerModel

    var body: some View {
        VStack(spacing: 0) {
            controls
                .frame(maxHeight: .infinity)

            TimelineView(.animation(minimumInterval: 0.1, paused: !timer.isRunning)) { context in
                ProgressPill(progress: timer.progress(at: context.date))
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
        .contentShape(Rectangle())
        .onTapGesture {
            if timer.isFinished {
                withAnimation(.smooth) { timer.acknowledge() }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isFinished {
            MinutesLabel(minutes: timer.minutes)
                .accessibilityLabel("\(timer.minutes) minute timer done. Tap to dismiss.")
        } else {
            HStack(spacing: pt(24)) {
                if timer.isRunning {
                    IconButton(systemImage: "pause", label: "Pause") { timer.pause() }
                } else {
                    IconButton(systemImage: "play", label: "Resume") { timer.resume() }
                }
                IconButton(systemImage: "stop", label: "Stop") {
                    withAnimation(.smooth) { timer.stop() }
                }
            }
        }
    }
}

/// A capsule that fills with white from the left as progress goes from 0 to 1. No text.
struct ProgressPill: View {
    let progress: Double
    var label: LocalizedStringKey = "Timer progress"

    var body: some View {
        Capsule()
            .fill(WinkTheme.track)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(WinkTheme.primaryText)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .clipShape(Capsule())
            .frame(width: pt(286), height: pt(128))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview("Picker") {
    WindowPreview {
        TimerApplet()
    }
}

#Preview("Running") {
    WindowPreview {
        TimerCountdown(timer: {
            let timer = TimerModel()
            timer.start(minutes: 1)
            return timer
        }())
    }
}
