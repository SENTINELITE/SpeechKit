@preconcurrency import AVFoundation
import Foundation

@Observable
final class AudioCaptureManager: @unchecked Sendable {
    private(set) var isCapturing = false
    private(set) var currentLevel = 0.0
    
    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<Data>.Continuation?
    private var currentStream: AsyncStream<Data>?
    private var targetSampleRate: Double
    private let recordedAudioLock = NSLock()
    private var recordedPCMData = Data()

    init(targetSampleRate: Double = 16000) {
        self.targetSampleRate = targetSampleRate
    }

    var recordedWAVData: Data? {
        recordedAudioLock.lock()
        let pcmData = recordedPCMData
        let sampleRate = targetSampleRate
        recordedAudioLock.unlock()

        guard !pcmData.isEmpty else { return nil }
        return Self.makeWAVData(pcmData: pcmData, sampleRate: sampleRate)
    }

    func setTargetSampleRate(_ targetSampleRate: Double) {
        self.targetSampleRate = targetSampleRate
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
    
    func startCapture() throws -> AsyncStream<Data> {
        if isCapturing, let currentStream {
            return currentStream
        }

        resetRecordedAudio()

        #if os(iOS) || os(watchOS) || os(visionOS)
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
        
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            self.audioEngine = nil
            throw SpeechAudioCaptureError.audioEngineError("Failed to create target audio format")
        }
        
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            self.audioEngine = nil
            throw SpeechAudioCaptureError.audioEngineError("Failed to create audio converter from \(inputFormat) to \(targetFormat)")
        }
        
        let stream = AsyncStream<Data> { continuation in
            self.continuation = continuation
            
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.stopCapture()
                }
            }
        }
        currentStream = stream
        
        let captureBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        
        inputNode.installTap(onBus: 0, bufferSize: captureBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            let ratio = self.targetSampleRate / inputFormat.sampleRate
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            
            guard frameCount > 0, let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }
            
            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            guard status != .error, error == nil, convertedBuffer.frameLength > 0 else { return }
            
            if let channelData = convertedBuffer.int16ChannelData {
                updateLevel(from: channelData[0], frameCount: Int(convertedBuffer.frameLength))
                let data = Data(
                    bytes: channelData[0],
                    count: Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                )
                self.appendRecordedAudio(data)
                self.continuation?.yield(data)
            }
        }
        
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            self.continuation?.finish()
            self.continuation = nil
            self.currentStream = nil
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

    private func appendRecordedAudio(_ data: Data) {
        recordedAudioLock.lock()
        recordedPCMData.append(data)
        recordedAudioLock.unlock()
    }

    private func updateLevel(from samples: UnsafePointer<Int16>, frameCount: Int) {
        guard frameCount > 0 else { return }

        var sumSquares = 0.0
        for index in 0..<frameCount {
            let sample = Double(samples[index]) / Double(Int16.max)
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        let normalized = min(max(pow(rms * 8, 0.72), 0), 1)

        Task { @MainActor [weak self] in
            guard let self else { return }
            let smoothing = normalized > self.currentLevel ? 0.16 : 0.58
            self.currentLevel += (normalized - self.currentLevel) * smoothing
        }
    }
    
    #if os(iOS) || os(watchOS) || os(visionOS)
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
