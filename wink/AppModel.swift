//
//  AppModel.swift
//  wink
//

import SwiftUI

/// App-wide navigation state, plus the models that must keep running when you leave their applets.
@Observable
final class AppModel {
    /// The horizontally swipeable pages, left to right.
    enum Page: Hashable {
        case controls
        case music
        case home
        case gallery(Int)
    }

    static let galleryPages: [[Applet]] = stride(from: 0, to: Applet.gallery.count, by: 4).map {
        Array(Applet.gallery[$0..<min($0 + 4, Applet.gallery.count)])
    }

    static let pages: [Page] = [.controls, .music, .home] + galleryPages.indices.map { .gallery($0) }

    /// The page currently scrolled to. Bound to the page strip's scroll position.
    var page: Page? = .home
    /// An applet shown full-window on top of the pages.
    private(set) var openApplet: Applet?
    /// Whether home has calmed down to just the time and a smiley.
    /// Going idle dims the screen to its lowest brightness; waking restores it.
    var isHomeIdle = false {
        didSet {
            guard isHomeIdle != oldValue else { return }
            if isHomeIdle {
                brightnessBeforeIdle = ScreenBrightness.level
                ScreenBrightness.level = 0
            } else if let brightnessBeforeIdle {
                ScreenBrightness.level = brightnessBeforeIdle
                self.brightnessBeforeIdle = nil
            }
        }
    }
    @ObservationIgnored private var brightnessBeforeIdle: Double?

    let timer = TimerModel()
    let stopwatch = StopwatchModel()
    let pomodoro = PomodoroModel()
    let flashlight = FlashlightModel()
    let assistant = AssistantModel()

    init() {
        // A finished timer pulls the user back to the timer applet from wherever they are.
        timer.onFinish = { [weak self] in
            self?.open(.timer)
        }
    }

    /// Opens an applet, or flips the flashlight, which has no screen of its own.
    func open(_ applet: Applet) {
        if applet == .flashlight {
            // No `withAnimation`: the icon animates its own switch, and an app-wide animation here
            // would also animate any layout settling in the same update, making other icons rise.
            flashlight.toggle()
            return
        }
        withAnimation(.smooth) { openApplet = applet }
    }

    /// Closes the open applet, back to whichever page it was opened from.
    func closeApplet() {
        withAnimation(.smooth) { openApplet = nil }
    }
}

/// UserDefaults keys for values the Settings applet changes.
enum SettingsKey {
    static let idleTimeout = "idleTimeoutSeconds"
    static let showsDebugOutline = "showsDebugOutline"
    static let pomodoroFocusMinutes = "pomodoroFocusMinutes"
    static let pomodoroBreakMinutes = "pomodoroBreakMinutes"
}
