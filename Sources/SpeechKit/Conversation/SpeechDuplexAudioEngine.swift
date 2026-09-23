@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Bookkeeping for audio that has been handed to the player but not yet heard.
///
/// The duplex engine schedules assistant audio as it arrives and learns that a
/// buffer finished only from a completion callback, so the "is the assistant
/// still speaking?" answer is a byte count, not a flag. This type is a pure
/// value so the arithmetic can be tested without an audio device.
struct SpeechPlaybackQueueAccounting: Sendable, Equatable {
    /// The sample rate of the scheduled audio, in hertz.
    var sampleRate: Double
    /// The number of bytes scheduled for playback that have not been played yet.
    private(set) var pendingBytes: Int

    /// Creates playback accounting for a sample rate.
    ///
    /// - Parameters:
    ///   - sampleRate: The sample rate of the scheduled audio, in hertz.
    ///   - pendingBytes: The number of bytes already scheduled.
    init(sampleRate: Double, pendingBytes: Int = 0) {
        self.sampleRate = sampleRate
        self.pendingBytes = max(0, pendingBytes)
    }

    /// The number of bytes of 16-bit mono audio consumed per second of playback.
    var bytesPerSecond: Double {
        sampleRate * Double(SpeechPCMAudioSupport.bytesPerFrame)
    }

    /// The duration of the audio that is scheduled but not yet played, in seconds.
    var pendingSeconds: Double {
        guard bytesPerSecond > 0 else { return 0 }
        return Double(pendingBytes) / bytesPerSecond
    }

    /// A Boolean value that indicates whether any scheduled audio is still unplayed.
    var isPending: Bool {
        pendingBytes > 0
    }

    /// Records that a block of audio was handed to the player.
    ///
    /// - Parameter byteCount: The number of bytes scheduled. Negative counts are ignored.
    mutating func schedule(byteCount: Int) {
        guard byteCount > 0 else { return }
        pendingBytes += byteCount
    }

    /// Records that a block of audio finished playing.
    ///
    /// - Parameter byteCount: The number of bytes played. The pending count never goes below zero.
    mutating func didPlay(byteCount: Int) {
        guard byteCount > 0 else { return }
        pendingBytes = max(0, pendingBytes - byteCount)
    }

    /// Clears the pending count, for a flush or a teardown.
    mutating func reset() {
        pendingBytes = 0
    }

    /// Rounds a byte count down to a whole number of 16-bit frames.
    ///
    /// Providers stream raw PCM16, and a chunk boundary can land mid-sample. A
    /// trailing odd byte is dropped rather than played as noise.
    ///
    /// - Parameter byteCount: The raw byte count.
    /// - Returns: The largest even, non-negative byte count no greater than `byteCount`.
    static func frameAlignedByteCount(_ byteCount: Int) -> Int {
        guard byteCount > 0 else { return 0 }
        return byteCount - (byteCount % SpeechPCMAudioSupport.bytesPerFrame)
    }
}

/// A single audio engine that captures the microphone and plays assistant audio at the same time.
///
/// Speech-to-speech conversations need full duplex: the microphone stays open
/// while the assistant talks, so the two halves must share one `AVAudioEngine`
/// and one audio session configured for voice chat. That is the difference from
/// the transcription capture managers, which put the session in `.record` and
/// never play anything back.
///
/// Capture behaves exactly like the transcription path: 100 ms buffers converted
/// to 16-bit mono at ``sampleRate``, yielded on the stream returned by
/// ``start()``, metered into ``inputLevel``, and accumulated into
/// ``recordedWAVData``. Playback is an `AVAudioPlayerNode` on the main mixer;
/// callers push provider audio with ``enqueuePlayback(_:)`` and drop whatever
/// is still queued with ``flushPlayback()`` when the user interrupts.
@Observable
final class SpeechDuplexAudioEngine: @unchecked Sendable {
    /// A Boolean value that indicates whether the engine is capturing and playing.
    private(set) var isRunning = false
    /// The smoothed microphone level, between `0` and `1`.
    private(set) var inputLevel = 0.0
    /// The smoothed assistant playback level, between `0` and `1`.
    private(set) var outputLevel = 0.0
    /// A Boolean value that indicates whether assistant audio is scheduled but not finished.
    private(set) var isPlaybackPending = false
    /// The duration of assistant audio that is scheduled but not finished, in seconds.
    private(set) var pendingPlaybackSeconds = 0.0
    /// A Boolean value that indicates whether the OS accepted voice processing on the input node.
    ///
    /// Voice processing is what keeps the assistant from hearing itself through
    /// the speaker. When a device refuses it, the engine still runs, and this
    /// flag lets the caller warn or fall back to headphones.
    private(set) var voiceProcessingEnabled = false

    /// Diagnostics for on-device debugging; filter Console on subsystem `SpeechKit`.
    @ObservationIgnored static let logger = Logger(subsystem: "SpeechKit", category: "DuplexAudio")
    /// The number of microphone tap callbacks since the engine last started.
    @ObservationIgnored private var tapCallbackCount = 0
    /// The configuration-change observer for the running engine.
    @ObservationIgnored private var configurationObserver: NSObjectProtocol?

    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var playerNode: AVAudioPlayerNode?
    @ObservationIgnored private var playbackFormat: AVAudioFormat?
    @ObservationIgnored private var continuation: AsyncStream<Data>.Continuation?
    @ObservationIgnored private var currentStream: AsyncStream<Data>?
    @ObservationIgnored private var sampleRateValue: Double
    @ObservationIgnored private var inputLevelSmoother = SpeechAudioLevelSmoother()
    @ObservationIgnored private var outputLevelSmoother = SpeechAudioLevelSmoother()

    @ObservationIgnored private let playbackLock = NSLock()
    @ObservationIgnored private var accounting: SpeechPlaybackQueueAccounting
    @ObservationIgnored private let recordedAudioLock = NSLock()
    @ObservationIgnored private var recordedPCMData = Data()

    /// Creates a duplex audio engine.
    ///
    /// - Parameter sampleRate: The sample rate shared by capture and playback, in hertz.
    ///   GPT-Live defaults to 24 kHz.
    init(sampleRate: Double = 24000) {
        self.sampleRateValue = sampleRate
        self.accounting = SpeechPlaybackQueueAccounting(sampleRate: sampleRate)
    }

    /// The sample rate shared by capture and playback, in hertz.
    var sampleRate: Double {
        sampleRateValue
    }

    /// The captured microphone audio as a WAV file, or `nil` when nothing was captured.
    var recordedWAVData: Data? {
        recordedAudioLock.lock()
        let pcmData = recordedPCMData
        recordedAudioLock.unlock()

        guard !pcmData.isEmpty else { return nil }
        return SpeechPCMAudioSupport.makeWAVData(pcmData: pcmData, sampleRate: sampleRateValue)
    }

    /// Changes the sample rate used by capture and playback.
    ///
    /// The rate is baked into the converter and the player format when the
    /// engine starts, so a change while running is ignored.
    ///
    /// - Parameter sampleRate: The new sample rate, in hertz.
    func setSampleRate(_ sampleRate: Double) {
        guard !isRunning, sampleRate > 0 else { return }
        sampleRateValue = sampleRate
        playbackLock.lock()
        accounting.sampleRate = sampleRate
        playbackLock.unlock()
    }

    /// Asks the user for microphone access.
    ///
    /// - Returns: `true` when the app may record.
    func requestPermission() async -> Bool {
        #if os(macOS)
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
        #else
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    /// Starts capture and playback and returns the microphone stream.
    ///
    /// Calling this while the engine is already running returns the existing stream.
    ///
    /// - Returns: An asynchronous stream of 16-bit little-endian mono chunks at ``sampleRate``.
    /// - Throws: ``SpeechAudioCaptureError/audioEngineError(_:)`` when the hardware
    ///   format is unusable, or the underlying `AVAudioEngine` or `AVAudioSession` error.
    func start() throws -> AsyncStream<Data> {
        if isRunning, let currentStream {
            return currentStream
        }
        tapCallbackCount = 0

        resetRecordedAudio()
        resetPlaybackAccounting()

        #if os(iOS) || os(watchOS) || os(visionOS)
        try configureAudioSession()
        #endif

        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        enableVoiceProcessing(on: inputNode)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        Self.logger.info(
            "duplex engine starting: input \(inputFormat.sampleRate, privacy: .public) Hz x\(inputFormat.channelCount, privacy: .public), target \(self.sampleRateValue, privacy: .public) Hz, voice processing \(self.voiceProcessingEnabled, privacy: .public)"
        )
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            teardownEngine()
            throw SpeechAudioCaptureError.audioEngineError("Invalid input format: \(inputFormat)")
        }

        guard let captureFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRateValue,
            channels: 1,
            interleaved: true
        ) else {
            teardownEngine()
            throw SpeechAudioCaptureError.audioEngineError("Failed to create capture audio format")
        }

        // Player nodes want a non-interleaved float format; PCM16 from the
        // provider is converted on the way in by ``enqueuePlayback(_:)``.
        guard let playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRateValue,
            channels: 1,
            interleaved: false
        ) else {
            teardownEngine()
            throw SpeechAudioCaptureError.audioEngineError("Failed to create playback audio format")
        }
        self.playbackFormat = playbackFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: captureFormat) else {
            teardownEngine()
            throw SpeechAudioCaptureError.audioEngineError(
                "Failed to create audio converter from \(inputFormat) to \(captureFormat)"
            )
        }

        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stop()
                }
            }
        }
        currentStream = stream

        let captureBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        inputNode.installTap(onBus: 0, bufferSize: captureBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            self.tapCallbackCount += 1
            if self.tapCallbackCount == 1 || self.tapCallbackCount % 50 == 0 {
                Self.logger.info(
                    "mic tap #\(self.tapCallbackCount, privacy: .public): \(buffer.frameLength, privacy: .public) frames at \(buffer.format.sampleRate, privacy: .public) Hz x\(buffer.format.channelCount, privacy: .public)"
                )
            }

            let ratio = self.sampleRateValue / inputFormat.sampleRate
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard frameCount > 0, let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: captureFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else {
                Self.logger.error(
                    "mic conversion failed: status \(status.rawValue, privacy: .public), \(error?.localizedDescription ?? "no error", privacy: .public), frames \(convertedBuffer.frameLength, privacy: .public)"
                )
                return
            }

            if let channelData = convertedBuffer.int16ChannelData {
                self.updateInputLevel(from: channelData[0], frameCount: Int(convertedBuffer.frameLength))
                let data = Data(
                    bytes: channelData[0],
                    count: Int(convertedBuffer.frameLength) * SpeechPCMAudioSupport.bytesPerFrame
                )
                self.appendRecordedAudio(data)
                self.continuation?.yield(data)
            }
        }

        let player = AVAudioPlayerNode()
        playerNode = player
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        // The input node stays unconnected on purpose: a tap is enough for the
        // engine to render it, and routing the microphone into the mixer, even
        // at zero volume, risks playing it back out of the speaker.
        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            teardownEngine()
            continuation?.finish()
            continuation = nil
            currentStream = nil
            isRunning = false
            throw error
        }

        player.play()
        isRunning = true
        observeConfigurationChanges(on: engine)
        Self.logger.info("duplex engine running (engine.isRunning \(engine.isRunning, privacy: .public))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let engine = self.audioEngine else { return }
            Self.logger.info(
                "one second in: engine.isRunning \(engine.isRunning, privacy: .public), taps \(self.tapCallbackCount, privacy: .public), route \(Self.currentRouteDescription(), privacy: .public)"
            )
        }
        return stream
    }

    /// Restarts the engine when the system reconfigures audio underneath it.
    ///
    /// Enabling voice processing or a route change can post
    /// `AVAudioEngineConfigurationChange`, after which the engine is stopped and
    /// its taps go quiet until it is started again.
    private func observeConfigurationChanges(on engine: AVAudioEngine) {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Self.logger.info("engine configuration changed; isRunning \(engine.isRunning, privacy: .public)")
            guard self.isRunning, !engine.isRunning else { return }
            do {
                try engine.start()
                self.playerNode?.play()
                Self.logger.info("engine restarted after configuration change")
            } catch {
                Self.logger.error("engine restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func currentRouteDescription() -> String {
        #if os(iOS) || os(watchOS) || os(visionOS)
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ",")
        return "in[\(inputs)] out[\(outputs)]"
        #else
        return "n/a"
        #endif
    }

    /// Queues assistant audio for playback in arrival order.
    ///
    /// Safe to call from any thread, including the socket task that decodes
    /// provider deltas. A trailing odd byte is dropped so a chunk boundary that
    /// lands mid-sample cannot shift every following sample.
    ///
    /// - Parameter pcm16: Signed 16-bit little-endian mono samples at ``sampleRate``.
    func enqueuePlayback(_ pcm16: Data) {
        guard let playerNode, let playbackFormat else {
            Self.logger.error("playback dropped: engine not running (\(pcm16.count, privacy: .public) bytes)")
            return
        }

        let alignedCount = SpeechPlaybackQueueAccounting.frameAlignedByteCount(pcm16.count)
        guard alignedCount > 0 else { return }
        let aligned = pcm16.prefix(alignedCount)

        let frameCount = alignedCount / SpeechPCMAudioSupport.bytesPerFrame
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let channelData = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        let scale = 1 / Float(Int16.max)
        aligned.withUnsafeBytes { rawBuffer in
            for index in 0..<frameCount {
                let rawValue = rawBuffer.loadUnaligned(
                    fromByteOffset: index * SpeechPCMAudioSupport.bytesPerFrame,
                    as: UInt16.self
                )
                let sample = Int16(bitPattern: UInt16(littleEndian: rawValue))
                channelData[0][index] = Float(sample) * scale
            }
        }

        // Output metering happens here rather than through a tap on the player
        // node: the level of a chunk is known the moment it is converted, and a
        // tap would run a second render callback and converter for every buffer
        // just to recompute what we already have. The level is applied when the
        // buffer finishes playing, which is when the user actually hears it.
        let level = SpeechPCMAudioSupport.normalizedLevel(pcm16: aligned)

        playbackLock.lock()
        accounting.schedule(byteCount: alignedCount)
        let pendingBytes = accounting.pendingBytes
        let pendingSeconds = accounting.pendingSeconds
        playbackLock.unlock()
        publishPlaybackState(pendingBytes: pendingBytes, pendingSeconds: pendingSeconds)

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.didPlayBack(byteCount: alignedCount, level: level)
        }
    }

    /// Drops every queued assistant buffer, for a barge-in.
    ///
    /// Stopping a player node unschedules its buffers, so the node is restarted
    /// immediately and the next ``enqueuePlayback(_:)`` is heard normally.
    func flushPlayback() {
        playerNode?.stop()
        resetPlaybackAccounting()
        publishPlaybackState(pendingBytes: 0, pendingSeconds: 0)
        publishOutputLevel(0, reset: true)

        if isRunning, audioEngine?.isRunning == true {
            playerNode?.play()
        }
    }

    /// Stops capture and playback, finishes the microphone stream, and releases the session.
    func stop() {
        guard audioEngine != nil || continuation != nil || isRunning else {
            isRunning = false
            currentStream = nil
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        playerNode?.stop()
        teardownEngine()

        continuation?.finish()
        continuation = nil
        currentStream = nil
        isRunning = false

        resetPlaybackAccounting()
        isPlaybackPending = false
        pendingPlaybackSeconds = 0
        inputLevelSmoother.reset()
        outputLevelSmoother.reset()
        inputLevel = 0
        outputLevel = 0

        #if os(iOS) || os(watchOS) || os(visionOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Engine lifecycle helpers

    private func teardownEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if let audioEngine, let playerNode {
            audioEngine.detach(playerNode)
        }
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        playbackFormat = nil
    }

    private func enableVoiceProcessing(on inputNode: AVAudioInputNode) {
        #if os(macOS)
        // macOS aggregate devices can reject voice-processing initialization
        // when input and output have different channel layouts. Keep the
        // standard AVAudioEngine path for desktop capture and playback;
        // echo cancellation is optional for this engine.
        voiceProcessingEnabled = false
        #else
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            voiceProcessingEnabled = inputNode.isVoiceProcessingEnabled
        } catch {
            // Echo cancellation is a strong preference, not a requirement: a
            // device that refuses it can still hold a conversation on headphones.
            voiceProcessingEnabled = false
        }
        #endif
    }

    #if os(iOS) || os(watchOS) || os(visionOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        #if os(watchOS)
        let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
        #else
        let options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        #endif
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif

    // MARK: - Recorded audio

    private func resetRecordedAudio() {
        recordedAudioLock.lock()
        recordedPCMData.removeAll(keepingCapacity: true)
        recordedAudioLock.unlock()
    }

    private func appendRecordedAudio(_ data: Data) {
        recordedAudioLock.lock()
        recordedPCMData.append(data)
        recordedAudioLock.unlock()
    }

    // MARK: - Playback accounting

    private func resetPlaybackAccounting() {
        playbackLock.lock()
        accounting.reset()
        playbackLock.unlock()
    }

    private func didPlayBack(byteCount: Int, level: Double) {
        playbackLock.lock()
        accounting.didPlay(byteCount: byteCount)
        let pendingBytes = accounting.pendingBytes
        let pendingSeconds = accounting.pendingSeconds
        playbackLock.unlock()

        publishPlaybackState(pendingBytes: pendingBytes, pendingSeconds: pendingSeconds)
        // With the queue empty there is no further completion callback to decay
        // the meter, so rest it outright instead of leaving a residue on screen.
        publishOutputLevel(pendingBytes > 0 ? level : 0, reset: pendingBytes == 0)
    }

    private func publishPlaybackState(pendingBytes: Int, pendingSeconds: Double) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaybackPending = pendingBytes > 0
            self.pendingPlaybackSeconds = pendingSeconds
        }
    }

    // MARK: - Metering

    private func updateInputLevel(from samples: UnsafePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else { return }

        let normalized = SpeechPCMAudioSupport.normalizedLevel(
            int16Samples: samples,
            frameCount: frameCount
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.inputLevel = self.inputLevelSmoother.update(towards: normalized)
        }
    }

    private func publishOutputLevel(_ normalized: Double, reset: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if reset {
                self.outputLevelSmoother.reset()
                self.outputLevel = 0
            } else {
                self.outputLevel = self.outputLevelSmoother.update(towards: normalized)
            }
        }
    }
}
