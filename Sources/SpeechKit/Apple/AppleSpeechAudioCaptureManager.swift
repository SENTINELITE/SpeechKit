@preconcurrency import AVFoundation
import Foundation

#if !os(watchOS)
import Speech

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
final class AppleSpeechAudioCaptureManager: @unchecked Sendable {
    private(set) var isCapturing = false
    private(set) var currentLevel = 0.0

    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var currentStream: AsyncStream<AnalyzerInput>?
    private let recordedAudioLock = NSLock()
    private var recordedPCMData = Data()
    private var recordedSampleRate = 16000.0

    var recordedWAVData: Data? {
        recordedAudioLock.lock()
        let pcmData = recordedPCMData
        let sampleRate = recordedSampleRate
        recordedAudioLock.unlock()

        guard !pcmData.isEmpty else { return nil }
        return Self.makeWAVData(pcmData: pcmData, sampleRate: sampleRate)
    }

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

    func startCapture(targetFormat requestedTargetFormat: AVAudioFormat?) throws -> AsyncStream<AnalyzerInput> {
        if isCapturing, let currentStream {
            return currentStream
        }

        resetRecordedAudio()

        #if os(iOS) || os(visionOS)
        try configureAudioSession()
        #endif

        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            self.audioEngine = nil
            throw SpeechAudioCaptureError.audioEngineError("Invalid input format: \(inputFormat)")
        }

        let targetFormat = requestedTargetFormat ?? inputFormat
        guard targetFormat.sampleRate > 0, targetFormat.channelCount > 0 else {
            self.audioEngine = nil
            throw SpeechAudioCaptureError.audioEngineError("Invalid Apple Speech target format: \(targetFormat)")
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            self.audioEngine = nil
            throw SpeechAudioCaptureError.audioEngineError("Failed to create audio converter from \(inputFormat) to \(targetFormat)")
        }

        recordedAudioLock.lock()
        recordedSampleRate = targetFormat.sampleRate
        recordedAudioLock.unlock()

        let streamPair = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(20)
        )
        let stream = streamPair.stream
        continuation = streamPair.continuation
        continuation?.onTermination = { @Sendable [weak self] _ in
            self?.stopCapture()
        }
        currentStream = stream

        let captureBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        inputNode.installTap(onBus: 0, bufferSize: captureBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let frameCapacity = max(AVAudioFrameCount(Double(buffer.frameLength) * ratio), 1)
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else { return }
            self.updateLevel(from: convertedBuffer)
            self.appendRecordedAudio(from: convertedBuffer)
            self.continuation?.yield(AnalyzerInput(buffer: convertedBuffer))
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            continuation?.finish()
            continuation = nil
            currentStream = nil
            isCapturing = false
            throw error
        }

        isCapturing = true
        return stream
    }

    func stopCapture() {
        guard audioEngine != nil || continuation != nil || isCapturing else {
            isCapturing = false
            currentStream = nil
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        continuation?.finish()
        continuation = nil
        currentStream = nil
        isCapturing = false
        currentLevel = 0
    }

    private func resetRecordedAudio() {
        recordedAudioLock.lock()
        recordedPCMData.removeAll(keepingCapacity: true)
        recordedAudioLock.unlock()
    }

    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sumSquares = 0.0
        if let floatData = buffer.floatChannelData {
            let samples = floatData[0]
            for index in 0..<frameCount {
                let sample = Double(samples[index])
                sumSquares += sample * sample
            }
        } else if let int16Data = buffer.int16ChannelData {
            let samples = int16Data[0]
            for index in 0..<frameCount {
                let sample = Double(samples[index]) / Double(Int16.max)
                sumSquares += sample * sample
            }
        } else {
            return
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        let normalized = min(max(pow(rms * 8, 0.72), 0), 1)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let smoothing = normalized > self.currentLevel ? 0.16 : 0.58
            self.currentLevel += (normalized - self.currentLevel) * smoothing
        }
    }

    private func appendRecordedAudio(from buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var data = Data()
        if let int16Data = buffer.int16ChannelData {
            let samples = int16Data[0]
            data.append(Data(bytes: samples, count: frameCount * MemoryLayout<Int16>.size))
        } else if let floatData = buffer.floatChannelData {
            let samples = floatData[0]
            for index in 0..<frameCount {
                let clamped = min(max(samples[index], -1), 1)
                var sample = Int16(clamped * Float(Int16.max)).littleEndian
                Swift.withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) }
            }
        } else {
            return
        }

        recordedAudioLock.lock()
        recordedPCMData.append(data)
        recordedAudioLock.unlock()
    }

    #if os(iOS) || os(visionOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif

    private static func makeWAVData(pcmData: Data, sampleRate: Double) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let riffSize = UInt32(36) + dataSize

        var wavData = Data()
        wavData.appendASCII("RIFF")
        wavData.appendLittleEndian(riffSize)
        wavData.appendASCII("WAVE")
        wavData.appendASCII("fmt ")
        wavData.appendLittleEndian(UInt32(16))
        wavData.appendLittleEndian(UInt16(1))
        wavData.appendLittleEndian(channelCount)
        wavData.appendLittleEndian(UInt32(sampleRate))
        wavData.appendLittleEndian(byteRate)
        wavData.appendLittleEndian(blockAlign)
        wavData.appendLittleEndian(bitsPerSample)
        wavData.appendASCII("data")
        wavData.appendLittleEndian(dataSize)
        wavData.append(pcmData)
        return wavData
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
#endif
