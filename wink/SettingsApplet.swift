//
//  SettingsApplet.swift
//  wink
//

import SwiftUI

/// Idle timeout, pomodoro lengths, and the debug outline of the visible window.
struct SettingsApplet: View {
    @AppStorage(SettingsKey.idleTimeout) private var idleTimeout: Double = 60
    @AppStorage(SettingsKey.pomodoroFocusMinutes) private var focusMinutes = PomodoroModel.defaultFocusMinutes
    @AppStorage(SettingsKey.pomodoroBreakMinutes) private var breakMinutes = PomodoroModel.defaultBreakMinutes
    @AppStorage(SettingsKey.showsDebugOutline) private var showsDebugOutline = false

    /// Seconds; 0 means never go idle.
    private static let idleTimeouts: [Double] = [15, 30, 60, 120, 300, 0]
    private static let focusChoices = [15, 20, 25, 30, 45, 50]
    private static let breakChoices = [3, 5, 10, 15]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: pt(12)) {
                sectionTitle("Idle after")
                ForEach(Self.idleTimeouts, id: \.self) { seconds in
                    option(Self.idleLabel(seconds), isSelected: idleTimeout == seconds) {
                        idleTimeout = seconds
                    }
                }

                sectionTitle("Pomodoro focus")
                    .padding(.top, pt(20))
                ForEach(Self.focusChoices, id: \.self) { minutes in
                    option(Self.minutesLabel(minutes), isSelected: focusMinutes == minutes) {
                        focusMinutes = minutes
                    }
                }

                sectionTitle("Pomodoro break")
                    .padding(.top, pt(20))
                ForEach(Self.breakChoices, id: \.self) { minutes in
                    option(Self.minutesLabel(minutes), isSelected: breakMinutes == minutes) {
                        breakMinutes = minutes
                    }
                }

                sectionTitle("Window outline")
                    .padding(.top, pt(20))
                option(Text("Off"), isSelected: !showsDebugOutline) { showsDebugOutline = false }
                option(Text("On"), isSelected: showsDebugOutline) { showsDebugOutline = true }
            }
            .padding(.horizontal, pt(44))
            .padding(.vertical, pt(16))
        }
        .scrollIndicators(.hidden)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.wink(22))
            .foregroundStyle(WinkTheme.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func option(_ title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack {
                title
                    .font(.wink(36))
                    .foregroundStyle(isSelected ? WinkTheme.primaryText : WinkTheme.secondaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.wink(28))
                        .foregroundStyle(WinkTheme.primaryText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlightButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func idleLabel(_ seconds: Double) -> Text {
        if seconds == 0 {
            Text("Never")
        } else {
            Text(Duration.seconds(seconds), format: .units(allowed: [.minutes, .seconds], width: .condensedAbbreviated))
        }
    }

    private static func minutesLabel(_ minutes: Int) -> Text {
        Text(Duration.seconds(minutes * 60), format: .units(allowed: [.minutes], width: .condensedAbbreviated))
    }
}

#Preview {
    WindowPreview {
        SettingsApplet()
    }
}
