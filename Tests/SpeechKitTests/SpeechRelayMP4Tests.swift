import Foundation
import Testing
@testable import SpeechKit

struct SpeechRelayMP4Tests {
    @Test(arguments: ["", "co64", "fixed-sizes", "lying-durations", "sbr", "ps", "trailing", "slack",
        "empty-edits", "single-edit", "edit-v1", "open-mdat", "internal-slack", "surround"])
    func acceptsMeterableSubset(kind: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.fixture(kind).write(to: file)
        let duration = try SpeechRelayMP4.duration(file)
        #expect(abs(duration - 0.128) < 0.000001)
    }

    @Test func chargesLargerDurationCrossCheck() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.fixture("long-stts").write(to: file)
        #expect(try SpeechRelayMP4.duration(file) == 0.256)
    }

    @Test(arguments: ["video", "extra-track", "alac", "moov-last", "fragment", "mvex", "multi-mdat",
        "too-much-slack", "overlap", "offset-before", "offset-after", "truncated", "stts-count",
        "trailing-large", "extra-stsd", "oversize-moov", "esds-type", "zero-timescale", "stsc-bad",
        "missing-stco", "duplicate-moov", "trailing-unknown", "truncated-esds", "sample-count", "box-overflow",
        "nonzero-slack", "odd-ftyp", "unknown-table", "unknown-track", "unknown-media", "unknown-minf", "unknown-entry",
        "duplicate-table", "repeated-edits", "duplicate-edits", "duplicate-elst", "empty-edts", "edit-negative", "edit-rate",
        "edit-overrun", "edit-rounding-overrun", "edit-v1-negative", "edit-v1-overrun", "edit-v1-rate", "edit-v1-overflow",
        "unknown-edit", "bad-reference", "bad-data-reference", "handler-flags", "mdhd-flags", "no-sl", "es-flags",
        "decoder-flags", "config-padding", "zero-child", "merged-samples", "oversize-sample", "frame-960"])
    func refusesUnmeterableOrUnreferencedAudio(kind: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: file) }
        try Self.fixture(kind).write(to: file)
        #expect(throws: SpeechFailure(.unsupportedMediaType)) { try SpeechRelayMP4.duration(file) }
    }

    @Test func truncatedHeadersNeverTrap() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Self.fixture("")
        for length in 0..<data.count {
            try data.prefix(length).write(to: file)
            #expect(throws: SpeechFailure(.unsupportedMediaType)) { try SpeechRelayMP4.duration(file) }
        }
    }

    static func realFixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("MP4Fixtures").appendingPathComponent(name)
    }

    @Test(arguments: ["aac.m4a", "aac.mp4", "aac-faststart.m4a", "he-aac.m4a", "surround.m4a"])
    func realFilesPassThroughUnchanged(name: String) async throws {
        let file = Self.realFixture(name)
        let original = try Data(contentsOf: file)
        let expected = name == "he-aac.m4a" ? 50.0 * 1024 / 24000 :
            name == "surround.m4a" ? 95.0 * 1024 / 48000 : 96.0 * 1024 / 48000
        #expect(try SpeechRelayMP4.duration(file) == expected)
        for enabled in [true, false] {
            let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .openAI, optimizeUploads: enabled)
            #expect(prepared.file == file && prepared.directory == nil)
            #expect(try Data(contentsOf: prepared.file) == original)
            prepared.remove()
        }
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func rejectsRealMergedAccessUnits() throws {
        #expect(throws: SpeechFailure(.unsupportedMediaType)) {
            try SpeechRelayMP4.duration(Self.realFixture("merged-samples.m4a"))
        }
    }

    static func fixture(_ kind: String) -> Data {
        func number(_ value: UInt64, _ width: Int = 4) -> Data {
            Data((0..<width).map { UInt8(truncatingIfNeeded: value >> ((width - 1 - $0) * 8)) })
        }
        func box(_ type: String, _ content: Data) -> Data { number(UInt64(content.count + 8)) + Data(type.utf8) + content }
        func full(_ type: String, _ content: Data) -> Data { box(type, number(0) + content) }
        func descriptor(_ tag: UInt8, _ content: Data) -> Data { Data([tag, UInt8(content.count)]) + content }
        let ftyp = box("ftyp", Data("M4A ".utf8) + number(0) + (kind == "odd-ftyp" ? Data([0]) : Data()))
        var config: Data
        if kind == "sbr" || kind == "ps" {
            var bits = String(kind == "ps" ? 29 : 5, radix: 2)
            bits = String(repeating: "0", count: 5 - bits.count) + bits + "1000" + "0001" + "0101" + "00010" + "000"
            while bits.count % 8 != 0 { bits += "0" }
            config = Data(stride(from: 0, to: bits.count, by: 8).map { index in
                UInt8(bits.dropFirst(index).prefix(8), radix: 2)!
            })
        } else { config = Data([kind == "esds-type" ? 0x1c : 0x14, kind == "surround" ? 0x38 : kind == "config-padding" ? 0x09 : kind == "frame-960" ? 0x0c : 0x08]) }
        let decoder = descriptor(4, Data([0x40, kind == "decoder-flags" ? 0x17 : 0x15]) + Data(repeating: 0, count: 11) + descriptor(5, config))
        let sl = kind == "no-sl" ? Data() : descriptor(6, Data([2]))
        var esds = full("esds", descriptor(3, Data([0, 1, kind == "es-flags" ? 1 : 0]) + decoder + sl))
        if kind == "truncated-esds" { esds.removeLast() }
        let sampleEntry = box(kind == "alac" ? "alac" : "mp4a", Data(repeating: 0, count: 6) +
            number(kind == "bad-data-reference" ? 2 : 1, 2) + Data(repeating: 0, count: 20) + esds +
            (kind == "unknown-entry" ? box("zzzz", Data()) : Data()))
        let stsd = full("stsd", number(1) + sampleEntry + (kind == "extra-stsd" ? sampleEntry : Data()))
        // Valid silent raw_data_block syntax for mono, or standard 7.1 elements.
        var sampleBits = ""
        func element(_ id: String, _ tag: Int, pair: Bool = false) {
            let tagBits = String(tag, radix: 2)
            sampleBits += id + String(repeating: "0", count: 4 - tagBits.count) + tagBits
            if pair { sampleBits += "0" } // independent channel windows
            sampleBits += String(repeating: "0", count: pair ? 44 : 22)
        }
        element("000", 0)
        if kind == "surround" {
            for tag in 0..<3 { element("001", tag, pair: true) }
            element("011", 0)
        }
        sampleBits += "111"
        while sampleBits.count % 8 != 0 { sampleBits += "0" }
        var packet = Data(stride(from: 0, to: sampleBits.count, by: 8).map { UInt8(sampleBits.dropFirst($0).prefix(8), radix: 2)! })
        if kind == "merged-samples" { packet += packet }
        if kind == "oversize-sample" { packet = Data(repeating: 0, count: 8193) }
        let sampleSize = UInt64(packet.count)
        let stsz = full("stsz", number(kind == "fixed-sizes" ? sampleSize : 0) + number(kind == "sample-count" ? UInt64.max >> 32 : 2) +
            (kind == "fixed-sizes" ? Data() : number(sampleSize) + number(sampleSize)))
        let stts = full("stts", number(1) + number(kind == "stts-count" ? 1 : 2) + number(kind == "long-stts" ? 2048 : 1024))
        let stsc = full("stsc", number(1) + number(kind == "stsc-bad" ? 2 : 1) + number(kind == "overlap" ? 1 : 2) + number(1))
        func moov(_ start: UInt64) -> Data {
            let position = kind == "offset-before" ? (start > 0 ? start - 1 : 0) : kind == "offset-after" ? start + 9 : start + (kind == "internal-slack" ? 4 : 0)
            let chunks = kind == "co64" ? full("co64", number(1) + number(position, 8)) :
                full("stco", number(kind == "overlap" ? 2 : 1) + number(position) + (kind == "overlap" ? number(position) : Data()))
            let tableExtra = kind == "unknown-table" ? box("zzzz", Data()) : kind == "duplicate-table" ? stts :
                kind == "zero-child" ? number(0) + Data("free".utf8) : Data()
            let stbl = box("stbl", stsd + stsz + stts + stsc + (kind == "missing-stco" ? Data() : chunks) + tableExtra)
            let mdhd = box("mdhd", number(kind == "mdhd-flags" ? 1 : 0) + number(0) + number(0) + number(kind == "zero-timescale" ? 0 : 16000) + number(1) + number(0))
            let hdlr = box("hdlr", number(kind == "handler-flags" ? 1 : 0) + number(0) + Data((kind == "video" ? "vide" : "soun").utf8) + Data(repeating: 0, count: 12))
            let reference = box("dinf", full("dref", number(1) + box("url ", number(kind == "bad-reference" ? 0 : 1))))
            let minf = box("minf", reference + stbl + (kind == "unknown-minf" ? box("zzzz", Data()) : Data()))
            var edits = Data()
            if kind.contains("edit") || kind == "empty-edts" || kind == "duplicate-elst" {
                let wide = kind.contains("v1")
                let width = wide ? 8 : 4
                let duration: UInt64 = kind.contains("overflow") ? .max : kind == "edit-rounding-overrun" ? 128 : kind.contains("overrun") ? 129 : 128
                let time: UInt64 = kind.contains("negative") ? (wide ? UInt64.max : UInt64(UInt32.max)) : kind == "edit-rounding-overrun" ? 3 : 0
                let entry = number(duration, width) + number(time, width) + number(kind.contains("rate") ? 0 : 0x0001_0000)
                let count = kind == "empty-edits" ? 0 : kind == "repeated-edits" ? 2 : 1
                let list = box("elst", number(wide ? 0x0100_0000 : 0) + number(UInt64(count)) +
                    (count == 0 ? Data() : entry) + (count == 2 ? entry : Data()))
                edits = box("edts", kind == "empty-edts" ? Data() : list +
                    (kind == "duplicate-elst" ? list : Data()) + (kind == "unknown-edit" ? box("zzzz", Data()) : Data()))
                if kind == "duplicate-edits" { edits += edits }
            }
            let mdia = box("mdia", mdhd + hdlr + minf + (kind == "unknown-media" ? box("zzzz", Data()) : Data()))
            let trak = box("trak", edits + mdia + (kind == "unknown-track" ? box("zzzz", Data()) : Data()))
            let movieScale: UInt64 = kind == "edit-rounding-overrun" ? 1001 : 1000
            let mvhd = full("mvhd", number(0) + number(0) + number(movieScale) + Data(repeating: 0, count: 84))
            return box("moov", mvhd + trak +
                (kind == "extra-track" ? trak : Data()) + (kind == "mvex" ? box("mvex", Data()) : Data()))
        }
        let header = moov(UInt64(ftyp.count + moov(0).count + 8))
        let payload = (kind == "internal-slack" ? Data(repeating: 0, count: 4) : Data()) + (packet + packet) +
            (kind == "nonzero-slack" ? Data([1, 2, 3, 4]) : Data(repeating: 0, count: kind == "too-much-slack" ? 65 : kind == "slack" ? 64 : 0))
        let mdat = kind == "open-mdat" ? number(0) + Data("mdat".utf8) + payload : box("mdat", payload)
        var result = ftyp + header + mdat
        switch kind {
        case "moov-last": result = ftyp + mdat + header
        case "fragment": result = ftyp + header + box("moof", Data()) + mdat
        case "multi-mdat": result += mdat
        case "duplicate-moov": result = ftyp + header + header + mdat
        case "trailing": result += box("free", Data(repeating: 0, count: 32))
        case "trailing-large": result += box("free", Data(repeating: 0, count: 65_536))
        case "trailing-unknown": result += box("uuid", Data())
        case "oversize-moov": result = ftyp + box("moov", Data(repeating: 0, count: SpeechRelayMP4.maxHeaderBytes)) + mdat
        case "box-overflow": result = ftyp + number(1) + Data("moov".utf8) + number(UInt64.max, 8)
        case "truncated": result.removeLast()
        default: break
        }
        return result
    }
}
