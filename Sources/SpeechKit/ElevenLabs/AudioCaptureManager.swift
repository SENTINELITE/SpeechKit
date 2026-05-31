@preconcurrency import AVFoundation
import Foundation

@Observable
final class AudioCaptureManager: @unchecked Sendable {
    private(set) var isCapturing = false
    
    private var audioEngine: AVAudioEngine?
    private var continuation: AsyncStream<Data>.Continuation?
    private var currentStream: AsyncStream<Data>?
    private var targetSampleRate: Double

    init(targetSampleRate: Double = 16000) {
        self.targetSampleRate = targetSampleRate
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
                let data = Data(
                    bytes: channelData[0],
                    count: Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                )
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
    }
    
    #if os(iOS) || os(watchOS) || os(visionOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
    #endif
}
