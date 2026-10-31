import Foundation

enum SpeechRelayMP4 {
    // 6144 bits/channel for eight channels, plus 2048 bytes of FIL/DSE and
    // framing allowance. Keep identical to the Worker and syntax validator.
    static let maxAACSampleBytes: UInt64 = 8192
    static let maxHeaderBytes = 8 * 1024 * 1024
    private static let maxSafeInteger: UInt64 = 9_007_199_254_740_991
    private static let optionalBoxes: Set<String> = ["free", "skip", "udta", "meta", "wide"]

    struct Box {
        let type: String
        let payload: Int
        let end: Int
    }

    static func duration(_ file: URL) throws -> TimeInterval {
        try scan(file) { sample, config in
            guard SpeechRelayAACSyntax.validateSingleAccessUnit(sample: sample, config: config) else { throw unsupported() }
        }
    }

    // Apple decoders cannot open the review's packed-sample M4A. For local PCM
    // conversion only, unwrap proven access units to bounded ADTS packets. Never
    // forward this intermediate file. Container integrity checks still apply.
    static func unpackForConversion(_ file: URL, output: FileHandle,
                                    maximumDuration: TimeInterval, maximumBytes: Int64) throws -> Bool {
        var coreFrames: Int64 = 0
        var packed = false
        var written: Int64 = 0
        let rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        _ = try scan(file) { sample, config in
            let channel = config.channelConfiguration, sf = config.samplingFrequencyIndex
            // ADTS cannot carry an ASC-only PCE. Leave these to the normal decoder.
            guard channel > 0 else { throw unsupported() }
            let bytes = Array(sample)
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                guard let count = SpeechRelayAACSyntax.firstAccessUnitLength(in: bytes, offset: offset, config: config),
                      count > 0, count + 7 <= 8191 else { throw unsupported() }
                if count < bytes.count - offset { packed = true }
                coreFrames += 1024
                guard Double(coreFrames) / Double(rates[sf]) <= maximumDuration else { throw SpeechFailure(.audioTooLong) }
                written += Int64(count + 7)
                guard written <= maximumBytes else { throw SpeechFailure(.audioTooLarge) }
                let length = count + 7
                let header = Data([0xff, 0xf1, UInt8(0x40 | sf << 2 | channel >> 2),
                    UInt8((channel & 3) << 6 | length >> 11), UInt8((length >> 3) & 255),
                    UInt8((length & 7) << 5 | 0x1f), 0xfc])
                try output.write(contentsOf: header)
                try output.write(contentsOf: bytes[offset..<offset + count])
                offset += count
            }
        }
        return packed
    }

    private static func scan(_ file: URL,
                             sampleHandler: (Data, SpeechRelayAACSyntax.Config) throws -> Void) throws -> TimeInterval {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        guard length <= maxSafeInteger else { throw unsupported() }
        var offset: UInt64 = 0
        var moov: Data?
        var media: Range<UInt64>?
        var trailing: UInt64 = 0
        while offset < length {
            try Task.checkCancellation()
            try input.seek(toOffset: offset)
            let header = try read(input, count: 8)
            let type = String(decoding: header[4..<8], as: UTF8.self)
            var size = UInt64(try integer(header, 0, 4))
            var headerSize: UInt64 = 8
            if size == 1 {
                size = try integer(read(input, count: 8), 0, 8)
                headerSize = 16
            } else if size == 0 {
                guard type == "mdat" else { throw unsupported() }
                size = length - offset
            }
            guard size >= headerSize, size <= length - offset else { throw unsupported() }
            if offset == 0, type != "ftyp" { throw unsupported() }
            if media != nil {
                guard ["free", "skip", "udta"].contains(type) else { throw unsupported() }
                trailing += size
                guard trailing <= 65_536 else { throw unsupported() }
            }
            switch type {
            case "ftyp":
                guard offset == 0, size <= maxHeaderBytes, size >= headerSize + 8,
                      (size - headerSize) % 4 == 0 else { throw unsupported() }
            case "moov":
                guard moov == nil, media == nil, size <= maxHeaderBytes else { throw unsupported() }
                moov = try read(input, count: Int(size - headerSize))
            case "mdat":
                guard moov != nil, media == nil, size > headerSize else { throw unsupported() }
                media = (offset + headerSize)..<(offset + size)
            case "free", "skip", "udta", "meta", "wide": break
            default: throw unsupported()
            }
            offset += size
        }
        guard let moov, let media else { throw unsupported() }
        return try validate(moov, media: media, input: input, maximumFile: length, sampleHandler: sampleHandler)
    }

    private static func validate(_ data: Data, media: Range<UInt64>, input: FileHandle,
                                 maximumFile: UInt64, sampleHandler: (Data, SpeechRelayAACSyntax.Config) throws -> Void) throws -> TimeInterval {
        let root = try children(data, in: 0..<data.count, allowed: ["mvhd", "trak"])
        let track = try only("trak", in: root)
        let trackBoxes = try children(data, in: track.payload..<track.end, allowed: ["tkhd", "edts", "mdia"])
        let mdia = try only("mdia", in: trackBoxes)
        let mediaBoxes = try children(data, in: mdia.payload..<mdia.end, allowed: ["mdhd", "hdlr", "minf"])
        let handler = try only("hdlr", in: mediaBoxes)
        try full(data, box: handler, minimum: 24)
        guard String(decoding: data[handler.payload + 8..<handler.payload + 12], as: UTF8.self) == "soun" else {
            throw unsupported()
        }
        let header = try only("mdhd", in: mediaBoxes)
        guard header.end - header.payload >= 4, data[header.payload] <= 1 else { throw unsupported() }
        try full(data, box: header, minimum: data[header.payload] == 1 ? 36 : 24, version: data[header.payload])
        let scaleOffset = header.payload + (data[header.payload] == 1 ? 20 : 12)
        guard scaleOffset + 4 <= header.end else { throw unsupported() }
        let timescale = try integer(data, scaleOffset, 4)
        guard timescale > 0 else { throw unsupported() }
        let minf = try only("minf", in: mediaBoxes)
        let mediaInfo = try children(data, in: minf.payload..<minf.end, allowed: ["smhd", "dinf", "stbl"])
        let dinf = try only("dinf", in: mediaInfo)
        let dref = try only("dref", in: children(data, in: dinf.payload..<dinf.end, allowed: ["dref"], optional: false))
        try full(data, box: dref, minimum: 8)
        guard try integer(data, dref.payload + 4, 4) == 1 else { throw unsupported() }
        let reference = try only("url ", in: children(data, in: dref.payload + 8..<dref.end, allowed: ["url "], optional: false))
        guard reference.end - reference.payload == 4, try integer(data, reference.payload, 4) == 1 else { throw unsupported() }
        let table = try only("stbl", in: mediaInfo)
        let tables = try children(data, in: table.payload..<table.end,
            allowed: ["stsd", "stts", "stsc", "stsz", "stco", "co64", "sgpd", "sbgp"])
        let description = try only("stsd", in: tables)
        try full(data, box: description, minimum: 8)
        guard try integer(data, description.payload, 4) == 0,
              try integer(data, description.payload + 4, 4) == 1 else { throw unsupported() }
        let entries = try boxes(data, in: description.payload + 8..<description.end)
        guard entries.count == 1 else { throw unsupported() }
        let entry = try only("mp4a", in: entries)
        guard entry.end - entry.payload >= 28, try integer(data, entry.payload + 6, 2) == 1,
              try integer(data, entry.payload + 8, 2) == 0 else { throw unsupported() }
        let esds = try only("esds", in: children(data, in: entry.payload + 28..<entry.end, allowed: ["esds", "btrt", "sbtd"]))
        guard esds.end - esds.payload >= 4, try integer(data, esds.payload, 4) == 0 else { throw unsupported() }
        let aac = try aacConfig(data, in: esds.payload + 4..<esds.end)
        let sizesBox = try only("stsz", in: tables)
        guard sizesBox.end - sizesBox.payload >= 12, try integer(data, sizesBox.payload, 4) == 0 else { throw unsupported() }
        let fixed = try integer(data, sizesBox.payload + 4, 4)
        let count = try integer(data, sizesBox.payload + 8, 4)
        guard count > 0, count <= maximumFile,
              sizesBox.end - sizesBox.payload == 12 + (fixed == 0 ? Int(count) * 4 : 0) else { throw unsupported() }
        var sizes = [UInt64]()
        let total: UInt64
        if fixed > 0 {
            guard fixed <= maxAACSampleBytes else { throw unsupported() }
            let product = fixed.multipliedReportingOverflow(by: count)
            guard !product.overflow else { throw unsupported() }
            total = product.partialValue
        } else {
            sizes.reserveCapacity(Int(count))
            var sum: UInt64 = 0
            for index in 0..<Int(count) {
                if index % 4096 == 0 { try Task.checkCancellation() }
                let size = try integer(data, sizesBox.payload + 12 + index * 4, 4)
                guard size > 0, size <= maxAACSampleBytes else { throw unsupported() }
                sizes.append(size)
                sum += size
            }
            total = sum
        }
        guard total <= maximumFile else { throw unsupported() }
        let timing = try rows(data, box: only("stts", in: tables), columns: 2)
        var timedCount: UInt64 = 0
        var ticks: UInt64 = 0
        for row in timing {
            guard row[0] > 0, row[1] > 0, row[0] <= count - min(count, timedCount) else { throw unsupported() }
            timedCount += row[0]
            let (sum, overflow) = ticks.addingReportingOverflow(row[0] * row[1])
            guard !overflow, sum <= maxSafeInteger else { throw unsupported() }
            ticks = sum
        }
        guard timedCount == count else { throw unsupported() }
        try validateEdits(data, root: root, track: trackBoxes, timescale: timescale, ticks: ticks)
        let mappings = try rows(data, box: only("stsc", in: tables), columns: 3)
        guard !mappings.isEmpty, mappings[0][0] == 1 else { throw unsupported() }
        let offsets = tables.filter { ["stco", "co64"].contains($0.type) }
        guard offsets.count == 1 else { throw unsupported() }
        let chunks = try rows(data, box: offsets[0], columns: 1, width: offsets[0].type == "co64" ? 8 : 4)
        guard !chunks.isEmpty, chunks.count <= count else { throw unsupported() }
        for index in mappings.indices {
            let row = mappings[index]
            guard row[0] <= chunks.count, row[1] > 0, row[1] <= count, row[2] == 1,
                  index == 0 || row[0] > mappings[index - 1][0] else { throw unsupported() }
        }
        var mapping = 0
        var sample = 0
        var ranges = [(bytes: Range<UInt64>, firstSample: Int, count: Int)]()
        for index in chunks.indices {
            try Task.checkCancellation()
            while mapping + 1 < mappings.count, mappings[mapping + 1][0] <= index + 1 { mapping += 1 }
            let chunkCount = Int(mappings[mapping][1])
            guard chunkCount <= Int(count) - sample else { throw unsupported() }
            let bytes = fixed > 0 ? fixed * UInt64(chunkCount) : sizes[sample..<sample + chunkCount].reduce(0, +)
            let start = chunks[index][0]
            guard start >= media.lowerBound, start <= media.upperBound, bytes <= media.upperBound - start else { throw unsupported() }
            ranges.append((start..<start + bytes, sample, chunkCount))
            sample += chunkCount
        }
        guard sample == count else { throw unsupported() }
        ranges.sort { $0.bytes.lowerBound < $1.bytes.lowerBound }
        for index in ranges.indices.dropFirst() {
            guard ranges[index].bytes.lowerBound >= ranges[index - 1].bytes.upperBound else { throw unsupported() }
        }
        guard media.upperBound - media.lowerBound >= total,
              media.upperBound - media.lowerBound - total <= 64 else { throw unsupported() }
        var position = media.lowerBound
        for range in ranges {
            try zeroPadding(input, in: position..<range.bytes.lowerBound)
            try input.seek(toOffset: range.bytes.lowerBound)
            for index in range.firstSample..<range.firstSample + range.count {
                try Task.checkCancellation()
                let size = fixed > 0 ? fixed : sizes[index]
                // Read one bounded sample, never the whole mdat or source file.
                let sample = try read(input, count: Int(size))
                try sampleHandler(sample, aac.syntax)
            }
            position = range.bytes.upperBound
        }
        try zeroPadding(input, in: position..<media.upperBound)
        return max(Double(count) * 1024 / Double(aac.rate), Double(ticks) / Double(timescale))
    }

    private static func validateEdits(_ data: Data, root: [Box], track: [Box], timescale: UInt64, ticks: UInt64) throws {
        guard let edits = track.first(where: { $0.type == "edts" }) else { return }
        let list = try only("elst", in: children(data, in: edits.payload..<edits.end, allowed: ["elst"], optional: false))
        guard list.end - list.payload >= 8, data[list.payload] <= 1 else { throw unsupported() }
        let version = data[list.payload]
        try full(data, box: list, minimum: 8, version: version)
        let count = try integer(data, list.payload + 4, 4)
        let width = version == 1 ? 8 : 4
        guard count <= 1, list.end - list.payload == 8 + Int(count) * (width * 2 + 4) else { throw unsupported() }
        let movie = try only("mvhd", in: root)
        guard movie.end - movie.payload >= 4, data[movie.payload] <= 1 else { throw unsupported() }
        let movieVersion = data[movie.payload]
        try full(data, box: movie, minimum: movieVersion == 1 ? 112 : 100, version: movieVersion)
        let movieScale = try integer(data, movie.payload + (movieVersion == 1 ? 20 : 12), 4)
        guard movieScale > 0 else { throw unsupported() }
        guard count == 1 else { return }
        let segment = try rawInteger(data, list.payload + 8, width)
        let mediaTime = try rawInteger(data, list.payload + 8 + width, width)
        guard mediaTime < (UInt64(1) << (width * 8 - 1)), mediaTime <= ticks,
              try integer(data, list.payload + 8 + width * 2, 4) == 0x0001_0000 else { throw unsupported() }
        let product = segment.multipliedFullWidth(by: timescale)
        guard product.high < movieScale else { throw unsupported() }
        let duration = movieScale.dividingFullWidth(product)
        let remaining = ticks - mediaTime
        guard duration.quotient <= remaining,
              duration.remainder == 0 || duration.quotient < remaining else { throw unsupported() }
    }

    private static func zeroPadding(_ input: FileHandle, in range: Range<UInt64>) throws {
        guard !range.isEmpty else { return }
        try Task.checkCancellation()
        try input.seek(toOffset: range.lowerBound)
        guard try read(input, count: Int(range.count)).allSatisfy({ $0 == 0 }) else { throw unsupported() }
    }

    private static func full(_ data: Data, box: Box, minimum: Int, version: UInt8 = 0) throws {
        guard box.end - box.payload >= minimum,
              try integer(data, box.payload, 4) == UInt64(version) << 24 else { throw unsupported() }
    }

    private static func children(_ data: Data, in range: Range<Int>, allowed: Set<String>, optional: Bool = true) throws -> [Box] {
        let result = try boxes(data, in: range)
        var found = Set<String>()
        for box in result {
            guard allowed.contains(box.type) || (optional && optionalBoxes.contains(box.type)) else { throw unsupported() }
            if !optionalBoxes.contains(box.type), !found.insert(box.type).inserted { throw unsupported() }
        }
        return result
    }

    private static func boxes(_ data: Data, in range: Range<Int>) throws -> [Box] {
        guard range.lowerBound >= 0, range.upperBound <= data.count, range.lowerBound <= range.upperBound else { throw unsupported() }
        var result = [Box]()
        var offset = range.lowerBound
        while offset < range.upperBound {
            try Task.checkCancellation()
            guard range.upperBound - offset >= 8 else { throw unsupported() }
            var size = try integer(data, offset, 4)
            var header = 8
            if size == 1 {
                guard range.upperBound - offset >= 16 else { throw unsupported() }
                size = try integer(data, offset + 8, 8)
                header = 16
            }
            guard size >= header, size <= range.upperBound - offset else { throw unsupported() }
            result.append(Box(type: String(decoding: data[offset + 4..<offset + 8], as: UTF8.self),
                payload: offset + header, end: offset + Int(size)))
            offset += Int(size)
        }
        return result
    }

    private static func only(_ type: String, in boxes: [Box]) throws -> Box {
        let matches = boxes.filter { $0.type == type }
        guard matches.count == 1 else { throw unsupported() }
        return matches[0]
    }

    private static func rows(_ data: Data, box: Box, columns: Int, width: Int = 4) throws -> [[UInt64]] {
        guard box.end - box.payload >= 8, try integer(data, box.payload, 4) == 0 else { throw unsupported() }
        let count = try integer(data, box.payload + 4, 4)
        guard count > 0, count <= maxHeaderBytes / (columns * width),
              box.end - box.payload == 8 + Int(count) * columns * width else { throw unsupported() }
        return try (0..<Int(count)).map { row in
            if row % 4096 == 0 { try Task.checkCancellation() }
            return try (0..<columns).map { try integer(data, box.payload + 8 + (row * columns + $0) * width, width) }
        }
    }

    private static func aacConfig(_ data: Data, in range: Range<Int>) throws -> (rate: UInt64, syntax: SpeechRelayAACSyntax.Config) {
        var cursor = range.lowerBound
        func descriptor(_ tag: UInt8, end: Int) throws -> Range<Int> {
            guard cursor < end, data[cursor] == tag else { throw unsupported() }
            cursor += 1
            var length = 0
            var terminated = false
            for _ in 0..<4 {
                guard cursor < end else { throw unsupported() }
                let byte = data[cursor]
                cursor += 1
                length = length * 128 + Int(byte & 127)
                if byte & 128 == 0 { terminated = true; break }
            }
            guard terminated, length <= end - cursor else { throw unsupported() }
            return cursor..<cursor + length
        }
        let es = try descriptor(3, end: range.upperBound)
        guard es.count >= 3 else { throw unsupported() }
        guard es.upperBound == range.upperBound, data[cursor + 2] == 0 else { throw unsupported() }
        cursor += 3
        let decoder = try descriptor(4, end: es.upperBound)
        guard decoder.count >= 13, data[cursor] == 0x40, data[cursor + 1] >> 2 == 5,
              data[cursor + 1] & 2 == 0 else { throw unsupported() }
        cursor += 13
        let config = try descriptor(5, end: decoder.upperBound)
        guard config.upperBound == decoder.upperBound else { throw unsupported() }
        cursor = decoder.upperBound
        let sl = try descriptor(6, end: es.upperBound)
        guard sl.upperBound == es.upperBound, sl.count == 1, data[sl.lowerBound] == 2 else { throw unsupported() }
        var bit = config.lowerBound * 8
        func bits(_ count: Int) throws -> UInt64 {
            guard bit + count <= config.upperBound * 8 else { throw unsupported() }
            var value: UInt64 = 0
            for _ in 0..<count {
                value = value * 2 + UInt64((data[bit / 8] >> (7 - bit % 8)) & 1)
                bit += 1
            }
            return value
        }
        let rates: [UInt64] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        func frequency() throws -> UInt64 {
            let index = try bits(4)
            if index == 15 {
                let rate = try bits(24)
                guard rate > 0, rate <= 192000 else { throw unsupported() }
                return rate
            }
            guard index < rates.count else { throw unsupported() }
            return rates[Int(index)]
        }
        let object = try bits(5)
        guard [2, 5, 29].contains(object) else { throw unsupported() }
        let rate = try frequency()
        let channelConfig = try bits(4)
        guard channelConfig <= 7 else { throw unsupported() }
        if object == 5 || object == 29 {
            guard try frequency() >= rate, try bits(5) == 2 else { throw unsupported() }
        }
        let frameLengthFlag = try bits(1) != 0
        guard !frameLengthFlag else { throw unsupported() }
        if try bits(1) != 0 { _ = try bits(14) }
        let hasExtension = try bits(1) != 0
        var programConfig: SpeechRelayAACSyntax.ProgramConfig?
        if channelConfig == 0 {
            _ = try bits(4)
            guard try bits(2) == 1 else { throw unsupported() }
            let frequencyIndex = try bits(4)
            guard frequencyIndex < rates.count, rates[Int(frequencyIndex)] == rate else { throw unsupported() }
            let front = try bits(4), side = try bits(4), back = try bits(4)
            let lfe = try bits(2), associated = try bits(3), coupling = try bits(4)
            if try bits(1) != 0 { _ = try bits(4) }
            if try bits(1) != 0 { _ = try bits(4) }
            if try bits(1) != 0 { _ = try bits(3) }
            guard coupling == 0 else { throw unsupported() }
            func elements(_ count: UInt64) throws -> [SpeechRelayAACSyntax.Element] {
                try (0..<count).map { _ in
                    let type: SpeechRelayAACSyntax.Element.Kind = try bits(1) != 0 ? .cpe : .sce
                    return .init(type: type, tag: Int(try bits(4)))
                }
            }
            let frontElements = try elements(front), sideElements = try elements(side), backElements = try elements(back)
            let lfeElements: [SpeechRelayAACSyntax.Element] = try (0..<lfe).map { _ in .init(type: .lfe, tag: Int(try bits(4))) }
            programConfig = .init(front: frontElements, side: sideElements, back: backElements, lfe: lfeElements)
            let channels = (frontElements + sideElements + backElements + lfeElements).reduce(0) { $0 + ($1.type == .cpe ? 2 : 1) }
            guard channels > 0, channels <= 8 else { throw unsupported() }
            for _ in 0..<associated { _ = try bits(4) }
            while bit % 8 != 0 { guard try bits(1) == 0 else { throw unsupported() } }
            let comment = try bits(8)
            for _ in 0..<comment { _ = try bits(8) }
        }
        if hasExtension, try bits(1) != 0 { throw unsupported() }
        if object == 2, config.upperBound * 8 - bit >= 16 {
            guard try bits(11) == 0x2b7, try bits(5) == 5 else { throw unsupported() }
            if try bits(1) != 0, try frequency() < rate { throw unsupported() }
            if config.upperBound * 8 - bit >= 12 {
                guard try bits(11) == 0x548 else { throw unsupported() }
                _ = try bits(1)
            }
        }
        while bit < config.upperBound * 8 { guard try bits(1) == 0 else { throw unsupported() } }
        guard let frequencyIndex = rates.firstIndex(of: rate) else { throw unsupported() }
        return (rate, .init(objectType: 2, samplingFrequencyIndex: frequencyIndex,
            channelConfiguration: Int(channelConfig), frameLengthFlag: frameLengthFlag, programConfig: programConfig))
    }

    private static func integer(_ data: Data, _ offset: Int, _ width: Int) throws -> UInt64 {
        let value = try rawInteger(data, offset, width)
        guard value <= maxSafeInteger else { throw unsupported() }
        return value
    }

    private static func rawInteger(_ data: Data, _ offset: Int, _ width: Int) throws -> UInt64 {
        guard offset >= 0, offset <= data.count, width <= data.count - offset else { throw unsupported() }
        return data[offset..<offset + width].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    private static func read(_ input: FileHandle, count: Int) throws -> Data {
        let data = try input.read(upToCount: count) ?? Data()
        guard data.count == count else { throw unsupported() }
        return data
    }

    private static func unsupported() -> SpeechFailure { SpeechFailure(.unsupportedMediaType) }
}
