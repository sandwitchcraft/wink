//
//  VisibleWindow.swift
//  wink
//

import CoreGraphics
import Foundation

/// The part of the screen left visible by the physical case, measured in millimetres
/// from the top-left corner of the display.
struct VisibleWindow: Equatable {
    var originX: Double
    var originY: Double
    var width: Double
    var height: Double

    /// Pela case on iPhone 17: ~35 mm wide x 40 mm tall, flush with the top-left corner.
    static let pelaIPhone17 = VisibleWindow(originX: 0, originY: 0, width: 35, height: 40)

    /// iPhone 15 Pro Max: 37 mm wide x 38 mm tall, inset ~1.65 mm from the left and top edges of the display.
    static let iPhone15ProMax = VisibleWindow(originX: 1.65, originY: 1.65, width: 39, height: 39)

    /// The window for the device the app is running on.
    static let current: VisibleWindow = deviceModel == "iPhone16,2" ? .iPhone15ProMax : .pelaIPhone17

    /// The hardware model identifier, such as "iPhone16,2" (iPhone 15 Pro Max).
    /// In the simulator this is the simulated device, not the Mac.
    private static var deviceModel: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// iPhone 17 display: 460 ppi at 3x scale, so 460 / 3 points per inch.
    static let iPhone17PointsPerMillimetre = (460.0 / 3.0) / 25.4

    /// Converts the millimetre measurements into a rect in screen points.
    func rect(pointsPerMillimetre: Double = Self.iPhone17PointsPerMillimetre) -> CGRect {
        CGRect(
            x: originX * pointsPerMillimetre,
            y: originY * pointsPerMillimetre,
            width: width * pointsPerMillimetre,
            height: height * pointsPerMillimetre
        )
    }
}
