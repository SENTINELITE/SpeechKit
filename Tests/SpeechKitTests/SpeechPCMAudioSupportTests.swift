import Foundation
import Testing
@testable import SpeechKit

@Suite("Shared PCM audio support")
struct SpeechPCMAudioSupportTests {
    // MARK: - WAV header

    @Test("WAV header describes 24 kHz 16-bit mono audio")
    func wavHeaderFieldsAt24kHz() throws {
        let pcmData = Data([0x01, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0x10, 0x20])
        let wav = SpeechPCMAudioSupport.makeWAVData(pcmData: pcmData, sampleRate: 24000)

        #expect(wav.count == 44 + pcmData.count)
        #expect(ascii(wav, 0, 4) == "RIFF")
        #expect(littleEndianUInt32(wav, 4) == UInt32(36 + pcmData.count))
        #expect(ascii(wav, 8, 4) == "WAVE")
        #expect(ascii(wav, 12, 4) == "fmt ")
        #expect(littleEndianUInt32(wav, 16) == 16)
        #expect(littleEndianUInt16(wav, 20) == 1)
        #expect(littleEndianUInt16(wav, 22) == 1)
        #expect(littleEndianUInt32(wav, 24) == 24000)
        #expect(littleEndianUInt32(wav, 28) == 48000)
        #expect(littleEndianUInt16(wav, 32) == 2)
        #expect(littleEndianUInt16(wav, 34) == 16)
        #expect(ascii(wav, 36, 4) == "data")
        #expect(littleEndianUInt32(wav, 40) == UInt32(pcmData.count))
        #expect(wav.suffix(pcmData.count) == pcmData)
    }

    @Test("WAV header byte rate follows the sample rate")
    func wavHeaderByteRateAt16kHz() {
        let wav = SpeechPCMAudioSupport.makeWAVData(pcmData: Data(count: 32), sampleRate: 16000)

        #expect(littleEndianUInt32(wav, 24) == 16000)
        #expect(littleEndianUInt32(wav, 28) == 32000)
        #expect(littleEndianUInt32(wav, 40) == 32)
    }

    @Test("WAV data for an empty payload is a bare header")
    func wavHeaderForEmptyPayload() {
        let wav = SpeechPCMAudioSupport.makeWAVData(pcmData: Data(), sampleRate: 24000)

        #expect(wav.count == 44)
        #expect(littleEndianUInt32(wav, 4) == 36)
        #expect(littleEndianUInt32(wav, 40) == 0)
    }

    // MARK: - Level metering

    @Test("Silence meters as zero")
    func normalizedLevelForSilence() {
        #expect(SpeechPCMAudioSupport.normalizedLevel(int16Samples: [Int16](repeating: 0, count: 480)) == 0)
        #expect(SpeechPCMAudioSupport.normalizedLevel(pcm16: Data(count: 960)) == 0)
    }

    @Test("An empty block meters as zero")
    func normalizedLevelForEmptyBlock() {
        #expect(SpeechPCMAudioSupport.normalizedLevel(int16Samples: []) == 0)
        #expect(SpeechPCMAudioSupport.normalizedLevel(pcm16: Data()) == 0)
    }

    @Test("Full-scale audio meters as one")
    func normalizedLevelForFullScale() {
        let positive = [Int16](repeating: Int16.max, count: 256)
        let alternating = (0..<256).map { $0.isMultiple(of: 2) ? Int16.max : -Int16.max }

        #expect(SpeechPCMAudioSupport.normalizedLevel(int16Samples: positive) == 1)
        #expect(SpeechPCMAudioSupport.normalizedLevel(int16Samples: alternating) == 1)
    }

    @Test("A quiet block meters between zero and one")
    func normalizedLevelForQuietBlock() {
        let quiet = [Int16](repeating: Int16(Double(Int16.max) * 0.02), count: 256)
        let level = SpeechPCMAudioSupport.normalizedLevel(int16Samples: quiet)

        #expect(level > 0)
        #expect(level < 1)
    }

    @Test("Byte and sample metering agree")
    func normalizedLevelParityBetweenBytesAndSamples() {
        let samples: [Int16] = [0, 1200, -3400, 9000, -12000, 200, -50, 32000]
        var bytes = Data()
        for sample in samples {
            bytes.appendSpeechLittleEndian(sample)
        }

        let fromSamples = SpeechPCMAudioSupport.normalizedLevel(int16Samples: samples)
        let fromBytes = SpeechPCMAudioSupport.normalizedLevel(pcm16: bytes)

        #expect(abs(fromSamples - fromBytes) < 0.000001)
    }

    @Test("Byte metering ignores a trailing odd byte")
    func normalizedLevelIgnoresTrailingOddByte() {
        let samples: [Int16] = [4000, -4000, 8000, -8000]
        var bytes = Data()
        for sample in samples {
            bytes.appendSpeechLittleEndian(sample)
        }
        var oddBytes = bytes
        oddBytes.append(0x7F)

        #expect(SpeechPCMAudioSupport.normalizedLevel(pcm16: oddBytes)
            == SpeechPCMAudioSupport.normalizedLevel(pcm16: bytes))
    }

    // MARK: - Level smoothing

    @Test("The level meter rises more slowly than it falls")
    func smootherRisesSlowerThanItFalls() {
        var rising = SpeechAudioLevelSmoother()
        let risen = rising.update(towards: 1)

        var falling = SpeechAudioLevelSmoother(level: 1)
        let fallen = falling.update(towards: 0)

        let riseDistance = risen - 0
        let fallDistance = 1 - fallen

        #expect(riseDistance < fallDistance)
        #expect(abs(risen - SpeechAudioLevelSmoother.defaultRiseFactor) < 0.000001)
        #expect(abs(fallen - (1 - SpeechAudioLevelSmoother.defaultFallFactor)) < 0.000001)
    }

    @Test("The smoother reports the weight it will apply")
    func smootherReportsSmoothingWeight() {
        let smoother = SpeechAudioLevelSmoother(level: 0.5)

        #expect(smoother.smoothing(towards: 0.9) == SpeechAudioLevelSmoother.defaultRiseFactor)
        #expect(smoother.smoothing(towards: 0.1) == SpeechAudioLevelSmoother.defaultFallFactor)
        #expect(smoother.smoothing(towards: 0.5) == SpeechAudioLevelSmoother.defaultFallFactor)
    }

    @Test("Repeated updates approach the measured level without overshooting")
    func smootherConvergesOnTheTarget() {
        var smoother = SpeechAudioLevelSmoother()
        for _ in 0..<64 {
            smoother.update(towards: 0.8)
        }

        #expect(smoother.level < 0.8)
        #expect(smoother.level > 0.79)
    }

    @Test("Resetting returns the level to rest")
    func smootherResets() {
        var smoother = SpeechAudioLevelSmoother(level: 0.75)
        smoother.reset()

        #expect(smoother.level == 0)
    }

    // MARK: - Helpers

    private func ascii(_ data: Data, _ offset: Int, _ count: Int) -> String {
        String(decoding: data[data.startIndex + offset..<data.startIndex + offset + count], as: UTF8.self)
    }

    private func littleEndianUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
    }

    private func littleEndianUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        data.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
    }
}
