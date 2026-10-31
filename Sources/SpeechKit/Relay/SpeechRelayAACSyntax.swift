import Foundation

/// AAC-LC syntax only, ISO/IEC 14496-3 sections 4.4.2 and 4.5. No audio decoding.
/// Pass the LC core ASC, including for SBR/PS. 960-sample frames fail closed.
/// Tables are transformed from JCodec 4ba922aca445c4df59f99e183c79d0538e5cb53f,
/// net/sourceforge/jaad/aac/huffman/Codebooks.java and syntax/ScaleFactorBands.java.
/// JAAD declares these public domain; JCodec changes use the FreeBSD license below.
/// https://github.com/jcodec/jcodec/tree/4ba922aca445c4df59f99e183c79d0538e5cb53f
public enum SpeechRelayAACSyntax {
    public struct Element: Sendable, Equatable {
        public enum Kind: String, Sendable, Codable { case sce, cpe, lfe }
        public let type: Kind
        public let tag: Int
        public init(type: Kind, tag: Int) { self.type = type; self.tag = tag }
    }
    public struct ProgramConfig: Sendable, Equatable {
        public let front: [Element]
        public let side: [Element]
        public let back: [Element]
        public let lfe: [Element]
        public init(front: [Element], side: [Element] = [], back: [Element] = [], lfe: [Element] = []) {
            self.front = front; self.side = side; self.back = back; self.lfe = lfe
        }
        fileprivate var parts: [[Element]] { [front, side, back, lfe] }
    }
    public struct Config: Sendable, Equatable {
        public let objectType: Int
        public let samplingFrequencyIndex: Int
        public let channelConfiguration: Int
        public let frameLengthFlag: Bool
        public let programConfig: ProgramConfig?
        public init(objectType: Int, samplingFrequencyIndex: Int, channelConfiguration: Int,
                    frameLengthFlag: Bool, programConfig: ProgramConfig? = nil) {
            self.objectType = objectType; self.samplingFrequencyIndex = samplingFrequencyIndex
            self.channelConfiguration = channelConfiguration; self.frameLengthFlag = frameLengthFlag
            self.programConfig = programConfig
        }
    }
    /// Returns true only for exactly one complete, layout-consistent LC raw_data_block.
    /// Rejects unsupported or malformed syntax. Bounded to 8192 bytes and eight channels.
    public static func validateSingleAccessUnit(sample: Data, config: Config) -> Bool {
        guard sample.count <= 8192 else { return false }
        return validateSingleAccessUnit(sample: Array(sample), config: config)
    }
    public static func validateSingleAccessUnit(sample: [UInt8], config: Config) -> Bool {
        firstAccessUnitLength(in: sample, offset: 0, config: config) == sample.count
    }

    // Local conversion only: find a syntax-proven boundary without rescanning every
    // candidate prefix. Strict acceptance still requires that it consumes ALL bytes.
    static func firstAccessUnitLength(in sample: [UInt8], offset: Int, config: Config) -> Int? {
        let sf = config.samplingFrequencyIndex, channel = config.channelConfiguration
        guard config.objectType == 2, !config.frameLengthFlag, (0...12).contains(sf),
              (0...7).contains(channel), offset >= 0, offset < sample.count, sample.count <= 8192 else { return nil }
        var p = config.programConfig
        if let p, !validProgram(p, channel: channel) { return nil }
        let b = Bits(sample)
        b.position = offset * 8
        var elements: [Element] = [], hasPce = false
        do {
            while true {
                let id = try b.read(3)
                if id == 7 {
                    try b.align()
                    guard !elements.isEmpty else { return nil }
                    if let p {
                        let expected = p.parts.flatMap { $0 }
                        guard expected.count == elements.count && expected.allSatisfy({ elements.contains($0) }) else { return nil }
                        return b.position / 8 - offset
                    }
                    guard channel != 0 else { return nil }
                    let expected = layouts[channel].flatMap { $0 }
                    guard elements.count == expected.count && [Element.Kind.sce, .cpe, .lfe].allSatisfy({ type in
                        elements.filter { $0.type == type }.count == expected.filter { $0 == type }.count
                    }) else { return nil }
                    return b.position / 8 - offset
                }
                if id == 0 || id == 1 || id == 3 {
                    guard elements.count < 8 else { return nil }
                    let type: Element.Kind = id == 0 ? .sce : id == 1 ? .cpe : .lfe
                    let element = Element(type: type, tag: try b.read(4))
                    guard !elements.contains(element) else { return nil }
                    elements.append(element)
                    if let p {
                        guard p.parts.flatMap({ $0 }).contains(element) else { return nil }
                    } else {
                        guard channel != 0,
                              elements.filter({ $0.type == type }).count <= layouts[channel].flatMap({ $0 }).filter({ $0 == type }).count else { return nil }
                    }
                    if id == 1 {
                        let common = try b.read(1) != 0 ? info(b, sf: sf) : nil
                        if let common {
                            let mask = try b.read(2)
                            guard mask != 3 else { return nil }
                            if mask == 1 { try b.skip(common.groups.count * common.maxSfb) }
                        }
                        try ics(b, sf: sf, common: common)
                        try ics(b, sf: sf, common: common, intensityAllowed: common != nil)
                    } else { try ics(b, sf: sf) }
                } else if id == 4 {
                    try b.skip(4)
                    let aligned = try b.read(1)
                    var count = try b.read(8)
                    if count == 255 { count += try b.read(8) }
                    if aligned != 0 { try b.align() }
                    try b.skip(count * 8)
                } else if id == 5 {
                    guard !hasPce, elements.isEmpty else { return nil }
                    let next = try program(b, sf: sf)
                    guard validProgram(next, channel: channel) else { return nil }
                    if let p, p != next { return nil }
                    p = next; hasPce = true
                } else if id == 6 {
                    var count = try b.read(4)
                    if count == 15 { count += try b.read(8) - 1 }
                    try b.skip(count * 8) // FIL, including opaque SBR/PS extension payloads
                } else { return nil } // CCE and unsupported syntax
            }
        } catch { return nil }
    }
    private enum Invalid: Error { case syntax }
    private final class Bits {
        let bytes: [UInt8]
        var position = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        func read(_ count: Int) throws -> Int {
            guard position + count <= bytes.count * 8 else { throw Invalid.syntax }
            var value = 0
            for _ in 0..<count {
                value = value * 2 + Int((bytes[position >> 3] >> (7 - (position & 7))) & 1)
                position += 1
            }
            return value
        }
        func skip(_ count: Int) throws {
            guard position + count <= bytes.count * 8 else { throw Invalid.syntax }
            position += count
        }
        func align() throws {
            guard try read((8 - (position & 7)) & 7) == 0 else { throw Invalid.syntax }
        }
        func huffman(_ book: Int) throws -> Int {
            let tree = SpeechRelayAACSyntax.huffman[book]
            var node = 0
            repeat { node = tree[node + (try read(1))] } while node > 0
            return -node - 1
        }
    }
    private struct ICS {
        let short: Bool
        let maxSfb: Int
        let groups: [Int]
        let bands: [Int]
    }
    private static func info(_ b: Bits, sf: Int) throws -> ICS {
        guard try b.read(1) == 0 else { throw Invalid.syntax }
        let short = try b.read(2) == 2
        try b.skip(1)
        let maxSfb = try b.read(short ? 4 : 6)
        var groups = [1]
        if short {
            for _ in 0..<7 {
                if try b.read(1) != 0 { groups[groups.count - 1] += 1 } else { groups.append(1) }
            }
        } else if try b.read(1) != 0 { throw Invalid.syntax }
        let bands = (short ? shortBands : longBands)[sf]
        guard maxSfb < bands.count else { throw Invalid.syntax }
        return ICS(short: short, maxSfb: maxSfb, groups: groups, bands: bands)
    }
    private static func ics(_ b: Bits, sf: Int, common: ICS? = nil, intensityAllowed: Bool = false) throws {
        var scale = try b.read(8)
        let i = try common ?? info(b, sf: sf)
        var codebooks: [Int] = []
        let width = i.short ? 3 : 5, escape = (1 << width) - 1
        for _ in i.groups {
            var band = 0
            while band < i.maxSfb {
                let book = try b.read(4)
                guard book != 12, book < 14 || intensityAllowed else { throw Invalid.syntax }
                var length = 0, increment: Int
                repeat {
                    increment = try b.read(width)
                    length += increment
                    guard band + length <= i.maxSfb else { throw Invalid.syntax }
                } while increment == escape
                guard length > 0 else { throw Invalid.syntax }
                codebooks.append(contentsOf: repeatElement(book, count: length))
                band += length
            }
        }
        var firstNoise = true
        for book in codebooks {
            if book == 0 { continue }
            if book == 13 && firstNoise { try b.skip(9); firstNoise = false }
            else {
                let delta = try b.huffman(11) - 60
                if book < 12 {
                    scale += delta
                    guard (0...255).contains(scale) else { throw Invalid.syntax }
                }
            }
        }
        if try b.read(1) != 0 {
            guard !i.short else { throw Invalid.syntax }
            let count = try b.read(2) + 1, start = try b.read(6)
            guard start < i.bands.count - 1 else { throw Invalid.syntax }
            var offset = i.bands[start]
            for _ in 0..<count {
                offset += try b.read(5)
                guard offset < 1024 else { throw Invalid.syntax }
                try b.skip(4)
            }
        }
        if try b.read(1) != 0 {
            for _ in 0..<(i.short ? 8 : 1) {
                let count = try b.read(i.short ? 1 : 2)
                let resolution = try count != 0 ? b.read(1) + 3 : 0
                for _ in 0..<count {
                    try b.skip(i.short ? 4 : 6)
                    let order = try b.read(i.short ? 3 : 5)
                    guard order <= (i.short ? 7 : 12) else { throw Invalid.syntax }
                    if order != 0 {
                        try b.skip(1)
                        let compression = try b.read(1)
                        try b.skip(order * (resolution - compression))
                    }
                }
            }
        }
        guard try b.read(1) == 0 else { throw Invalid.syntax }
        var index = 0
        for group in i.groups {
            for band in 0..<i.maxSfb {
                let book = codebooks[index]; index += 1
                if book == 0 || book >= 13 { continue }
                let dimension = book <= 4 ? 4 : 2
                let coefficients = (i.bands[band + 1] - i.bands[band]) * group
                guard coefficients % dimension == 0 else { throw Invalid.syntax }
                for _ in 0..<(coefficients / dimension) {
                    let payload = try b.huffman(book - 1)
                    try b.skip(payload & 7)
                    for _ in 0..<(payload >> 3) {
                        var size = 4
                        while try b.read(1) != 0 {
                            size += 1
                            guard size <= 12 else { throw Invalid.syntax }
                        }
                        try b.skip(size)
                    }
                }
            }
        }
    }
    private static let layouts: [[[Element.Kind]]] = [
        [], [[.sce], [], [], []], [[.cpe], [], [], []],
        [[.sce, .cpe], [], [], []], [[.sce, .cpe], [], [.sce], []],
        [[.sce, .cpe], [], [.cpe], []], [[.sce, .cpe], [], [.cpe], [.lfe]],
        [[.sce, .cpe], [.cpe], [.cpe], [.lfe]],
    ]
    private static func validProgram(_ p: ProgramConfig, channel: Int) -> Bool {
        let sections = p.parts, all = sections.flatMap { $0 }
        guard !all.isEmpty, all.reduce(0, { $0 + ($1.type == .cpe ? 2 : 1) }) <= 8 else { return false }
        var seen: [Element] = []
        for s in 0..<4 {
            guard sections[s].count <= (s == 3 ? 3 : 15) else { return false }
            for e in sections[s] {
                guard (s == 3 ? e.type == .lfe : e.type == .sce || e.type == .cpe),
                      (0...15).contains(e.tag), !seen.contains(e) else { return false }
                seen.append(e)
            }
            if channel != 0 && sections[s].map(\.type) != layouts[channel][s] { return false }
        }
        return true
    }
    private static func program(_ b: Bits, sf: Int) throws -> ProgramConfig {
        try b.skip(4)
        guard try b.read(2) == 1, try b.read(4) == sf else { throw Invalid.syntax }
        let counts = try [b.read(4), b.read(4), b.read(4), b.read(2)]
        let associated = try b.read(3), coupling = try b.read(4)
        guard coupling == 0 else { throw Invalid.syntax }
        if try b.read(1) != 0 { try b.skip(4) }
        if try b.read(1) != 0 { try b.skip(4) }
        if try b.read(1) != 0 { try b.skip(3) }
        var sections: [[Element]] = []
        for s in 0..<4 {
            var elements: [Element] = []
            for _ in 0..<counts[s] {
                let type: Element.Kind = try s == 3 ? .lfe : b.read(1) != 0 ? .cpe : .sce
                elements.append(Element(type: type, tag: try b.read(4)))
            }
            sections.append(elements)
        }
        try b.skip(associated * 4)
        try b.align()
        let comment = try b.read(8)
        try b.skip(comment * 8)
        return ProgramConfig(front: sections[0], side: sections[1], back: sections[2], lfe: sections[3])
    }

// BEGIN GENERATED AAC TABLES
/*
Copyright 2008-2019 JCodecProject

Redistribution  and  use  in   source  and   binary   forms,  with  or  without 
modification, are permitted provided  that the following  conditions  are  met:

Redistributions of  source code  must  retain the above  copyright notice, this
list of conditions and the following disclaimer. Redistributions in binary form
must  reproduce  the above  copyright notice, this  list of conditions  and the
following disclaimer in the documentation and/or other  materials provided with
the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO, THE  IMPLIED
WARRANTIES  OF  MERCHANTABILITY  AND  FITNESS  FOR  A  PARTICULAR  PURPOSE  ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,  OR CONSEQUENTIAL DAMAGES
(INCLUDING,  BUT NOT LIMITED TO,  PROCUREMENT OF SUBSTITUTE GOODS  OR SERVICES;
LOSS OF USE, DATA, OR PROFITS;  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY  THEORY  OF  LIABILITY,  WHETHER  IN  CONTRACT,  STRICT LIABILITY,  OR TORT 
(INCLUDING  NEGLIGENCE OR OTHERWISE)  ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
    private static let huffman: [[Int]] = [
        [
            -1, 2, 4, 18, 6, 12, 8, 10, -1, -1, -1, -1, 14, 16, -1, -1, -1, -1, 20, 50, 22, 36, 24, 30,
            26, 28, -1, -1, -1, -1, 32, 34, -1, -1, -1, -1, 38, 44, 40, 42, -1, -1, -1, -1, 46, 48, -1, -1,
            -1, -1, 52, 66, 54, 60, 56, 58, -1, -1, -1, -1, 62, 64, -1, -1, -1, -1, 68, 98, 70, 84, 72, 78,
            74, 76, -1, -1, -1, -1, 80, 82, -1, -1, -1, -1, 86, 92, 88, 90, -1, -1, -1, -1, 94, 96, -1, -1,
            -1, -1, 100, 114, 102, 108, 104, 106, -1, -1, -1, -1, 110, 112, -1, -1, -1, -1, 116, 130, 118, 124, 120, 122,
            -1, -1, -1, -1, 126, 128, -1, -1, -1, -1, 132, 146, 134, 140, 136, 138, -1, -1, -1, -1, 142, 144, -1, -1,
            -1, -1, 148, 154, 150, 152, -1, -1, -1, -1, 156, 158, -1, -1, -1, -1,
        ],
        [
            2, 30, 4, 10, -1, 6, -1, 8, -1, -1, 12, 18, 14, 16, -1, -1, -1, -1, 20, 24, -1, 22, -1, -1,
            26, 28, -1, -1, -1, -1, 32, 62, 34, 48, 36, 42, 38, 40, -1, -1, -1, -1, 44, 46, -1, -1, -1, -1,
            50, 56, 52, 54, -1, -1, -1, -1, 58, 60, -1, -1, -1, -1, 64, 90, 66, 76, 68, 70, -1, -1, 72, 74,
            -1, -1, -1, -1, 78, 84, 80, 82, -1, -1, -1, -1, 86, 88, -1, -1, -1, -1, 92, 116, 94, 102, 96, 98,
            -1, -1, -1, 100, -1, -1, 104, 110, 106, 108, -1, -1, -1, -1, 112, 114, -1, -1, -1, -1, 118, 132, 120, 126,
            122, 124, -1, -1, -1, -1, 128, 130, -1, -1, -1, -1, 134, 146, 136, 140, -1, 138, -1, -1, 142, 144, -1, -1,
            -1, -1, 148, 154, 150, 152, -1, -1, -1, -1, 156, 158, -1, -1, -1, -1,
        ],
        [
            -1, 2, 4, 10, 6, 8, -2, -2, -2, -2, 12, 22, 14, 16, -3, -3, 18, 20, -3, -3, -3, -4, 24, 36,
            26, 28, -3, -4, 30, 32, -5, -4, -4, 34, -2, -2, 38, 62, 40, 48, 42, 44, -3, -3, -4, 46, -3, -4,
            50, 56, 52, 54, -3, -4, -4, -2, 58, 60, -3, -3, -2, -3, 64, 84, 66, 72, 68, 70, -3, -5, -4, -4,
            74, 78, -5, 76, -4, -3, 80, 82, -4, -3, -5, -5, 86, 100, 88, 94, 90, 92, -4, -4, -3, -4, 96, 98,
            -4, -4, -3, -3, 102, 114, 104, 108, -4, 106, -3, -5, 110, 112, -4, -4, -5, -5, 116, 126, 118, 120, -3, -4,
            122, 124, -4, -4, -4, -4, 128, 134, 130, 132, -4, -5, -5, -5, 136, 140, -5, 138, -3, -3, 142, 146, -4, 144,
            -4, -5, 148, 152, -4, 150, -5, -5, 154, 156, -5, -4, -3, 158, -4, -4,
        ],
        [
            2, 16, 4, 10, 6, 8, -5, -4, -4, -4, 12, 14, -4, -2, -3, -1, 18, 28, 20, 22, -3, -3, 24, 26,
            -3, -3, -2, -3, 30, 48, 32, 34, -2, -2, 36, 42, 38, 40, -5, -5, -5, -5, 44, 46, -4, -4, -4, -4,
            50, 78, 52, 64, 54, 58, -4, 56, -4, -4, 60, 62, -4, -4, -4, -4, 66, 72, 68, 70, -4, -3, -3, -3,
            74, 76, -3, -3, -3, -3, 80, 96, 82, 88, 84, 86, -3, -3, -3, -3, 90, 92, -3, -2, -2, 94, -2, -2,
            98, 116, 100, 106, 102, 104, -5, -5, -5, -5, 108, 110, -5, -5, 112, 114, -4, -4, -4, -4, 118, 132, 120, 126,
            122, 124, -4, -4, -4, -4, 128, 130, -4, -5, -4, -4, 134, 144, 136, 138, -4, -5, 140, 142, -5, -5, -3, -3,
            146, 152, 148, 150, -3, -3, -3, -3, 154, 156, -5, -4, -4, 158, -4, -4,
        ],
        [
            -1, 2, 4, 10, 6, 8, -1, -1, -1, -1, 12, 18, 14, 16, -1, -1, -1, -1, 20, 42, 22, 28, 24, 26,
            -1, -1, -1, -1, 30, 36, 32, 34, -1, -1, -1, -1, 38, 40, -1, -1, -1, -1, 44, 66, 46, 52, 48, 50,
            -1, -1, -1, -1, 54, 60, 56, 58, -1, -1, -1, -1, 62, 64, -1, -1, -1, -1, 68, 90, 70, 76, 72, 74,
            -1, -1, -1, -1, 78, 84, 80, 82, -1, -1, -1, -1, 86, 88, -1, -1, -1, -1, 92, 114, 94, 100, 96, 98,
            -1, -1, -1, -1, 102, 108, 104, 106, -1, -1, -1, -1, 110, 112, -1, -1, -1, -1, 116, 130, 118, 124, 120, 122,
            -1, -1, -1, -1, 126, 128, -1, -1, -1, -1, 132, 142, 134, 136, -1, -1, 138, 140, -1, -1, -1, -1, 144, 150,
            146, 148, -1, -1, -1, -1, 152, 154, -1, -1, 156, 158, -1, -1, -1, -1,
        ],
        [
            2, 16, 4, 10, 6, 8, -1, -1, -1, -1, 12, 14, -1, -1, -1, -1, 18, 42, 20, 28, -1, 22, 24, 26,
            -1, -1, -1, -1, 30, 36, 32, 34, -1, -1, -1, -1, 38, 40, -1, -1, -1, -1, 44, 66, 46, 52, 48, 50,
            -1, -1, -1, -1, 54, 60, 56, 58, -1, -1, -1, -1, 62, 64, -1, -1, -1, -1, 68, 88, 70, 76, 72, 74,
            -1, -1, -1, -1, 78, 82, -1, 80, -1, -1, 84, 86, -1, -1, -1, -1, 90, 116, 92, 102, 94, 96, -1, -1,
            98, 100, -1, -1, -1, -1, 104, 110, 106, 108, -1, -1, -1, -1, 112, 114, -1, -1, -1, -1, 118, 132, 120, 126,
            122, 124, -1, -1, -1, -1, 128, 130, -1, -1, -1, -1, 134, 142, 136, 138, -1, -1, -1, 140, -1, -1, 144, 150,
            146, 148, -1, -1, -1, -1, 152, 154, -1, -1, 156, 158, -1, -1, -1, -1,
        ],
        [
            -1, 2, 4, 6, -2, -2, 8, 16, -3, 10, 12, 14, -3, -3, -2, -2, 18, 38, 20, 26, 22, 24, -3, -3,
            -3, -2, 28, 32, -2, 30, -3, -3, 34, 36, -3, -3, -3, -3, 40, 62, 42, 48, 44, 46, -3, -3, -2, -2,
            50, 56, 52, 54, -3, -3, -3, -2, 58, 60, -3, -2, -3, -3, 64, 82, 66, 72, 68, 70, -3, -3, -3, -3,
            74, 76, -3, -3, 78, 80, -3, -2, -2, -3, 84, 98, 86, 92, 88, 90, -3, -3, -3, -3, 94, 96, -3, -3,
            -3, -3, 100, 108, 102, 104, -3, -3, -3, 106, -2, -2, 110, 116, 112, 114, -3, -3, -3, -3, 118, 120, -3, -3,
            122, 124, -3, -3, -3, -3,
        ],
        [
            2, 16, 4, 8, -3, 6, -3, -2, 10, 12, -3, -2, -3, 14, -1, -2, 18, 38, 20, 26, 22, 24, -2, -3,
            -3, -3, 28, 32, -3, 30, -3, -3, 34, 36, -3, -3, -3, -2, 40, 62, 42, 48, 44, 46, -2, -3, -3, -3,
            50, 56, 52, 54, -3, -3, -3, -3, 58, 60, -3, -3, -3, -2, 64, 82, 66, 72, 68, 70, -3, -2, -3, -3,
            74, 76, -3, -3, 78, 80, -3, -3, -3, -2, 84, 98, 86, 92, 88, 90, -3, -2, -3, -3, 94, 96, -3, -3,
            -3, -3, 100, 108, 102, 104, -3, -3, -3, 106, -3, -3, 110, 116, 112, 114, -2, -3, -2, -3, 118, 120, -3, -3,
            122, 124, -3, -2, -2, -3,
        ],
        [
            -1, 2, 4, 6, -2, -2, 8, 16, -3, 10, 12, 14, -3, -3, -2, -2, 18, 46, 20, 28, 22, 24, -3, -3,
            -3, 26, -2, -2, 30, 36, 32, 34, -3, -3, -3, -3, 38, 40, -3, -3, 42, 44, -3, -3, -2, -2, 48, 96,
            50, 66, 52, 58, 54, 56, -3, -3, -3, -3, 60, 62, -3, -3, -3, 64, -2, -3, 68, 82, 70, 76, 72, 74,
            -2, -3, -3, -3, 78, 80, -3, -3, -3, -3, 84, 90, 86, 88, -3, -2, -3, -3, 92, 94, -3, -3, -3, -3,
            98, 156, 100, 126, 102, 112, 104, 106, -3, -3, 108, 110, -2, -3, -3, -3, 114, 120, 116, 118, -2, -3, -3, -3,
            122, 124, -3, -2, -3, -3, 128, 142, 130, 136, 132, 134, -3, -3, -2, -2, 138, 140, -3, -3, -3, -3, 144, 150,
            146, 148, -3, -3, -3, -3, 152, 154, -3, -3, -3, -3, 158, 214, 160, 184, 162, 170, 164, 166, -3, -2, -3, 168,
            -3, -3, 172, 178, 174, 176, -2, -3, -3, -3, 180, 182, -3, -3, -3, -3, 186, 200, 188, 194, 190, 192, -3, -3,
            -3, -3, 196, 198, -3, -3, -3, -3, 202, 208, 204, 206, -3, -3, -3, -3, 210, 212, -3, -2, -3, -3, 216, 254,
            218, 232, 220, 226, 222, 224, -2, -3, -3, -3, 228, 230, -3, -3, -3, -3, 234, 240, 236, 238, -2, -3, -3, -3,
            242, 248, 244, 246, -3, -3, -3, -3, 250, 252, -3, -3, -3, -3, 256, 286, 258, 272, 260, 266, 262, 264, -3, -3,
            -3, -3, 268, 270, -2, -3, -3, -2, 274, 280, 276, 278, -3, -3, -3, -3, 282, 284, -2, -3, -3, -3, 288, 302,
            290, 296, 292, 294, -3, -3, -3, -3, 298, 300, -3, -3, -3, -3, 304, 318, 306, 312, 308, 310, -3, -3, -3, -3,
            314, 316, -3, -3, -3, -3, 320, 326, 322, 324, -3, -3, -3, -3, 328, 330, -3, -3, 332, 334, -3, -3, -3, -3,
        ],
        [
            2, 30, 4, 12, 6, 8, -3, -3, -3, 10, -3, -2, 14, 20, 16, 18, -2, -3, -3, -3, 22, 24, -3, -3,
            26, 28, -2, -2, -3, -3, 32, 74, 34, 48, 36, 42, 38, 40, -3, -3, -1, -3, 44, 46, -3, -2, -2, -3,
            50, 60, 52, 54, -3, -3, 56, 58, -3, -3, -3, -3, 62, 68, 64, 66, -3, -3, -3, -3, 70, 72, -3, -2,
            -3, -2, 76, 128, 78, 98, 80, 86, 82, 84, -3, -3, -3, -3, 88, 92, -3, 90, -3, -3, 94, 96, -3, -3,
            -3, -3, 100, 114, 102, 108, 104, 106, -3, -2, -3, -2, 110, 112, -3, -3, -3, -3, 116, 122, 118, 120, -3, -3,
            -3, -3, 124, 126, -3, -3, -3, -3, 130, 186, 132, 156, 134, 142, 136, 138, -3, -3, -3, 140, -3, -3, 144, 150,
            146, 148, -3, -2, -3, -3, 152, 154, -3, -3, -3, -2, 158, 172, 160, 166, 162, 164, -3, -3, -3, -3, 168, 170,
            -3, -3, -3, -3, 174, 180, 176, 178, -3, -3, -3, -3, 182, 184, -3, -3, -3, -3, 188, 240, 190, 210, 192, 198,
            194, 196, -3, -2, -3, -2, 200, 204, -3, 202, -3, -3, 206, 208, -3, -3, -3, -3, 212, 226, 214, 220, 216, 218,
            -2, -3, -3, -3, 222, 224, -3, -3, -3, -2, 228, 234, 230, 232, -3, -3, -3, -3, 236, 238, -3, -3, -3, -3,
            242, 272, 244, 258, 246, 252, 248, 250, -3, -3, -3, -3, 254, 256, -3, -3, -3, -3, 260, 266, 262, 264, -3, -2,
            -3, -2, 268, 270, -3, -2, -3, -3, 274, 298, 276, 284, 278, 280, -3, -3, -3, 282, -3, -3, 286, 292, 288, 290,
            -3, -3, -3, -3, 294, 296, -3, -3, -3, -3, 300, 314, 302, 308, 304, 306, -2, -3, -2, -3, 310, 312, -3, -3,
            -2, -3, 316, 322, 318, 320, -3, -3, -2, -3, 324, 330, 326, 328, -3, -3, -3, -3, 332, 334, -3, -2, -3, -3,
        ],
        [
            2, 50, 4, 14, 6, 8, -1, -3, 10, 12, -19, -2, -2, -3, 16, 26, 18, 20, -3, -3, 22, 24, -3, -3,
            -3, -2, 28, 36, 30, 32, -3, -2, -3, 34, -3, -3, 38, 44, 40, 42, -3, -3, -3, -3, 46, 48, -2, -2,
            -3, -3, 52, 166, 54, 104, 56, 74, 58, 64, 60, 62, -3, -3, -3, -3, 66, 68, -3, -3, 70, 72, -3, -3,
            -3, -3, 76, 90, 78, 84, 80, 82, -3, -3, -3, -11, 86, 88, -11, -11, -11, -11, 92, 98, 94, 96, -3, -11,
            -2, -3, 100, 102, -2, -11, -3, -11, 106, 136, 108, 122, 110, 116, 112, 114, -11, -11, -11, -3, 118, 120, -3, -3,
            -3, -3, 124, 130, 126, 128, -11, -11, -3, -3, 132, 134, -11, -11, -11, -3, 138, 152, 140, 146, 142, 144, -3, -11,
            -3, -11, 148, 150, -11, -11, -3, -11, 154, 160, 156, 158, -3, -3, -11, -11, 162, 164, -3, -3, -3, -2, 168, 280,
            170, 218, 172, 188, 174, 180, 176, 178, -11, -11, -3, -3, 182, 184, -3, -3, -2, 186, -3, -11, 190, 204, 192, 198,
            194, 196, -11, -3, -3, -11, 200, 202, -3, -11, -3, -3, 206, 212, 208, 210, -3, -3, -3, -3, 214, 216, -3, -11,
            -3, -3, 220, 250, 222, 236, 224, 230, 226, 228, -2, -3, -3, -3, 232, 234, -3, -3, -3, -2, 238, 244, 240, 242,
            -3, -3, -3, -3, 246, 248, -3, -3, -3, -3, 252, 266, 254, 260, 256, 258, -3, -3, -3, -3, 262, 264, -3, -3,
            -2, -3, 268, 274, 270, 272, -3, -3, -3, -3, 276, 278, -3, -3, -3, -3, 282, 398, 284, 336, 286, 306, 288, 294,
            290, 292, -3, -3, -10, -3, 296, 300, -3, 298, -3, -3, 302, 304, -3, -3, -10, -3, 308, 322, 310, 316, 312, 314,
            -2, -3, -3, -3, 318, 320, -3, -3, -3, -3, 324, 330, 326, 328, -3, -3, -3, -3, 332, 334, -3, -3, -3, -3,
            338, 368, 340, 354, 342, 348, 344, 346, -3, -3, -3, -3, 350, 352, -3, -3, -3, -3, 356, 362, 358, 360, -3, -3,
            -3, -3, 364, 366, -3, -3, -3, -2, 370, 384, 372, 378, 374, 376, -3, -3, -3, -3, 380, 382, -3, -3, -3, -3,
            386, 392, 388, 390, -3, -3, -3, -3, 394, 396, -3, -3, -3, -3, 400, 462, 402, 432, 404, 418, 406, 412, 408, 410,
            -3, -3, -2, -3, 414, 416, -3, -3, -3, -3, 420, 426, 422, 424, -3, -3, -3, -3, 428, 430, -3, -3, -3, -3,
            434, 448, 436, 442, 438, 440, -3, -3, -3, -3, 444, 446, -3, -3, -3, -3, 450, 456, 452, 454, -3, -3, -3, -3,
            458, 460, -3, -3, -2, -2, 464, 508, 466, 480, 468, 474, 470, 472, -3, -3, -3, -3, 476, 478, -3, -3, -3, -3,
            482, 494, 484, 488, -3, 486, -3, -3, 490, 492, -3, -3, -3, -3, 496, 502, 498, 500, -3, -3, -3, -3, 504, 506,
            -3, -3, -3, -3, 510, 540, 512, 526, 514, 520, 516, 518, -3, -3, -3, -2, 522, 524, -3, -3, -2, -3, 528, 534,
            530, 532, -2, -3, -3, -3, 536, 538, -2, -3, -3, -3, 542, 556, 544, 550, 546, 548, -3, -3, -2, -2, 552, 554,
            -3, -3, -3, -3, 558, 564, 560, 562, -2, -3, -3, -2, 566, 570, -3, 568, -2, -2, 572, 574, -3, -2, -2, -3,
        ],
        [
            -61, 2, 4, 8, -60, 6, -62, -59, 10, 14, -63, 12, -58, -64, 16, 22, 18, 20, -57, -65, -56, -66, 24, 32,
            26, 28, -67, -55, -68, 30, -54, -69, 34, 42, 36, 38, -53, -70, -52, 40, -71, -51, 44, 54, 46, 48, -50, -72,
            50, 52, -73, -49, -74, -48, 56, 66, 58, 60, -75, -47, 62, 64, -77, -76, -78, -79, 68, 78, 70, 72, -46, -44,
            74, 76, -45, -80, -43, -42, 80, 90, 82, 84, -81, -41, 86, 88, -82, -40, -83, -39, 92, 104, 94, 98, -84, 96,
            -38, -36, 100, 102, -86, -34, -37, -35, 106, 116, 108, 110, -85, -33, 112, 114, -88, -90, -31, -32, 118, 134, 120, 126,
            122, 124, -87, -30, -27, -28, 128, 130, -29, -25, -89, 132, -26, -23, 136, 178, 138, 150, 140, 144, -24, 142, -91, -22,
            146, 148, -20, -4, -2, -3, 152, 164, 154, 158, -1, 156, -99, -100, 160, 162, -101, -102, -103, -118, 166, 172, 168, 170,
            -98, -92, -93, -94, 174, 176, -95, -96, -97, -105, 180, 210, 182, 196, 184, 190, 186, 188, -112, -113, -114, -115, 192, 194,
            -116, -117, -111, -106, 198, 204, 200, 202, -107, -108, -109, -110, 206, 208, -119, -7, -9, -10, 212, 226, 214, 220, 216, 218,
            -11, -6, -104, -121, 222, 224, -120, -5, -8, -16, 228, 234, 230, 232, -17, -19, -21, -18, 236, 238, -12, -13, -15, -14,
        ],
    ]
    private static let longBands: [[Int]] = [
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144,
            156, 172, 188, 212, 240, 276, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144,
            156, 172, 188, 212, 240, 276, 320, 384, 448, 512, 576, 640, 704, 768, 832, 896, 960, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 64, 72, 80, 88, 100, 112, 124, 140, 156,
            172, 192, 216, 240, 268, 304, 344, 384, 424, 464, 504, 544, 584, 624, 664, 704, 744, 784, 824, 864, 904, 944, 984, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144, 160, 176,
            196, 216, 240, 264, 292, 320, 352, 384, 416, 448, 480, 512, 544, 576, 608, 640, 672, 704, 736, 768, 800, 832, 864, 896,
            928, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144, 160, 176,
            196, 216, 240, 264, 292, 320, 352, 384, 416, 448, 480, 512, 544, 576, 608, 640, 672, 704, 736, 768, 800, 832, 864, 896,
            928, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 88, 96, 108, 120, 132, 144, 160, 176,
            196, 216, 240, 264, 292, 320, 352, 384, 416, 448, 480, 512, 544, 576, 608, 640, 672, 704, 736, 768, 800, 832, 864, 896,
            928, 960, 992, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 124, 136, 148,
            160, 172, 188, 204, 220, 240, 260, 284, 308, 336, 364, 396, 432, 468, 508, 552, 600, 652, 704, 768, 832, 896, 960, 1024,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 52, 60, 68, 76, 84, 92, 100, 108, 116, 124, 136, 148,
            160, 172, 188, 204, 220, 240, 260, 284, 308, 336, 364, 396, 432, 468, 508, 552, 600, 652, 704, 768, 832, 896, 960, 1024,
        ],
        [
            0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 100, 112, 124, 136, 148, 160, 172, 184, 196, 212, 228, 244,
            260, 280, 300, 320, 344, 368, 396, 424, 456, 492, 532, 572, 616, 664, 716, 772, 832, 896, 960, 1024,
        ],
        [
            0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 100, 112, 124, 136, 148, 160, 172, 184, 196, 212, 228, 244,
            260, 280, 300, 320, 344, 368, 396, 424, 456, 492, 532, 572, 616, 664, 716, 772, 832, 896, 960, 1024,
        ],
        [
            0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 100, 112, 124, 136, 148, 160, 172, 184, 196, 212, 228, 244,
            260, 280, 300, 320, 344, 368, 396, 424, 456, 492, 532, 572, 616, 664, 716, 772, 832, 896, 960, 1024,
        ],
        [
            0, 12, 24, 36, 48, 60, 72, 84, 96, 108, 120, 132, 144, 156, 172, 188, 204, 220, 236, 252, 268, 288, 308, 328,
            348, 372, 396, 420, 448, 476, 508, 544, 580, 620, 664, 712, 764, 820, 880, 944, 1024,
        ],
        [
            0, 12, 24, 36, 48, 60, 72, 84, 96, 108, 120, 132, 144, 156, 172, 188, 204, 220, 236, 252, 268, 288, 308, 328,
            348, 372, 396, 420, 448, 476, 508, 544, 580, 620, 664, 712, 764, 820, 880, 944, 1024,
        ],
    ]
    private static let shortBands: [[Int]] = [
        [
            0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 92, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 92, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 92, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 28, 36, 44, 56, 68, 80, 96, 112, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 28, 36, 44, 56, 68, 80, 96, 112, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 28, 36, 44, 56, 68, 80, 96, 112, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 36, 44, 52, 64, 76, 92, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 36, 44, 52, 64, 76, 92, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 60, 72, 88, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 60, 72, 88, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 32, 40, 48, 60, 72, 88, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 36, 44, 52, 60, 72, 88, 108, 128,
        ],
        [
            0, 4, 8, 12, 16, 20, 24, 28, 36, 44, 52, 60, 72, 88, 108, 128,
        ],
    ]
}
