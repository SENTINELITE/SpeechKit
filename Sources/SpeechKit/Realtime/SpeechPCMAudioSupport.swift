import Foundation

/// Shared linear PCM helpers used by SpeechKit's capture and duplex audio paths.
///
/// SpeechKit normalizes every microphone provider to signed 16-bit little-endian
/// mono samples, so the WAV writer and the level meter are identical wherever
/// audio is captured or played back. Keeping them here means the transcription
/// capture manager and the speech-to-speech duplex engine cannot drift apart.
enum SpeechPCMAudioSupport {
    /// The number of bytes in one 16-bit mono sample frame.
    static let bytesPerFrame = MemoryLayout<Int16>.size

    /// Wraps raw 16-bit mono PCM samples in a canonical 44-byte WAV header.
    ///
    /// - Parameters:
    ///   - pcmData: Signed 16-bit little-endian mono samples, without a container.
    ///   - sampleRate: The sample rate the samples were captured at, in hertz.
    /// - Returns: A complete RIFF/WAVE file.
    static func makeWAVData(pcmData: Data, sampleRate: Double) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let riffSize = UInt32(36) + dataSize

        var wavData = Data()
        wavData.appendSpeechASCII("RIFF")
        wavData.appendSpeechLittleEndian(riffSize)
        wavData.appendSpeechASCII("WAVE")
        wavData.appendSpeechASCII("fmt ")
        wavData.appendSpeechLittleEndian(UInt32(16))
        wavData.appendSpeechLittleEndian(UInt16(1))
        wavData.appendSpeechLittleEndian(channelCount)
        wavData.appendSpeechLittleEndian(UInt32(sampleRate))
        wavData.appendSpeechLittleEndian(byteRate)
        wavData.appendSpeechLittleEndian(blockAlign)
        wavData.appendSpeechLittleEndian(bitsPerSample)
        wavData.appendSpeechASCII("data")
        wavData.appendSpeechLittleEndian(dataSize)
        wavData.append(pcmData)
        return wavData
    }

    /// Returns the display level for a block of 16-bit mono samples.
    ///
    /// The value is the root mean square of the block, scaled and curved so that
    /// conversational speech lands in the upper half of the range instead of
    /// hugging zero the way a raw RMS does.
    ///
    /// - Parameters:
    ///   - int16Samples: A pointer to at least `frameCount` samples.
    ///   - frameCount: The number of samples to measure.
    /// - Returns: A value between `0` and `1`, or `0` when there is nothing to measure.
    static func normalizedLevel(int16Samples: UnsafePointer<Int16>, frameCount: Int) -> Double {
        guard frameCount > 0 else { return 0 }

        var sumSquares = 0.0
        for index in 0..<frameCount {
            let sample = Double(int16Samples[index]) / Double(Int16.max)
            sumSquares += sample * sample
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        return min(max(pow(rms * 8, 0.72), 0), 1)
    }

    /// Returns the display level for an array of 16-bit mono samples.
    ///
    /// - Parameter int16Samples: The samples to measure.
    /// - Returns: A value between `0` and `1`, or `0` when the array is empty.
    static func normalizedLevel(int16Samples: [Int16]) -> Double {
        int16Samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return normalizedLevel(int16Samples: baseAddress, frameCount: buffer.count)
        }
    }

    /// Returns the display level for a block of raw little-endian PCM16 bytes.
    ///
    /// A trailing odd byte, if any, is ignored rather than treated as a sample.
    ///
    /// - Parameter pcm16: Signed 16-bit little-endian mono samples.
    /// - Returns: A value between `0` and `1`, or `0` when there is nothing to measure.
    static func normalizedLevel(pcm16: Data) -> Double {
        let frameCount = pcm16.count / bytesPerFrame
        guard frameCount > 0 else { return 0 }

        return pcm16.withUnsafeBytes { rawBuffer in
            var sumSquares = 0.0
            for index in 0..<frameCount {
                let rawValue = rawBuffer.loadUnaligned(
                    fromByteOffset: index * bytesPerFrame,
                    as: UInt16.self
                )
                let sample = Double(Int16(bitPattern: UInt16(littleEndian: rawValue))) / Double(Int16.max)
                sumSquares += sample * sample
            }

            let rms = sqrt(sumSquares / Double(frameCount))
            return min(max(pow(rms * 8, 0.72), 0), 1)
        }
    }
}

/// An asymmetric low-pass filter that keeps audio level meters readable.
///
/// The meter climbs slowly and falls quickly, so a syllable reads as one
/// sustained movement instead of a flicker, while silence drops the ring back to
/// rest almost immediately.
struct SpeechAudioLevelSmoother: Sendable, Equatable {
    /// The default weight applied to a level that is higher than the current one.
    static let defaultRiseFactor = 0.16
    /// The default weight applied to a level that is lower than the current one.
    static let defaultFallFactor = 0.58

    /// The weight applied when the incoming level is above the smoothed level.
    var riseFactor: Double
    /// The weight applied when the incoming level is at or below the smoothed level.
    var fallFactor: Double
    /// The current smoothed level, between `0` and `1`.
    private(set) var level: Double

    /// Creates a level smoother.
    ///
    /// - Parameters:
    ///   - level: The starting level.
    ///   - riseFactor: The weight applied to rising levels.
    ///   - fallFactor: The weight applied to falling levels.
    init(
        level: Double = 0,
        riseFactor: Double = SpeechAudioLevelSmoother.defaultRiseFactor,
        fallFactor: Double = SpeechAudioLevelSmoother.defaultFallFactor
    ) {
        self.level = level
        self.riseFactor = riseFactor
        self.fallFactor = fallFactor
    }

    /// Moves the smoothed level toward a newly measured level.
    ///
    /// - Parameter target: The newly measured level, between `0` and `1`.
    /// - Returns: The updated smoothed level.
    @discardableResult
    mutating func update(towards target: Double) -> Double {
        let smoothing = target > level ? riseFactor : fallFactor
        level += (target - level) * smoothing
        return level
    }

    /// Returns the weight this smoother would apply to a newly measured level.
    ///
    /// - Parameter target: The newly measured level.
    /// - Returns: Either ``riseFactor`` or ``fallFactor``.
    func smoothing(towards target: Double) -> Double {
        target > level ? riseFactor : fallFactor
    }

    /// Returns the smoothed level to rest.
    mutating func reset() {
        level = 0
    }
}

/// Byte-append helpers for the container headers SpeechKit writes.
///
/// The names carry a `speech` prefix so they never collide with a same-named
/// helper declared privately in another file of the module.
extension Data {
    /// Appends the ASCII bytes of a string, for fixed-width chunk identifiers.
    ///
    /// - Parameter string: An ASCII string such as `"RIFF"`.
    mutating func appendSpeechASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    /// Appends an integer in little-endian byte order.
    ///
    /// - Parameter value: The integer to append.
    mutating func appendSpeechLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
