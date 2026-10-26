//
//  MusicPage.swift
//  wink
//

import MediaPlayer
import SwiftUI

/// Now playing and transport controls for the system Music app.
/// iOS only lets apps control Apple Music this way, not other players.
@Observable
final class MusicModel {
    private(set) var authorization = MPMediaLibrary.authorizationStatus()
    private(set) var title: String?
    private(set) var artist: String?
    private(set) var isPlaying = false

    private let player = MusicPlayerBridge()

    var isAuthorized: Bool { authorization == .authorized }

    /// Shows the system prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        authorization = await MPMediaLibrary.requestAuthorization()
    }

    /// Follows track changes until cancelled. Does nothing without access.
    func observeNowPlaying() async {
        guard isAuthorized else { return }
        player.beginNotifications()
        defer { player.endNotifications() }
        await refresh()
        for await _ in NotificationCenter.default.notifications(named: .MPMusicPlayerControllerNowPlayingItemDidChange) {
            await refresh()
        }
    }

    /// Follows play/pause changes made outside the app until cancelled.
    func observePlaybackState() async {
        guard isAuthorized else { return }
        for await _ in NotificationCenter.default.notifications(named: .MPMusicPlayerControllerPlaybackStateDidChange) {
            await refresh()
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        // Flip right away so the button responds; the state notification confirms it.
        isPlaying.toggle()
    }

    func next() {
        player.skipToNext()
    }

    func previous() {
        player.skipToPrevious()
    }

    private func refresh() async {
        let nowPlaying = await player.nowPlaying()
        title = nowPlaying.title
        artist = nowPlaying.artist
        isPlaying = nowPlaying.isPlaying
    }
}

/// Talks to the system music player on a background queue.
/// Every call is a synchronous round trip to the Music app, which can stall the main thread.
nonisolated final class MusicPlayerBridge: @unchecked Sendable {
    struct NowPlaying: Sendable {
        let title: String?
        let artist: String?
        let isPlaying: Bool
    }

    private let queue = DispatchQueue(label: "wink.music")
    /// Created on first use, on the queue, so building it doesn't block launch either.
    private var cachedPlayer: MPMusicPlayerController?

    private var player: MPMusicPlayerController {
        if let cachedPlayer { return cachedPlayer }
        let player = MPMusicPlayerController.systemMusicPlayer
        cachedPlayer = player
        return player
    }

    func nowPlaying() async -> NowPlaying {
        await withCheckedContinuation { continuation in
            queue.async {
                let item = self.player.nowPlayingItem
                continuation.resume(returning: NowPlaying(
                    title: item?.title,
                    artist: item?.artist,
                    isPlaying: self.player.playbackState == .playing
                ))
            }
        }
    }

    func beginNotifications() { queue.async { self.player.beginGeneratingPlaybackNotifications() } }
    func endNotifications() { queue.async { self.player.endGeneratingPlaybackNotifications() } }
    func play() { queue.async { self.player.play() } }
    func pause() { queue.async { self.player.pause() } }
    func skipToNext() { queue.async { self.player.skipToNextItem() } }
    func skipToPrevious() { queue.async { self.player.skipToPreviousItem() } }
}

/// The page between the control panel and home.
struct MusicPage: View {
    @Environment(AppModel.self) private var model
    @State private var music = MusicModel()

    var body: some View {
        content
            .padding(.top, WinkLayout.islandClearance)
            .padding(.bottom, WinkLayout.bottomInset + pt(10))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Follow playback only while the page is showing and access is granted.
            .task(id: isObserving) {
                guard isObserving else { return }
                await music.observeNowPlaying()
            }
            .task(id: isObserving) {
                guard isObserving else { return }
                await music.observePlaybackState()
            }
    }

    private var isObserving: Bool {
        model.page == .music && music.isAuthorized
    }

    @ViewBuilder
    private var content: some View {
        switch music.authorization {
        case .notDetermined:
            PermissionPrompt(title: "Allow Music access") {
                await music.requestAccess()
            }
        case .authorized:
            player
        default:
            Text("Allow Music access in Settings")
                .font(.wink(26))
                .multilineTextAlignment(.center)
                .foregroundStyle(WinkTheme.secondaryText)
                .padding(.horizontal, pt(40))
        }
    }

    private var player: some View {
        VStack(spacing: pt(8)) {
            Text(music.title ?? String(localized: "Nothing playing"))
                .font(.wink(32))
                .foregroundStyle(music.title == nil ? WinkTheme.secondaryText : WinkTheme.primaryText)
            if let artist = music.artist {
                Text(artist)
                    .font(.wink(22, weight: .medium))
                    .foregroundStyle(WinkTheme.secondaryText)
            }

            Spacer(minLength: 0)

            HStack(spacing: pt(4)) {
                IconButton(systemImage: "backward.fill", label: "Previous", size: 96) { music.previous() }
                IconButton(
                    systemImage: music.isPlaying ? "pause.fill" : "play.fill",
                    label: music.isPlaying ? "Pause" : "Play",
                    size: 96
                ) { music.togglePlayback() }
                IconButton(systemImage: "forward.fill", label: "Next", size: 96) { music.next() }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, pt(36))
    }
}

#Preview {
    WindowPreview {
        MusicPage()
    }
}
