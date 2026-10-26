//
//  FlashlightModel.swift
//  wink
//

import AVFoundation
import SwiftUI

/// Turns the camera's torch on and off. The flashlight applet is just its icon.
@Observable
final class FlashlightModel {
    private(set) var isOn = false

    /// Flips the icon at once, then drives the torch off the main thread: the first use sets up the
    /// camera hardware, which is slow enough to stall the UI.
    func toggle() {
        isOn.toggle()
        let turnOn = isOn
        Task.detached {
            let succeeded = Self.setTorch(on: turnOn)
            if !succeeded {
                // The torch is busy (for example, the camera is in use); put the icon back.
                await MainActor.run { self.isOn = !turnOn }
            }
        }
    }

    private nonisolated static func setTorch(on: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }
}

/// A filled flashlight whose switch slides up when on and down when off. Nothing else moves.
/// Drawn rather than an SF Symbol, because swapping symbols animates the whole icon.
struct FlashlightIcon: View {
    let isOn: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let switchSize = w * 0.36

            ZStack(alignment: .top) {
                FlashlightBody()
                    .fill(WinkTheme.icon)

                // The switch: a dark well with a light knob, like the SF Symbol.
                Circle()
                    .fill(WinkTheme.windowFill)
                    .frame(width: switchSize, height: switchSize)
                    .overlay {
                        Circle()
                            .fill(WinkTheme.icon)
                            .frame(width: switchSize * 0.45, height: switchSize * 0.45)
                    }
                    .offset(y: h * (isOn ? 0.42 : 0.62) - switchSize / 2)
            }
            .frame(width: w, height: h)
        }
        .aspectRatio(0.5, contentMode: .fit)
        .animation(.smooth(duration: 0.25), value: isOn)
        .accessibilityHidden(true)
    }
}

/// A wide head tapering into a long body.
private struct FlashlightBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        // The pieces overlap so their rounded corners don't leave notches where they meet.
        var path = Path()
        // Lens rim across the top.
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY, width: w, height: 0.1 * h), cornerSize: CGSize(width: 0.06 * w, height: 0.06 * w))
        // Head tapering in to the body.
        path.move(to: point(0, 0.05))
        path.addLine(to: point(1, 0.05))
        path.addLine(to: point(0.8, 0.3))
        path.addLine(to: point(0.8, 0.5))
        path.addLine(to: point(0.2, 0.5))
        path.addLine(to: point(0.2, 0.3))
        path.closeSubpath()
        // Body, rounded at the bottom.
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.2 * w, y: rect.minY + 0.4 * h, width: 0.6 * w, height: 0.6 * h), cornerSize: CGSize(width: 0.12 * w, height: 0.12 * w))
        return path
    }
}

#Preview("Flashlight icon") {
    HStack(spacing: 40) {
        FlashlightIcon(isOn: false)
        FlashlightIcon(isOn: true)
    }
    .frame(height: 120)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
