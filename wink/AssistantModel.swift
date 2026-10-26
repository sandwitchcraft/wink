//
//  AssistantModel.swift
//  wink
//

import AVFoundation
import FoundationModels
import Speech
import SwiftUI

/// Hold to talk: records while the mic pill is held, transcribes on-device with `SpeechTranscriber`,
/// then answers with Apple's on-device language model. Nothing leaves the phone, and nothing is kept:
/// each question gets a fresh session and the answer is gone once dismissed.
@Observable
final class AssistantModel {
    enum Phase: Equatable {
        case ready
        case listening
        case thinking
        case answer(String)
    }

    /// Recent input levels, 0...1, newest first.
    static let levelCount = 9

    var phase = Phase.ready
    var levels = Array(repeating: 0.0, count: levelCount)
    /// Settable so previews can show the granted state.
    var permission = AVAudioApplication.shared.recordPermission

    /// True while recording or generating, when home shouldn't go idle or change page.
    var isBusy: Bool { phase == .listening || phase == .thinking }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var audioInput: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
    @ObservationIgnored private var recording: Task<Bool, Never>?
    @ObservationIgnored private var transcription: Task<String, Error>?

    /// Shows the system prompt. Only call this after the user taps, since the case hides the prompt.
    func requestAccess() async {
        _ = await AVAudioApplication.requestRecordPermission()
        refreshPermission()
    }

    /// Picks up a change made in Settings.
    func refreshPermission() {
        permission = AVAudioApplication.shared.recordPermission
    }

    /// The pill was pressed: start recording and transcribing.
    func beginListening() {
        guard phase == .ready, permission == .granted else { return }
        withAnimation(.smooth(duration: 0.4)) { phase = .listening }

        let (audio, audioInput) = AsyncStream.makeStream(of: AVReadOnlyAudioPCMBuffer.self)
        self.audioInput = audioInput
        // Transcription sets up in parallel; the stream buffers audio until it's ready.
        transcription = Task { try await Self.transcribe(audio) }
        recording = Task { await startEngine(feeding: audioInput) }
    }

    /// The pill was released: stop recording, then answer what was said.
    func endListening() {
        guard phase == .listening else { return }
        withAnimation(.smooth(duration: 0.4)) { phase = .thinking }

        Task {
            let didRecord = await recording?.value ?? false
            stopEngine()
            let reply = didRecord ? await answer() : String(localized: "Couldn't use the microphone.")
            withAnimation(.smooth(duration: 0.5)) { phase = .answer(reply) }
        }
    }

    /// The answer was tapped away.
    func dismiss() {
        guard case .answer = phase else { return }
        withAnimation(.smooth(duration: 0.5)) { phase = .ready }
    }

    // MARK: - Recording

    private func startEngine(feeding audioInput: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation) async -> Bool {
        do {
            try await VoiceNotesModel.setCategory(.record)
            try await VoiceNotesModel.activate(.sharedInstance())
            let (levelStream, levelInput) = AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))
            try Self.installTap(on: engine.inputNode, audio: audioInput, levels: levelInput)
            try engine.start()
            Task {
                for await level in levelStream {
                    levels.removeLast()
                    levels.insert(level, at: 0)
                }
            }
            return true
        } catch {
            audioInput.finish()
            return false
        }
    }

    private func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioInput?.finish()
        audioInput = nil
        levels = Array(repeating: 0, count: Self.levelCount)
        // Back to the ambient session the control panel uses to follow the volume buttons.
        Task { try? await VoiceNotesModel.setCategory(.ambient) }
    }

    /// The tap's block is `@Sendable` and runs on the audio thread; its read-only buffers are safe
    /// to hand across to the transcriber.
    private static func installTap(
        on input: AVAudioInputNode,
        audio: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation,
        levels: AsyncStream<Double>.Continuation
    ) throws {
        let format = input.outputFormat(forBus: 0)
        try input.installAudioTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            audio.yield(buffer)
            levels.yield(level(of: buffer))
        }
    }

    /// Loudness of a buffer, mapping roughly -50 dB (quiet room) ... 0 dB (loud) onto 0...1.
    private nonisolated static func level(of buffer: AVReadOnlyAudioPCMBuffer) -> Double {
        guard buffer.format.commonFormat == .pcmFormatFloat32 else { return 0 }
        return buffer.withUnsafeAudioBufferList { list in
            // The first channel is enough for a level meter.
            let channels = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            guard let first = channels.first, let data = first.mData else { return 0 }
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { return 0 }

            let samples = data.assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for index in 0..<count {
                sum += samples[index] * samples[index]
            }
            let rms = (sum / Float(count)).squareRoot()
            let decibels = 20 * log10(max(rms, 0.000_01))
            return min(max((Double(decibels) + 50) / 50, 0), 1)
        }
    }

    /// `AnalyzerInputConverter` only takes `AVAudioPCMBuffer`, so copy the read-only tap buffer into one.
    private nonisolated static func pcmBuffer(copying buffer: AVReadOnlyAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(buffer.frameLength)
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else { return nil }
        copy.frameLength = frames
        buffer.withUnsafeAudioBufferList { list in
            let sources = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
            let destinations = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (source, destination) in zip(sources, destinations) {
                guard let from = source.mData, let to = destination.mData else { continue }
                memcpy(to, from, Int(min(source.mDataByteSize, destination.mDataByteSize)))
            }
        }
        return copy
    }

    // MARK: - Transcribing

    /// Feeds recorded audio to an on-device transcriber until the stream finishes, and returns the text.
    private static func transcribe(_ audio: AsyncStream<AVReadOnlyAudioPCMBuffer>) async throws -> String {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw AssistantError.unsupportedLanguage
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        // The speech model is downloaded once per language. Audio itself never leaves the device.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let converter = try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)

        let text = Task {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }
        Task {
            defer { inputBuilder.finish() }
            do {
                for await tapBuffer in audio {
                    guard let buffer = pcmBuffer(copying: tapBuffer) else { continue }
                    for input in try converter.convert(buffer, at: nil) {
                        inputBuilder.yield(input)
                    }
                }
                for input in try converter.flush() {
                    inputBuilder.yield(input)
                }
            } catch {
                // Ends the input early; whatever was transcribed so far still counts.
            }
        }

        if let lastSample = try await analyzer.analyzeSequence(inputs) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await text.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Answering

    /// Turns the transcript into a short answer, or a short message saying why there isn't one.
    private func answer() async -> String {
        let question: String
        do {
            question = try await transcription?.value ?? ""
        } catch AssistantError.unsupportedLanguage {
            return String(localized: "Speech isn't available in your language yet.")
        } catch {
            return String(localized: "Couldn't understand that. Try again.")
        }
        guard !question.isEmpty else { return String(localized: "I didn't catch that.") }

        // On-device only: never `PrivateCloudComputeLanguageModel`.
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Turn on Apple Intelligence in Settings.")
        case .unavailable(.modelNotReady):
            return String(localized: "Apple Intelligence is still getting ready. Try again later.")
        case .unavailable:
            return String(localized: "Apple Intelligence isn't available on this device.")
        }

        // A fresh session each time, so there's no history.
        let session = LanguageModelSession(model: model, instructions: Self.instructions)
        do {
            return try await session.respond(to: question).content
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch LanguageModelError.guardrailViolation, LanguageModelError.refusal {
            return String(localized: "I can't help with that.")
        } catch {
            return String(localized: "Something went wrong. Try again.")
        }
    }

    private static var instructions: String {
        var text = """
            You are Wink, a calm personal assistant shown on a very small screen. \
            Answer in one or two short sentences. Use plain text only: no markdown, lists, or emoji.
            """
        // Apple recommends this exact phrase for locales other than U.S. English.
        if !Locale.Language(identifier: "en_US").isEquivalent(to: Locale.current.language) {
            text += " The person's locale is \(Locale.current.identifier)."
        }
        return text
    }
}

private enum AssistantError: Error {
    case unsupportedLanguage
}
