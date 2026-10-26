//
//  Applet.swift
//  wink
//

import SwiftUI

/// The small utilities that live in the Wink window.
enum Applet: CaseIterable, Identifiable {
    case camera
    case video
    case voiceNotes
    case flashlight
    case timer
    case pomodoro
    case stopwatch
    case calendar
    case reminders
    case weather
    case battery
    case settings

    /// Gallery order, four per page.
    static let gallery: [Applet] = allCases

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .camera: "camera"
        case .video: "video"
        case .voiceNotes: "waveform"
        case .flashlight: "flashlight.off.fill"
        case .timer: "timer"
        case .pomodoro: "hourglass"
        case .stopwatch: "stopwatch"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .weather: "cloud.sun"
        case .battery: "battery.75percent"
        case .settings: "gearshape"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .camera: "Camera"
        case .video: "Video"
        case .voiceNotes: "Voice Notes"
        case .flashlight: "Flashlight"
        case .timer: "Timer"
        case .pomodoro: "Pomodoro"
        case .stopwatch: "Stopwatch"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .weather: "Weather"
        case .battery: "Battery"
        case .settings: "Settings"
        }
    }
}

/// The full-window view for an applet.
struct AppletView: View {
    let applet: Applet

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WinkTheme.windowFill)
    }

    @ViewBuilder
    private var content: some View {
        switch applet {
        case .camera: CameraApplet()
        case .video: VideoApplet()
        case .voiceNotes: VoiceNotesApplet()
        case .timer: TimerApplet()
        case .pomodoro: PomodoroApplet()
        case .stopwatch: StopwatchApplet()
        case .calendar: CalendarApplet()
        case .reminders: RemindersApplet()
        case .weather: WeatherApplet()
        case .battery: BatteryApplet()
        case .settings: SettingsApplet()
        // Toggled from its icon; never opened as a screen.
        case .flashlight: EmptyView()
        }
    }
}

/// An applet's icon. Opens the applet, or toggles the flashlight and shows its state.
struct AppletIcon: View {
    @Environment(AppModel.self) private var model
    let applet: Applet

    var body: some View {
        switch applet {
        case .flashlight:
            Button {
                model.open(applet)
            } label: {
                FlashlightIcon(isOn: model.flashlight.isOn)
                    .frame(height: pt(46))
                    .frame(width: pt(104), height: pt(104))
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoHighlightButtonStyle())
            .accessibilityLabel(applet.title)
            .accessibilityValue(model.flashlight.isOn ? "On" : "Off")
        case .pomodoro:
            // SF Symbols has no tomato, so this one is drawn.
            Button {
                model.open(applet)
            } label: {
                TomatoIcon()
                    .frame(width: pt(48), height: pt(48))
                    .frame(width: pt(104), height: pt(104))
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoHighlightButtonStyle())
            .accessibilityLabel(applet.title)
        default:
            IconButton(systemImage: applet.systemImage, label: applet.title) {
                model.open(applet)
            }
        }
    }
}

/// Bare SF Symbol button with a square tap area, sized in mockup pixels.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 104
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            icon
        }
        .buttonStyle(NoHighlightButtonStyle())
        .accessibilityLabel(label)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: pt(size * 44 / 104), weight: .regular))
            .foregroundStyle(WinkTheme.icon)
            .frame(width: pt(size), height: pt(size))
            .contentShape(Rectangle())
    }
}
