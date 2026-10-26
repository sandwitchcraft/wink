//
//  WinkTheme.swift
//  wink
//

import SwiftUI

/// Colors used by the Wink UI, kept in one place so they are easy to tweak.
enum WinkTheme {
    /// True black so the window blends into the Dynamic Island.
    static let windowFill = hexColor(0x000000)
    static let windowBorder = hexColor(0x26262A)
    static let primaryText = hexColor(0xFFFFFF)
    static let secondaryText = hexColor(0xA1A1AA)
    static let icon = hexColor(0xF4F4F5)
    /// Unfilled part of sliders and progress pills.
    static let track = hexColor(0x26262A)
    static let start = hexColor(0x30D158)
    static let stop = hexColor(0xFF453A)
    static let cold = hexColor(0x4A90FF)
    static let hot = hexColor(0xFF4D4D)
    static let rain = hexColor(0x4A90FF)
}

/// Converts mockup sizes (10 px per mm) to points. Calibrate this against the physical case.
enum WinkScale {
    static let pointsPerMockupPixel: CGFloat = 0.6
}

/// Mockup pixels to points.
func pt(_ mockupPixels: CGFloat) -> CGFloat {
    mockupPixels * WinkScale.pointsPerMockupPixel
}

/// Fixed layout values in points. These follow the hardware, so they are not scaled.
enum WinkLayout {
    /// How far down from the top of the window the Dynamic Island reaches on iPhone 17, plus a small margin.
    /// Applets keep their content below this line.
    static let islandClearance: CGFloat = 54
    /// Corner radius of the iPhone 17 display (approximate; iOS doesn't publish it). The window sits in the
    /// screen's top-left corner, so edge-hugging decoration like the recording border uses this to follow the glass.
    static let screenCornerRadius: CGFloat = 62
    /// Height of the strip along an applet's bottom edge where the swipe up to go home starts.
    static let homeZone: CGFloat = 44
    /// Space applets leave at the bottom for page dots or the home bar.
    static let bottomInset: CGFloat = 30
}

extension Font {
    /// SF Rounded at a mockup pixel size.
    static func wink(_ mockupPixels: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: pt(mockupPixels), weight: weight, design: .rounded)
    }
}

/// Shows the label unchanged when pressed: no dimming or highlight.
struct NoHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Creates an opaque color from a 0xRRGGBB value.
private func hexColor(_ hex: UInt32) -> Color {
    Color(
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255
    )
}
