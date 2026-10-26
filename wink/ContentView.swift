//
//  ContentView.swift
//  wink
//

import SwiftUI

/// Black full-screen canvas with the Wink window centred inside the visible window.
/// The red debug outline of the window is toggled in the Settings applet.
struct ContentView: View {
    var window: VisibleWindow = .current
    /// Shows the outline regardless of the setting, for previews.
    var forcesDebugOutline = false

    @AppStorage(SettingsKey.showsDebugOutline) private var showsDebugOutline = false
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let rect = window.rect()

        ZStack(alignment: .topLeading) {
            Color.black

            WinkWindow(window: window)
                .frame(width: rect.width, height: rect.height)
                .overlay {
                    if showsDebugOutline || forcesDebugOutline {
                        Rectangle()
                            .strokeBorder(.red, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .offset(x: rect.minX, y: rect.minY)
        }
        .ignoresSafeArea()
        .environment(model)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // Screen brightness is system-wide, so wake (and restore brightness) before leaving the app.
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                model.isHomeIdle = false
                // A hold can't outlive the app being in front.
                model.assistant.endListening()
            } else {
                model.assistant.refreshPermission()
            }
        }
    }
}

#Preview("Clock") {
    ContentView()
}

#Preview("Debug outline") {
    ContentView(forcesDebugOutline: true)
}

#Preview("iPhone 15 Pro Max window") {
    ContentView(window: .iPhone15ProMax, forcesDebugOutline: true)
}
