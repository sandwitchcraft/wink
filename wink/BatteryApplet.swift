//
//  BatteryApplet.swift
//  wink
//

import SwiftUI
import UIKit

/// Charge level as a big percentage over a pill that fills with white, plus a bolt while charging.
struct BatteryApplet: View {
    /// 0...1, or `nil` when the level isn't known (for example, in the Simulator).
    @State private var level: Double?
    @State private var isCharging = false

    var body: some View {
        VStack(spacing: pt(28)) {
            HStack(alignment: .firstTextBaseline, spacing: pt(8)) {
                Text(level.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–")
                    .font(.wink(72))
                    .monospacedDigit()
                    .foregroundStyle(WinkTheme.primaryText)
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.wink(36))
                        .foregroundStyle(WinkTheme.secondaryText)
                        .accessibilityLabel("Charging")
                }
            }

            ProgressPill(progress: level ?? 0, label: "Battery level")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
        .task {
            UIDevice.current.isBatteryMonitoringEnabled = true
            // Battery level only changes in 1% steps, so a slow poll is plenty.
            while !Task.isCancelled {
                update()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private func update() {
        let device = UIDevice.current
        level = device.batteryLevel < 0 ? nil : Double(device.batteryLevel)
        isCharging = device.batteryState == .charging || device.batteryState == .full
    }
}

#Preview {
    WindowPreview {
        BatteryApplet()
    }
}
