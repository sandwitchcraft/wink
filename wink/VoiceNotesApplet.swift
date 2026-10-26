//
//  VoiceNotesApplet.swift
//  wink
//

import AVFoundation
import SwiftUI

/// Records voice notes as .m4a files in the app's Documents folder ("Voice Notes"),
/// which shows up in the Files app under On My iPhone > Wink.
@Observable
final class VoiceNotesModel {
    static let barCount = 24

    private(set) var permission = AVAudioApplication.shared.recordPermission
    private(set) var isRecording = false
    /// Recent input levels, 0...1, oldest first.
    private(set) var levels = Array(repeating: 0.0, count: barCount)

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?

    /// Shows the system prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        _ = await AVAudioApplication.requestRecordPermission()
        permission = AVAudioApplication.shared.recordPermission
    }

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func stop() {
        meterTask?.cancel()
        recorder?.stop()
        recorder = nil
        isRecording = false
        levels = Array(repeating: 0, count: Self.barCount)
        // Back to the ambient session the control panel uses to follow the volume buttons.
        Task { try? await Self.setCategory(.ambient) }
    }

    private func start() async {
        let session = AVAudioSession.sharedInstance()
        do {
            try await Self.setCategory(.record)
            try await Self.activate(session)
            let recorder = try AVAudioRecorder(url: try Self.newNoteURL(), settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                stop()
                return
            }
            self.recorder = recorder
            isRecording = true
            followLevels(of: recorder)
        } catch {
            stop()
        }
    }

    /// Samples the input level about 20 times a second while recording.
    private func followLevels(of recorder: AVAudioRecorder) {
        meterTask = Task {
            while !Task.isCancelled {
                recorder.updateMeters()
                // Map roughly -50 dB (quiet room) ... 0 dB (loud) onto 0...1.
                let level = min(max((Double(recorder.averagePower(forChannel: 0)) + 50) / 50, 0), 1)
                levels.removeFirst()
                levels.append(level)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// Changing the category of an active session blocks, so it happens off the main thread.
    /// Does nothing if the session already has that category. The assistant shares this.
    nonisolated static func setCategory(_ category: AVAudioSession.Category) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = AVAudioSession.sharedInstance()
                do {
                    if session.category != category {
                        try session.setCategory(category)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// `setActive` blocks the main thread, so use the asynchronous activation API.
    static func activate(_ session: AVAudioSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.activate { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// A new file like "Voice Notes/2026-10-27 14.05.12.m4a".
    private static func newNoteURL() throws -> URL {
        let folder = URL.documentsDirectory.appending(path: "Voice Notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return folder.appending(path: "\(formatter.string(from: .now)).m4a")
    }
}

/// A live waveform above a start/stop button.
struct VoiceNotesApplet: View {
    @State private var notes = VoiceNotesModel()

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, WinkLayout.islandClearance)
            .padding(.bottom, WinkLayout.bottomInset)
            .onDisappear { notes.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch notes.permission {
        case .undetermined:
            PermissionPrompt(title: "Allow microphone access") {
                await notes.requestAccess()
            }
        case .granted:
            recorder
        default:
            Text("Allow microphone access in Settings")
                .font(.wink(26))
                .multilineTextAlignment(.center)
                .foregroundStyle(WinkTheme.secondaryText)
                .padding(.horizontal, pt(40))
        }
    }

    private var recorder: some View {
        VStack(spacing: pt(24)) {
            Waveform(levels: notes.levels)
                .frame(height: pt(110))

            Button {
                Task { await notes.toggle() }
            } label: {
                Image(systemName: notes.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: pt(40), weight: .regular))
                    .foregroundStyle(.black)
                    .frame(width: pt(104), height: pt(104))
                    .background(Circle().fill(notes.isRecording ? WinkTheme.stop : WinkTheme.primaryText))
                    .contentShape(Circle())
            }
            .buttonStyle(NoHighlightButtonStyle())
            .accessibilityLabel(notes.isRecording ? "Stop recording" : "Start recording")
        }
    }
}

/// Rounded bars whose heights follow the input level; flat dots when silent.
private struct Waveform: View {
    let levels: [Double]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: pt(6)) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .fill(WinkTheme.primaryText)
                        .frame(width: pt(6), height: max(pt(6), proxy.size.height * levels[index]))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.linear(duration: 0.05), value: levels)
        .accessibilityHidden(true)
    }
}

#Preview {
    WindowPreview {
        VoiceNotesApplet()
    }
}
