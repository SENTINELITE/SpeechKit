import AVFoundation
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Records temporary WAV files for the recorded-upload sample.
@Observable
@MainActor
final class DemoAudioRecorder {
    private var recorder: AVAudioRecorder?
    private var meteringTimer: Timer?

    /// Whether the demo is currently recording a dictation file.
    private(set) var isRecording = false
    /// The smoothed input level used by the demo visuals.
    private(set) var currentLevel = 0.0
    /// The most recent recording URL available for upload or export.
    private(set) var lastRecordingURL: URL?

    /// Starts a microphone recording and returns the temporary WAV URL.
    func startRecording() async throws -> URL {
        guard !isRecording else {
            if let lastRecordingURL {
                return lastRecordingURL
            }
            throw DemoAudioRecorderError.recordingAlreadyActive
        }

        let allowed = await requestPermission()
        guard allowed else {
            throw DemoAudioRecorderError.permissionDenied
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechKitDemo-Dictation-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw DemoAudioRecorderError.failedToStart
        }

        self.recorder = recorder
        lastRecordingURL = url
        isRecording = true
        startMetering()
        return url
    }

    /// Stops the current recording and returns the last WAV URL, if one exists.
    func stopRecording() -> URL? {
        meteringTimer?.invalidate()
        meteringTimer = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        currentLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return lastRecordingURL
    }

    /// Stops the current recording and waits until the WAV file is ready to upload.
    func stopRecordingForUpload() async throws -> URL? {
        guard let url = stopRecording() else {
            return nil
        }

        try await waitForReadableRecording(at: url)
        return url
    }

    /// Gives AVAudioRecorder time to finalize the file before a provider reads it.
    private func waitForReadableRecording(at url: URL) async throws {
        var previousSize: UInt64?

        for _ in 0..<12 {
            let size = try fileSize(at: url)
            if size > 44, previousSize == size {
                return
            }

            previousSize = size
            try await Task.sleep(for: .milliseconds(75))
        }

        throw DemoAudioRecorderError.recordingNotReady
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            return UInt64(values.fileSize ?? 0)
        } catch {
            throw DemoAudioRecorderError.recordingNotReady
        }
    }

    /// Polls `AVAudioRecorder` metering for the demo's voice orb.
    private func startMetering() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let recorder = self.recorder, recorder.isRecording else {
                    self?.meteringTimer?.invalidate()
                    self?.meteringTimer = nil
                    return
                }

                recorder.updateMeters()
                self.updateLevel(Self.normalizedLevel(fromAveragePower: recorder.averagePower(forChannel: 0)))
            }
        }
    }

    /// Smooths raw microphone level changes for UI animation.
    private func updateLevel(_ rawLevel: Double) {
        let clampedLevel = min(max(rawLevel, 0), 1)
        let smoothing = clampedLevel > currentLevel ? 0.16 : 0.58
        currentLevel += (clampedLevel - currentLevel) * smoothing
    }

    /// Requests microphone permission for recording.
    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Converts decibel metering into a normalized value for display.
    nonisolated private static func normalizedLevel(fromAveragePower averagePower: Float) -> Double {
        let floor: Float = -62
        let ceiling: Float = -8
        let clampedPower = max(floor, min(ceiling, averagePower))
        let normalized = Double((clampedPower - floor) / (ceiling - floor))
        return pow(normalized, 0.72)
    }
}

/// A passive microphone meter used before the user starts a workflow.
@Observable
@MainActor
final class DemoInputPreviewMonitor {
    private var audioEngine: AVAudioEngine?

    /// Whether the passive preview tap is active.
    private(set) var isPreviewing = false
    /// The smoothed passive input level used by the demo visuals.
    private(set) var currentLevel = 0.0

    /// Whether the app can start the passive meter without prompting.
    var isMicrophoneAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Starts the preview only when the user has already granted microphone access.
    func startIfAuthorized() {
        guard isMicrophoneAuthorized else { return }
        do {
            try start()
        } catch {
            stop()
        }
    }

    /// Starts a lightweight audio-engine tap for visual metering.
    func start() throws {
        guard !isPreviewing else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DemoAudioRecorderError.failedToStart
        }

        let bufferSize = AVAudioFrameCount(format.sampleRate * 0.08)
        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: format,
            block: Self.makePreviewTap { [weak self] level in
                Task { @MainActor [weak self] in
                    self?.updateLevel(level)
                }
            }
        )

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw error
        }

        audioEngine = engine
        isPreviewing = true
    }

    /// Stops the passive meter and releases the audio session.
    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isPreviewing = false
        currentLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Smooths preview level changes for UI animation.
    private func updateLevel(_ rawLevel: Double) {
        let clampedLevel = min(max(rawLevel, 0), 1)
        let smoothing = clampedLevel > currentLevel ? 0.12 : 0.42
        currentLevel += (clampedLevel - currentLevel) * smoothing
    }

    /// Creates the audio tap outside MainActor isolation; AVAudioEngine invokes this on its realtime queue.
    nonisolated private static func makePreviewTap(
        _ onLevel: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            onLevel(normalizedLevel(from: buffer))
        }
    }

    /// Computes an RMS-based normalized level from an audio buffer.
    nonisolated private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        var sumSquares = 0.0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameCount {
                let sample = Double(samples[frame])
                sumSquares += sample * sample
            }
        }

        let rms = sqrt(sumSquares / Double(frameCount * max(channelCount, 1)))
        return min(max(pow(rms * 7, 0.72), 0), 1)
    }
}

/// Recording failures shown directly in the sample UI.
enum DemoAudioRecorderError: LocalizedError {
    case recordingAlreadyActive
    case permissionDenied
    case failedToStart
    case recordingNotReady

    var errorDescription: String? {
        switch self {
        case .recordingAlreadyActive:
            return "Recording is already active."
        case .permissionDenied:
            return "Microphone permission denied."
        case .failedToStart:
            return "Recording could not start."
        case .recordingNotReady:
            return "Recording was not ready to upload. Try recording again."
        }
    }
}

/// A WAV file document used by the demo's audio export action.
struct RecordedAudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.wav] }

    var data: Data

    /// Creates a document from WAV data produced by realtime or recorded upload capture.
    init(data: Data = Data()) {
        self.data = data
    }

    /// Creates a document from file importer data.
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    /// Writes the WAV data to the destination selected by the system exporter.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
