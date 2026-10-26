//
//  ControlCenterView.swift
//  wink
//

import AVFoundation
import MediaPlayer
import SwiftUI

/// The leftmost page: two vertical pill sliders for system volume and screen brightness.
struct ControlPanelPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemVolume = SystemVolume()
    @State private var brightness = ScreenBrightness.level

    var body: some View {
        @Bindable var systemVolume = systemVolume

        HStack(spacing: pt(28)) {
            PillSlider(value: $systemVolume.level, systemImage: "speaker.wave.2.fill", label: "Volume") { isDragging in
                systemVolume.isAdjusting = isDragging
            }
            PillSlider(value: $brightness, systemImage: "sun.max.fill", label: "Brightness")
        }
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset + pt(10))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            SystemVolumeView(volume: systemVolume.level)
        }
        .onChange(of: brightness) {
            ScreenBrightness.level = brightness
        }
        // Brightness has no change notification, and other applets (camera, voice notes) can switch the
        // audio session away from the one that reports volume changes, so resync when the page comes into view.
        .onChange(of: model.page) {
            if model.page == .controls {
                brightness = ScreenBrightness.level
                systemVolume.resync()
            }
        }
        // iOS deactivates the session while the app is in the background.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                systemVolume.resync()
            }
        }
    }
}

/// The system output volume, kept current when the hardware buttons change it.
@Observable
final class SystemVolume {
    /// 0...1. Setting it moves the hidden system volume slider.
    var level: Double
    /// True while the user drags the slider. iOS rounds volume to 16 steps and reports the rounded
    /// value back, which would yank the slider under the finger, so those reports are ignored meanwhile.
    @ObservationIgnored var isAdjusting = false

    @ObservationIgnored private var observation: NSKeyValueObservation?

    init() {
        let session = AVAudioSession.sharedInstance()
        level = Double(session.outputVolume)
        Self.activateAmbientSession()
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self, let newValue = change.newValue else { return }
            // KVO can fire on any thread; the model lives on the main actor.
            Task { @MainActor in
                if !self.isAdjusting {
                    self.level = Double(newValue)
                }
            }
        }
    }

    /// Re-activates the session that reports volume changes and re-reads the current level.
    func resync() {
        Self.activateAmbientSession()
        if !isAdjusting {
            level = Double(AVAudioSession.sharedInstance().outputVolume)
        }
    }

    /// `outputVolume` only reports changes while the app's audio session is active.
    /// Ambient mixes with other audio, so activating it doesn't interrupt music.
    /// Changing the category of an active session blocks, so it happens off the main thread.
    private static func activateAmbientSession() {
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            if session.category != .ambient {
                try? session.setCategory(.ambient)
            }
            session.activate { _, _ in }
        }
    }
}

/// Reads and sets the brightness of the screen showing the app.
enum ScreenBrightness {
    /// 0...1. Reads 0.5 if there's no screen yet (for example, in previews).
    static var level: Double {
        get { Double(currentScreen?.brightness ?? 0.5) }
        set { currentScreen?.brightness = CGFloat(min(max(newValue, 0), 1)) }
    }

    private static var currentScreen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }
}

/// A tall capsule that fills with white from the bottom.
/// Like iOS Control Center, dragging moves the level by how far the finger travels,
/// wherever the drag starts, rather than jumping to the touch point.
private struct PillSlider: View {
    @Binding var value: Double
    let systemImage: String
    let label: LocalizedStringKey
    /// Called with `true` when a drag starts and `false` when it ends.
    var onDragging: (Bool) -> Void = { _ in }

    /// The value when the current drag began.
    @State private var dragStartValue: Double?

    private let iconSize = pt(36)
    private let iconInset = pt(24)

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            // The icon flips to black once the white fill reaches it.
            let isIconCovered = height * value > iconInset + iconSize

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(WinkTheme.track)
                Rectangle()
                    .fill(WinkTheme.primaryText)
                    .frame(height: height * value)
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(isIconCovered ? Color.black : WinkTheme.icon)
                    .padding(.bottom, iconInset)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            // Only vertical drags move the slider; sideways swipes go to the page scroll.
            .gesture(VerticalPan(
                onBegan: {
                    dragStartValue = value
                    onDragging(true)
                },
                onChanged: { dy in
                    guard let start = dragStartValue, height > 0 else { return }
                    // Dragging up (negative dy) raises the level; a full-height drag covers the whole range.
                    value = min(max(start - dy / height, 0), 1)
                },
                onEnded: {
                    dragStartValue = nil
                    onDragging(false)
                }
            ))
        }
        .frame(width: pt(120))
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
        }
    }
}

/// A pan that only starts when the finger moves more vertically than horizontally.
/// Unlike a SwiftUI `DragGesture`, it declines horizontal swipes before claiming the touch,
/// so the paging scroll view still gets them.
private struct VerticalPan: UIGestureRecognizerRepresentable {
    let onBegan: () -> Void
    /// Called with the vertical distance travelled since the pan began (down is positive).
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onBegan()
            onChanged(context.converter.translation(in: .local)?.y ?? 0)
        case .changed:
            onChanged(context.converter.translation(in: .local)?.y ?? 0)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.y) > abs(velocity.x)
        }
    }
}

/// iOS only lets apps change the system volume through `MPVolumeView`.
/// This keeps an invisible one in the hierarchy and drives its slider.
private struct SystemVolumeView: UIViewRepresentable {
    let volume: Double

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.001
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        let target = Float(volume)
        if abs(slider.value - target) > 0.001 {
            slider.value = target
        }
    }
}

#Preview {
    WindowPreview {
        ControlPanelPage()
    }
}
