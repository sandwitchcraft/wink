//
//  StopwatchApplet.swift
//  wink
//

import SwiftUI

/// Stopwatch state. Lives in `AppModel` so it keeps counting when you leave the applet.
@Observable
final class StopwatchModel {
    private(set) var startDate: Date?
    private(set) var accumulated: TimeInterval = 0

    var isRunning: Bool { startDate != nil }

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startDate.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if let startDate {
            accumulated += Date.now.timeIntervalSince(startDate)
            self.startDate = nil
        } else {
            startDate = .now
        }
    }

    func reset() {
        startDate = nil
        accumulated = 0
    }
}

/// A green/red start/stop button in the top left, with mm:ss:cc below.
struct StopwatchApplet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stopwatch = model.stopwatch

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: pt(12)) {
                Button {
                    stopwatch.toggle()
                } label: {
                    Text(stopwatch.isRunning ? "Stop" : "Start")
                        .font(.wink(28))
                        .foregroundStyle(.black)
                        .frame(width: pt(104), height: pt(104))
                        .background(Circle().fill(stopwatch.isRunning ? WinkTheme.stop : WinkTheme.start))
                        .contentShape(Circle())
                }
                .buttonStyle(NoHighlightButtonStyle())

                if !stopwatch.isRunning && stopwatch.accumulated > 0 {
                    IconButton(systemImage: "arrow.counterclockwise", label: "Reset", size: 80) {
                        stopwatch.reset()
                    }
                }
            }

            TimelineView(.animation(minimumInterval: 0.03, paused: !stopwatch.isRunning)) { context in
                Text(Self.format(stopwatch.elapsed(at: context.date)))
                    .font(.wink(64))
                    .monospacedDigit()
                    .foregroundStyle(WinkTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding([.top, .horizontal], pt(30))
        .padding(.bottom, WinkLayout.bottomInset)
    }

    /// Minutes, seconds and hundredths, e.g. "01:23:45".
    static func format(_ elapsed: TimeInterval) -> String {
        let hundredths = Int(elapsed * 100)
        let minutes = hundredths / 6000
        let seconds = hundredths / 100 % 60
        let fraction = hundredths % 100
        return String(format: "%02d:%02d:%02d", minutes, seconds, fraction)
    }
}

#Preview {
    WindowPreview {
        StopwatchApplet()
    }
}
