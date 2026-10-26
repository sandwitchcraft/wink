//
//  HomeView.swift
//  wink
//

import AVFoundation
import SwiftUI

/// The clock in the middle of the window. Touching and holding anywhere on home records a question:
/// the time collapses into voice bars, they pulse while the answer generates, and the answer appears
/// in a dialog over the blurred home. After the idle timeout it calms down to a smaller time and a
/// smiley; tapping anywhere wakes it again (bringing back any answer that wasn't dismissed).
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.idleTimeout) private var idleTimeout: Double = 60
    @State private var lastInteraction = Date.now
    @State private var isAskingForMic = false

    private var assistant: AssistantModel { model.assistant }

    var body: some View {
        let answer = model.isHomeIdle ? nil : assistant.phase.answerText

        ZStack {
            home
                .blur(radius: answer == nil ? 0 : pt(14))
                .overlay {
                    if answer != nil {
                        Color.black.opacity(0.5)
                            .transition(.opacity)
                    }
                }

            if let answer {
                AnswerDialog(text: answer)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(PressAndHold(
            onBegan: { assistant.beginListening() },
            onEnded: { assistant.endListening() }
        ))
        .onTapGesture {
            tap(dismissing: answer != nil)
        }
        // One bump when recording starts; bump-bump when let go (light) and when the answer arrives (medium).
        .onChange(of: assistant.phase) { _, phase in
            switch phase {
            case .listening: Haptics.bump(.medium)
            case .thinking: Haptics.doubleBump(.light)
            case .answer: Haptics.doubleBump(.medium)
            case .ready: break
            }
        }
        // Leaving home (to another page or an applet) restarts the countdown, and so does each step
        // of a question, so it never dims mid-answer.
        .onChange(of: model.page) { registerInteraction() }
        .onChange(of: model.openApplet) { registerInteraction() }
        .onChange(of: assistant.phase) { registerInteraction() }
        .task(id: lastInteraction) {
            await idleAfterTimeout()
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Ask") {
            // VoiceOver can't hold, so the action toggles recording instead.
            if assistant.phase == .listening {
                assistant.endListening()
            } else {
                assistant.beginListening()
            }
        }
    }

    private var home: some View {
        let isListening = assistant.phase != .ready && assistant.phase.answerText == nil

        return VStack(spacing: pt(28)) {
            ZStack {
                ClockLabel()
                    .textRenderer(GlyphCollapse(progress: isListening ? 1 : 0))
                    .animation(.smooth(duration: 0.45), value: isListening)
                VoiceBars(phase: assistant.phase, levels: assistant.levels)
            }
            // Smaller while idle; a scale animates smoothly where a font size change wouldn't.
            .scaleEffect(model.isHomeIdle ? 0.65 : 1)
            .frame(width: pt(286), height: pt(128))

            if model.isHomeIdle {
                Smiley()
                    .frame(width: pt(44), height: pt(44))
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let hint = micHint, !model.isHomeIdle {
                Text(hint)
                    .font(.wink(20, weight: .medium))
                    .foregroundStyle(WinkTheme.secondaryText)
                    .padding(.bottom, WinkLayout.bottomInset + pt(16))
                    .transition(.opacity)
            }
        }
    }

    /// Shown until the microphone is allowed, since holding does nothing without it.
    private var micHint: LocalizedStringKey? {
        switch assistant.permission {
        case .granted: nil
        case .undetermined: isAskingForMic ? "Answer the prompt in the middle" : "Tap to allow mic"
        default: "Allow mic in Settings"
        }
    }

    private func tap(dismissing isShowingAnswer: Bool) {
        if isShowingAnswer {
            assistant.dismiss()
        } else if !model.isHomeIdle, assistant.permission == .undetermined, !isAskingForMic {
            // The system prompt only ever appears after a tap, since the case hides it.
            isAskingForMic = true
            Task {
                await assistant.requestAccess()
                isAskingForMic = false
            }
        }
        registerInteraction()
    }

    private func registerInteraction() {
        if model.isHomeIdle {
            withAnimation(.smooth(duration: 0.6)) { model.isHomeIdle = false }
        }
        lastInteraction = .now
    }

    private func idleAfterTimeout() async {
        // A timeout of 0 means "never".
        guard idleTimeout > 0, !model.isHomeIdle else { return }
        try? await Task.sleep(for: .seconds(idleTimeout))
        guard !Task.isCancelled, model.page == .home, model.openApplet == nil, !assistant.isBusy else { return }
        withAnimation(.smooth(duration: 0.8)) { model.isHomeIdle = true }
    }
}

private extension AssistantModel.Phase {
    var answerText: String? {
        if case .answer(let text) = self { text } else { nil }
    }
}

// MARK: - Hold to talk

/// A press that starts after a short hold and ends on release. A sideways swipe moves further than
/// `allowableMovement` before the hold registers, so it fails and the page strip gets it. The hold
/// covers the whole page, so it waits a little longer than a button would before counting.
private struct PressAndHold: UIGestureRecognizerRepresentable {
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.2
        press.allowableMovement = 12
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began: onBegan()
        case .ended, .cancelled, .failed: onEnded()
        default: break
        }
    }
}

/// Impact haptics, including a double bump. SwiftUI's `sensoryFeedback` plays one tap per change,
/// so the double bump uses UIKit's generator directly.
private enum Haptics {
    static func bump(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func doubleBump(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        Task {
            // Close enough to feel like one gesture, far enough apart to feel as two.
            try? await Task.sleep(for: .milliseconds(110))
            generator.impactOccurred()
        }
    }
}

// MARK: - Clock to bars

/// Squashes each glyph vertically into a thin line and fades it, left to right, so the time
/// looks like it collapses into the row of dots the voice bars grow from.
private struct GlyphCollapse: TextRenderer, Animatable {
    /// 0 is the plain text; 1 is fully collapsed.
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        // Each glyph starts a little after the one before it.
        let stagger = 0.01
        let span = 1 + stagger * Double(max(glyphs.count - 1, 0))

        for (index, glyph) in glyphs.enumerated() {
            let local = min(max(progress * span - stagger * Double(index), 0), 1)
            let bounds = glyph.typographicBounds.rect
            var copy = context
            copy.opacity = 1 - local
            copy.translateBy(x: bounds.midX, y: bounds.midY)
            copy.scaleBy(x: 1 - local * 0.4, y: max(1 - local, 0.04))
            copy.translateBy(x: -bounds.midX, y: -bounds.midY)
            copy.draw(glyph)
        }
    }
}

/// A row of rounded bars. Listening, they follow the voice level outward from the middle;
/// thinking, they morph from where they were on release into a small travelling wave.
/// Otherwise they shrink to dots and fade out.
private struct VoiceBars: View {
    let phase: AssistantModel.Phase
    let levels: [Double]

    /// The levels at the moment of release, so the wave can grow out of the last shape.
    @State private var releaseLevels: [Double] = []
    @State private var releaseTime = Date.distantPast

    private static let count = AssistantModel.levelCount * 2 - 1
    private let barWidth = pt(8)
    private let maxHeight = pt(120)
    /// How long each bar takes to morph into the wave, and the extra delay per bar out from the middle.
    private let morphDuration = 0.55
    private let morphStagger = 0.03

    var body: some View {
        let isShown = phase == .listening || phase == .thinking

        TimelineView(.animation(paused: phase != .thinking)) { context in
            HStack(spacing: pt(7)) {
                ForEach(0..<Self.count, id: \.self) { index in
                    Capsule()
                        .fill(WinkTheme.primaryText)
                        .frame(width: barWidth, height: height(at: index, time: context.date))
                        .animation(.smooth(duration: 0.12), value: levels)
                        // Bars rise from the middle outward, just after the glyphs start collapsing.
                        .scaleEffect(y: isShown ? 1 : 0.2)
                        .opacity(isShown ? 1 : 0)
                        .animation(
                            .spring(duration: 0.4, bounce: 0.3).delay(isShown ? 0.15 + distance(index) * 0.025 : 0),
                            value: isShown
                        )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onChange(of: phase) { oldPhase, newPhase in
            if oldPhase == .listening, newPhase == .thinking {
                releaseLevels = levels
                releaseTime = .now
            }
        }
        .accessibilityHidden(true)
    }

    private func distance(_ index: Int) -> Double {
        Double(abs(index - Self.count / 2))
    }

    /// A bar's height for a set of levels, with the newest level in the middle and older ones spreading outward.
    private func listeningHeight(at index: Int, levels: [Double]) -> CGFloat {
        guard !levels.isEmpty else { return barWidth }
        let level = levels[min(Int(distance(index)), levels.count - 1)]
        return barWidth + (maxHeight - barWidth) * level
    }

    private func waveHeight(at index: Int, time: Date) -> CGFloat {
        let wave = sin(time.timeIntervalSinceReferenceDate * 6 - Double(index) * 0.4)
        return barWidth + pt(28) * (wave + 1) / 2
    }

    private func height(at index: Int, time: Date) -> CGFloat {
        switch phase {
        case .listening:
            return listeningHeight(at: index, levels: levels)
        case .thinking:
            // Blend from the shape on release into the wave, the middle bar first.
            let elapsed = time.timeIntervalSince(releaseTime) - distance(index) * morphStagger
            let progress = min(max(elapsed / morphDuration, 0), 1)
            let eased = progress * progress * (3 - 2 * progress)
            let from = listeningHeight(at: index, levels: releaseLevels)
            return from + (waveHeight(at: index, time: time) - from) * eased
        default:
            return barWidth
        }
    }
}

// MARK: - Answer

/// The answer in a rounded card. Scrolls if it runs longer than the window.
private struct AnswerDialog: View {
    let text: String

    var body: some View {
        // Hugs a short answer; a long one fills the space and scrolls.
        ViewThatFits(in: .vertical) {
            label
            ScrollView {
                label
            }
            .scrollIndicators(.hidden)
        }
        .background(
            RoundedRectangle(cornerRadius: pt(36), style: .continuous)
                .fill(WinkTheme.windowFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: pt(36), style: .continuous))
        .padding(.horizontal, pt(24))
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset + pt(8))
        .frame(maxHeight: .infinity)
    }

    private var label: some View {
        Text(text)
            .font(.wink(26, weight: .medium))
            .foregroundStyle(WinkTheme.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(pt(24))
    }
}

// MARK: - Idle

/// Two eyes and a smile, with no face outline.
private struct Smiley: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let color = GraphicsContext.Shading.color(WinkTheme.secondaryText)

            let eye = w * 0.14
            for x in [0.28, 0.72] {
                let rect = CGRect(x: w * x - eye / 2, y: h * 0.22, width: eye, height: eye)
                context.fill(Path(ellipseIn: rect), with: color)
            }

            var smile = Path()
            smile.move(to: CGPoint(x: w * 0.18, y: h * 0.58))
            smile.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.58), control: CGPoint(x: w * 0.5, y: h * 0.98))
            context.stroke(smile, with: color, style: StrokeStyle(lineWidth: w * 0.09, lineCap: .round))
        }
    }
}

#Preview("Awake") {
    WindowPreview(configure: { $0.assistant.permission = .granted }) {
        HomeView()
    }
}

#Preview("Mic not allowed yet") {
    WindowPreview(configure: { $0.assistant.permission = .undetermined }) {
        HomeView()
    }
}

#Preview("Listening") {
    WindowPreview(configure: {
        $0.assistant.permission = .granted
        $0.assistant.phase = .listening
        $0.assistant.levels = [0.9, 0.6, 0.75, 0.3, 0.45, 0.55, 0.25, 0.35, 0.15]
    }) {
        HomeView()
    }
}

#Preview("Thinking") {
    WindowPreview(configure: {
        $0.assistant.permission = .granted
        $0.assistant.phase = .thinking
    }) {
        HomeView()
    }
}

#Preview("Answer") {
    WindowPreview(configure: {
        $0.assistant.phase = .answer("Paris is the capital of France. It's about 6 hours ahead of New York.")
    }) {
        HomeView()
    }
}

#Preview("Long answer") {
    WindowPreview(configure: {
        $0.assistant.phase = .answer(String(repeating: "This answer runs long enough that it needs to scroll inside the window. ", count: 4))
    }) {
        HomeView()
    }
}

#Preview("Idle") {
    WindowPreview(configure: { $0.isHomeIdle = true }) {
        HomeView()
    }
}
