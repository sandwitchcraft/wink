//
//  WinkWindow.swift
//  wink
//

import SwiftUI

/// The visible cutout of the case: a horizontally paged strip
/// (control panel, music, home, gallery pages) with any open applet on top.
/// Swipe up from the bottom edge of an applet to close it, back to the page it was opened from.
struct WinkWindow: View {
    var window: VisibleWindow = .current
    @Environment(AppModel.self) private var model
    /// How far the current home swipe has travelled upward, in points.
    @GestureState private var homeSwipe: CGFloat = 0

    /// Upward travel that commits a home swipe on release, in points.
    private let homeDistance: CGFloat = 36
    /// Predicted upward travel (from flick velocity) that also commits it.
    private let homeFlickDistance: CGFloat = 90

    var body: some View {
        ZStack {
            PageStrip()

            if let applet = model.openApplet {
                // The applet shrinks as you drag up, so the swipe gives feedback before it commits.
                let progress = min(homeSwipe / 200, 1)

                AppletView(applet: applet)
                    .id(applet)
                    .overlay(alignment: .bottom) { homeBar }
                    .scaleEffect(1 - progress * 0.2)
                    .opacity(1 - progress * 0.4)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .zIndex(1)
                    .accessibilityAction(.escape) { model.closeApplet() }
            }
        }
        .winkWindowFrame(window)
    }

    /// A subtle bar along the bottom edge that marks where the home swipe starts.
    private var homeBar: some View {
        Capsule()
            .fill(WinkTheme.secondaryText.opacity(0.4))
            .frame(width: pt(110), height: pt(7))
            .padding(.bottom, pt(14))
            .frame(maxWidth: .infinity)
            .frame(height: WinkLayout.homeZone, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($homeSwipe) { drag, swipe, _ in
                        swipe = max(-drag.translation.height, 0)
                    }
                    .onEnded { drag in
                        if -drag.translation.height > homeDistance || -drag.predictedEndTranslation.height > homeFlickDistance {
                            model.closeApplet()
                        }
                    }
            )
            .accessibilityLabel("Close")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.closeApplet() }
    }
}

/// The pages, using the system paging scroll so a swipe can start anywhere.
private struct PageStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(AppModel.pages, id: \.self) { page in
                    content(for: page)
                        .containerRelativeFrame(.horizontal)
                        .id(page)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $model.page)
        // Holding the mic pill mustn't turn into a page swipe.
        .scrollDisabled(model.assistant.isBusy)
        // The bound position isn't applied on first layout, so start on home explicitly.
        .defaultScrollAnchor(Self.homeAnchor, for: .initialOffset)
        .overlay(alignment: .bottom) {
            if !model.isHomeIdle {
                PageDots(current: model.page ?? .home)
                    .padding(.bottom, pt(16))
                    .transition(.opacity)
            }
        }
        .onChange(of: model.page) {
            if model.page != .home {
                model.isHomeIdle = false
            }
        }
    }

    /// The horizontal anchor that lines the home page up with the window.
    private static var homeAnchor: UnitPoint {
        let index = AppModel.pages.firstIndex(of: .home) ?? 0
        return UnitPoint(x: CGFloat(index) / CGFloat(max(AppModel.pages.count - 1, 1)), y: 0.5)
    }

    @ViewBuilder
    private func content(for page: AppModel.Page) -> some View {
        switch page {
        case .controls: ControlPanelPage()
        case .music: MusicPage()
        case .home: HomeView()
        case .gallery(let index): GalleryPage(applets: AppModel.galleryPages[index])
        }
    }
}

/// One dot per page, with the current page in white.
private struct PageDots: View {
    let current: AppModel.Page

    var body: some View {
        HStack(spacing: pt(10)) {
            ForEach(AppModel.pages, id: \.self) { page in
                Circle()
                    .fill(page == current ? WinkTheme.primaryText : WinkTheme.track)
                    .frame(width: pt(9), height: pt(9))
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Sizes content to the window (10 mockup px per mm, so 350 x 400 on iPhone 17), fills it with black,
    /// clips to the rounded window shape and draws the thin border. The corner radius stays 14% of the width.
    func winkWindowFrame(_ window: VisibleWindow = .current) -> some View {
        let width = pt(window.width * 10)
        let height = pt(window.height * 10)
        let shape = RoundedRectangle(cornerRadius: width * 0.14, style: .continuous)
        return self
            .frame(width: width, height: height)
            .background(shape.fill(WinkTheme.windowFill))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(WinkTheme.windowBorder, lineWidth: pt(1))
            }
    }
}

/// Shows a view inside the window frame on black, with a fresh model, for previews.
struct WindowPreview<Content: View>: View {
    private let content: Content
    @State private var model: AppModel

    /// `configure` sets up the model before the preview renders, for example to start idle.
    init(configure: (AppModel) -> Void = { _ in }, @ViewBuilder content: () -> Content) {
        let model = AppModel()
        configure(model)
        _model = State(initialValue: model)
        self.content = content()
    }

    var body: some View {
        content
            .winkWindowFrame()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .environment(model)
    }
}

#Preview {
    WindowPreview {
        WinkWindow()
    }
}
