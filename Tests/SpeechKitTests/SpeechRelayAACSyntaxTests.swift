import Foundation
import Testing
@testable import SpeechKit

private struct AACVectorConfig: Decodable {
    let objectType: Int
    let samplingFrequencyIndex: Int
    let channelConfiguration: Int
    let frameLengthFlag: Bool
    let programConfig: Program?
    struct Item: Decodable { let type: SpeechRelayAACSyntax.Element.Kind; let tag: Int }
    struct Program: Decodable { let front: [Item]; let side: [Item]; let back: [Item]; let lfe: [Item] }
    var value: SpeechRelayAACSyntax.Config {
        func elements(_ items: [Item]) -> [SpeechRelayAACSyntax.Element] { items.map { .init(type: $0.type, tag: $0.tag) } }
        let p = programConfig.map { SpeechRelayAACSyntax.ProgramConfig(front: elements($0.front), side: elements($0.side), back: elements($0.back), lfe: elements($0.lfe)) }
        return .init(objectType: objectType, samplingFrequencyIndex: samplingFrequencyIndex,
                     channelConfiguration: channelConfiguration, frameLengthFlag: frameLengthFlag, programConfig: p)
    }
}
private struct AACVector: Sendable, CustomTestStringConvertible {
    let name: String
    let sample: Data
    let config: SpeechRelayAACSyntax.Config
    let ok: Bool
    var testDescription: String { name }
}
private enum AACVectors {
    struct Stream: Decodable { let name: String; let config: AACVectorConfig; let samples: [String] }
    struct Real: Decodable { let vectors: [Stream]; let rejected: [Stream] }
    struct Synthetic: Decodable {
        struct Case: Decodable { let name: String; let sample: String; let config: AACVectorConfig; let ok: Bool }
        let cases: [Case]
    }
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("AACSyntaxVectors")
    static let real = try! JSONDecoder().decode(Real.self, from: Data(contentsOf: directory.appendingPathComponent("real.json")))
    static let synthetic = try! JSONDecoder().decode(Synthetic.self, from: Data(contentsOf: directory.appendingPathComponent("synthetic.json")))
    static let cases: [AACVector] = real.vectors.flatMap { stream in
        stream.samples.enumerated().map { index, sample in
            AACVector(name: "\(stream.name)-frame-\(index)", sample: Data(base64Encoded: sample)!, config: stream.config.value, ok: true)
        }
    } + real.rejected.flatMap { stream in
        stream.samples.map { AACVector(name: stream.name, sample: Data(base64Encoded: $0)!, config: stream.config.value, ok: false) }
    } + synthetic.cases.map { AACVector(name: $0.name, sample: Data(base64Encoded: $0.sample)!, config: $0.config.value, ok: $0.ok) }
}
struct SpeechRelayAACSyntaxTests {
    @Test("Shared real frames and exhaustive syntax cases", arguments: AACVectors.cases)
    fileprivate func sharedVectors(_ v: AACVector) {
        #expect(SpeechRelayAACSyntax.validateSingleAccessUnit(sample: v.sample, config: v.config) == v.ok)
        // Exercise both public byte representations, including a nonzero Data startIndex.
        let prefixed = Data([0xff, 0xff]) + v.sample
        #expect(SpeechRelayAACSyntax.validateSingleAccessUnit(sample: prefixed.dropFirst(2), config: v.config) == v.ok)
        #expect(SpeechRelayAACSyntax.validateSingleAccessUnit(sample: Array(v.sample), config: v.config) == v.ok)
    }
    @Test func rejectsRealFrameConcatenationTruncationAndTrailingBytes() {
        for stream in AACVectors.real.vectors {
            for value in stream.samples {
                let sample = Data(base64Encoded: value)!, c = stream.config.value
                #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample + sample, config: c))
                let packed = Array(sample + sample)
                if packed.count <= 8192 {
                    #expect(SpeechRelayAACSyntax.firstAccessUnitLength(in: packed, offset: 0, config: c) == sample.count)
                    #expect(SpeechRelayAACSyntax.firstAccessUnitLength(in: packed, offset: sample.count, config: c) == sample.count)
                }
                #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample.dropLast(), config: c))
                #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample + Data([0]), config: c))
            }
        }
    }
    @Test func deterministicRandomInputsNeverCrashOrHang() {
        var seed: UInt32 = 0x12345678
        func random() -> UInt32 { seed = seed &* 1664525 &+ 1013904223; return seed }
        for _ in 0..<5000 {
            let count = Int(random() % 1024)
            let bytes = (0..<count).map { _ in UInt8(random() >> 24) }
            let c = SpeechRelayAACSyntax.Config(objectType: 2, samplingFrequencyIndex: Int(random() % 13),
                                                channelConfiguration: Int(random() % 8), frameLengthFlag: false)
            #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: bytes, config: c))
        }
        #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: [UInt8](repeating: 0, count: 8193), config: AACVectors.real.vectors[0].config.value))
    }
    @Test func rejectsUnboundedIntegerConfiguration() {
        let sample = Data(base64Encoded: AACVectors.real.vectors[0].samples[0])!
        for extreme in [Int.min, Int.max, -1, 99] {
            #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample, config: .init(objectType: 2, samplingFrequencyIndex: extreme, channelConfiguration: 1, frameLengthFlag: false)))
            #expect(!SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample, config: .init(objectType: 2, samplingFrequencyIndex: 3, channelConfiguration: extreme, frameLengthFlag: false)))
        }
    }
}
