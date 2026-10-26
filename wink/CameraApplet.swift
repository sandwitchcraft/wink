//
//  CameraApplet.swift
//  wink
//

import AVFoundation
import Photos
import SwiftUI

nonisolated enum CaptureKind {
    case photo
    case video
}

/// UI-facing capture state. The capture work happens in `CameraEngine` on its own queue.
@Observable
final class CameraModel {
    let kind: CaptureKind
    private(set) var isRecording = false
    /// Whether the camera, microphone (video only) or Photos still need to be asked about.
    private(set) var needsPermission: Bool
    private(set) var isCameraAllowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized

    private let engine: CameraEngine
    /// Whether the applet is on screen, so a late permission answer doesn't start the camera after it closes.
    private var isShowing = false

    var session: AVCaptureSession { engine.session }

    init(kind: CaptureKind) {
        self.kind = kind
        engine = CameraEngine(kind: kind)
        needsPermission = Self.hasUnansweredPermission(for: kind)
    }

    func start() {
        isShowing = true
        if isCameraAllowed {
            engine.start()
        }
    }

    /// Shows the system prompts. Only call this after the user taps, since the case hides them.
    func requestAccess() async {
        isCameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        if kind == .video {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        needsPermission = false
        if isShowing {
            start()
        }
    }

    func stop() {
        isShowing = false
        if isRecording {
            engine.stopRecording()
            isRecording = false
        }
        engine.stop()
    }

    private static func hasUnansweredPermission(for kind: CaptureKind) -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
            || (kind == .video && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined)
            || PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined
    }

    /// Takes a photo, or starts/stops recording.
    func capture() {
        switch kind {
        case .photo:
            engine.capturePhoto()
        case .video:
            if isRecording {
                engine.stopRecording()
            } else {
                engine.startRecording()
            }
            isRecording.toggle()
        }
    }
}

/// Owns the capture session and saves every photo and video straight to the photo library.
nonisolated final class CameraEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()

    private let kind: CaptureKind
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    /// All session work happens here; `startRunning` blocks, so it must stay off the main thread.
    private let queue = DispatchQueue(label: "wink.camera")
    private var isConfigured = false
    /// Tracks how the phone is held, so photos and videos come out the right way up.
    private var rotation: AVCaptureDevice.RotationCoordinator?

    init(kind: CaptureKind) {
        self.kind = kind
    }

    func start() {
        queue.async {
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto() {
        queue.async {
            guard self.session.isRunning else { return }
            self.applyRotation(to: self.photoOutput)
            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    func startRecording() {
        queue.async {
            guard self.session.isRunning, !self.movieOutput.isRecording else { return }
            self.applyRotation(to: self.movieOutput)
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    private func applyRotation(to output: AVCaptureOutput) {
        guard let angle = rotation?.videoRotationAngleForHorizonLevelCapture,
              let connection = output.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = kind == .photo ? .photo : .high

        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
            rotation = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        }

        switch kind {
        case .photo:
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
        case .video:
            if let microphone = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: microphone),
               session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }
        session.commitConfiguration()
    }
}

extension CameraEngine: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
        }
    }
}

extension CameraEngine: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // A recording can end with an error (for example, interruption) and still be usable.
        guard FileManager.default.fileExists(atPath: outputFileURL.path()) else { return }
        PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = true
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: outputFileURL, options: options)
        }
    }
}

/// Back camera preview. Tap anywhere to take a photo.
struct CameraApplet: View {
    var body: some View {
        CaptureView(kind: .photo)
    }
}

/// Back camera preview. Tap anywhere to start or stop recording; a red border shows while filming.
struct VideoApplet: View {
    var body: some View {
        CaptureView(kind: .video)
    }
}

private struct CaptureView: View {
    @State private var camera: CameraModel
    @State private var isFlashing = false
    @State private var captureCount = 0

    init(kind: CaptureKind) {
        _camera = State(initialValue: CameraModel(kind: kind))
    }

    var body: some View {
        content
            .onAppear { camera.start() }
            .onDisappear { camera.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if camera.needsPermission {
            PermissionPrompt(title: camera.kind == .photo ? "Allow camera access" : "Allow camera and microphone access") {
                await camera.requestAccess()
            }
        } else if !camera.isCameraAllowed {
            Text("Allow camera access in Settings")
                .font(.wink(26))
                .multilineTextAlignment(.center)
                .foregroundStyle(WinkTheme.secondaryText)
                .padding(pt(40))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            preview
        }
    }

    private var preview: some View {
        CameraPreview(session: camera.session)
            .overlay {
                if camera.isRecording {
                    RoundedRectangle(cornerRadius: WinkLayout.screenCornerRadius, style: .continuous)
                        .strokeBorder(WinkTheme.stop, lineWidth: pt(12))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay {
                if isFlashing {
                    WinkTheme.primaryText
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                capture()
            }
            .sensoryFeedback(.impact, trigger: captureCount)
            .accessibilityElement()
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { capture() }
    }

    private var accessibilityLabel: LocalizedStringKey {
        switch camera.kind {
        case .photo: "Camera. Tap to take a photo"
        case .video: camera.isRecording ? "Recording. Tap to stop" : "Video. Tap to start recording"
        }
    }

    private func capture() {
        guard camera.isCameraAllowed else { return }
        withAnimation(.smooth(duration: 0.2)) { camera.capture() }
        captureCount += 1
        if camera.kind == .photo {
            flash()
        }
    }

    /// A quick white flash confirms a photo was taken.
    private func flash() {
        withAnimation(.easeOut(duration: 0.05)) { isFlashing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeOut(duration: 0.25)) { isFlashing = false }
        }
    }
}

/// Shows the live feed from a capture session, filling the view.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            // `layerClass` guarantees the layer type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

#Preview {
    WindowPreview {
        CameraApplet()
    }
}
