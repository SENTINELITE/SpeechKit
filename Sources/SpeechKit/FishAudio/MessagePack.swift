import Foundation

/// A MessagePack value.
///
/// Fish Audio's realtime endpoint frames every message, in both directions, as
/// one MessagePack map. SpeechKit has no dependencies, so this small codec
/// covers the formats that protocol uses: nil, booleans, integers of every
/// width, 32- and 64-bit floats, strings, binary data, arrays, and maps.
/// Extension values are decoded and re-encoded opaquely so an unexpected one
/// does not fail the whole message.
///
/// Integer equality is numeric: `.int(5) == .uint(5)`. The encoder writes a
/// non-negative ``int(_:)`` in the unsigned formats, and the decoder reads
/// those formats back as ``uint(_:)``, so a round trip keeps the number but
/// not necessarily the case.
enum MessagePackValue: Sendable {
    /// The nil value.
    case null
    /// A Boolean value.
    case bool(Bool)
    /// A signed integer.
    case int(Int64)
    /// An unsigned integer.
    case uint(UInt64)
    /// A 32-bit float.
    case float(Float)
    /// A 64-bit float.
    case double(Double)
    /// A UTF-8 string.
    case string(String)
    /// Binary data.
    case binary(Data)
    /// An array of values.
    case array([MessagePackValue])
    /// A map, as key-value pairs in encoding order.
    case map([(key: MessagePackValue, value: MessagePackValue)])
    /// An extension value with its application-defined type.
    case ext(type: Int8, data: Data)
}

extension MessagePackValue: Equatable {
    static func == (lhs: MessagePackValue, rhs: MessagePackValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.int(let a), .int(let b)):
            return a == b
        case (.uint(let a), .uint(let b)):
            return a == b
        case (.int(let a), .uint(let b)), (.uint(let b), .int(let a)):
            return a >= 0 && UInt64(a) == b
        case (.float(let a), .float(let b)):
            return a == b
        case (.double(let a), .double(let b)):
            return a == b
        case (.string(let a), .string(let b)):
            return a == b
        case (.binary(let a), .binary(let b)):
            return a == b
        case (.array(let a), .array(let b)):
            return a == b
        case (.map(let a), .map(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.ext(let typeA, let dataA), .ext(let typeB, let dataB)):
            return typeA == typeB && dataA == dataB
        default:
            return false
        }
    }
}

// MARK: - Accessors

extension MessagePackValue {
    /// The value for a string key, when this is a map.
    subscript(key: String) -> MessagePackValue? {
        guard case .map(let pairs) = self else { return nil }
        return pairs.first { $0.key == .string(key) }?.value
    }

    /// The string, when this is a string.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The Boolean, when this is a Boolean.
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The integer, when this is an integer that fits in `Int`.
    var intValue: Int? {
        switch self {
        case .int(let value):
            return Int(exactly: value)
        case .uint(let value):
            return Int(exactly: value)
        default:
            return nil
        }
    }

    /// The number as a `Double`, when this is an integer or a float.
    var doubleValue: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .uint(let value):
            return Double(value)
        case .float(let value):
            return Double(value)
        case .double(let value):
            return value
        default:
            return nil
        }
    }

    /// The bytes, when this is binary data.
    var binaryValue: Data? {
        if case .binary(let value) = self { return value }
        return nil
    }

    /// The elements, when this is an array.
    var arrayValue: [MessagePackValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The pairs, when this is a map.
    var mapValue: [(key: MessagePackValue, value: MessagePackValue)]? {
        if case .map(let value) = self { return value }
        return nil
    }

    /// The string keys of a map, in encoding order.
    var mapKeys: [String] {
        mapValue?.compactMap(\.key.stringValue) ?? []
    }
}

// MARK: - Errors

/// Errors thrown by the MessagePack decoder.
enum MessagePackError: Error, Equatable, Sendable {
    /// The input ended before the value did.
    case truncated
    /// The input holds bytes after the value.
    case trailingBytes
    /// The input uses a format byte that MessagePack never assigns.
    case invalidFormat(UInt8)
    /// Arrays and maps are nested deeper than the decoder allows.
    case nestingTooDeep
}

// MARK: - Encoding

enum MessagePack {
    /// How deeply arrays and maps may nest before decoding fails.
    static let maximumDepth = 64

    /// Encodes one value.
    static func encode(_ value: MessagePackValue) -> Data {
        var bytes: [UInt8] = []
        append(value, to: &bytes)
        return Data(bytes)
    }

    /// Decodes exactly one value, rejecting truncated input and trailing bytes.
    static func decode(_ data: Data) throws -> MessagePackValue {
        var reader = Reader(bytes: [UInt8](data))
        let value = try reader.readValue(depth: 0)
        guard reader.isAtEnd else { throw MessagePackError.trailingBytes }
        return value
    }

    private static func append(_ value: MessagePackValue, to bytes: inout [UInt8]) {
        switch value {
        case .null:
            bytes.append(0xc0)
        case .bool(let flag):
            bytes.append(flag ? 0xc3 : 0xc2)
        case .int(let number):
            if number >= 0 {
                appendUnsigned(UInt64(number), to: &bytes)
            } else if number >= -32 {
                bytes.append(UInt8(bitPattern: Int8(number)))
            } else if number >= Int64(Int8.min) {
                bytes.append(0xd0)
                appendBigEndian(Int8(number), to: &bytes)
            } else if number >= Int64(Int16.min) {
                bytes.append(0xd1)
                appendBigEndian(Int16(number), to: &bytes)
            } else if number >= Int64(Int32.min) {
                bytes.append(0xd2)
                appendBigEndian(Int32(number), to: &bytes)
            } else {
                bytes.append(0xd3)
                appendBigEndian(number, to: &bytes)
            }
        case .uint(let number):
            appendUnsigned(number, to: &bytes)
        case .float(let number):
            bytes.append(0xca)
            appendBigEndian(number.bitPattern, to: &bytes)
        case .double(let number):
            bytes.append(0xcb)
            appendBigEndian(number.bitPattern, to: &bytes)
        case .string(let string):
            let utf8 = Array(string.utf8)
            appendHeader(count: utf8.count, fix: (0xa0, 31), formats: (0xd9, 0xda, 0xdb), to: &bytes)
            bytes.append(contentsOf: utf8)
        case .binary(let data):
            appendHeader(count: data.count, fix: nil, formats: (0xc4, 0xc5, 0xc6), to: &bytes)
            bytes.append(contentsOf: data)
        case .array(let elements):
            appendHeader(count: elements.count, fix: (0x90, 15), formats: (nil, 0xdc, 0xdd), to: &bytes)
            for element in elements {
                append(element, to: &bytes)
            }
        case .map(let pairs):
            appendHeader(count: pairs.count, fix: (0x80, 15), formats: (nil, 0xde, 0xdf), to: &bytes)
            for pair in pairs {
                append(pair.key, to: &bytes)
                append(pair.value, to: &bytes)
            }
        case .ext(let type, let data):
            switch data.count {
            case 1: bytes.append(0xd4)
            case 2: bytes.append(0xd5)
            case 4: bytes.append(0xd6)
            case 8: bytes.append(0xd7)
            case 16: bytes.append(0xd8)
            default:
                appendHeader(count: data.count, fix: nil, formats: (0xc7, 0xc8, 0xc9), to: &bytes)
            }
            bytes.append(UInt8(bitPattern: type))
            bytes.append(contentsOf: data)
        }
    }

    private static func appendUnsigned(_ number: UInt64, to bytes: inout [UInt8]) {
        if number <= 0x7f {
            bytes.append(UInt8(number))
        } else if number <= UInt64(UInt8.max) {
            bytes.append(0xcc)
            bytes.append(UInt8(number))
        } else if number <= UInt64(UInt16.max) {
            bytes.append(0xcd)
            appendBigEndian(UInt16(number), to: &bytes)
        } else if number <= UInt64(UInt32.max) {
            bytes.append(0xce)
            appendBigEndian(UInt32(number), to: &bytes)
        } else {
            bytes.append(0xcf)
            appendBigEndian(number, to: &bytes)
        }
    }

    /// Writes a length header in the smallest format that fits.
    ///
    /// `fix` is the fix-format base byte and its largest count; `formats` are
    /// the 8-, 16-, and 32-bit length formats, where `nil` means the type has
    /// no 8-bit form.
    private static func appendHeader(
        count: Int,
        fix: (base: UInt8, maximum: Int)?,
        formats: (UInt8?, UInt8, UInt8),
        to bytes: inout [UInt8]
    ) {
        if let fix, count <= fix.maximum {
            bytes.append(fix.base | UInt8(count))
        } else if let format8 = formats.0, count <= Int(UInt8.max) {
            bytes.append(format8)
            bytes.append(UInt8(count))
        } else if count <= Int(UInt16.max) {
            bytes.append(formats.1)
            appendBigEndian(UInt16(count), to: &bytes)
        } else {
            bytes.append(formats.2)
            appendBigEndian(UInt32(truncatingIfNeeded: count), to: &bytes)
        }
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        withUnsafeBytes(of: value.bigEndian) { bytes.append(contentsOf: $0) }
    }
}

// MARK: - Decoding

private struct Reader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset == bytes.count }
    var remaining: Int { bytes.count - offset }

    mutating func readValue(depth: Int) throws -> MessagePackValue {
        let format = try readByte()

        switch format {
        case 0x00...0x7f:
            return .uint(UInt64(format))
        case 0x80...0x8f:
            return try readMap(count: Int(format & 0x0f), depth: depth)
        case 0x90...0x9f:
            return try readArray(count: Int(format & 0x0f), depth: depth)
        case 0xa0...0xbf:
            return .string(try readString(count: Int(format & 0x1f)))
        case 0xc0:
            return .null
        case 0xc2:
            return .bool(false)
        case 0xc3:
            return .bool(true)
        case 0xc4:
            return .binary(Data(try readBytes(count: try readLength(UInt8.self))))
        case 0xc5:
            return .binary(Data(try readBytes(count: try readLength(UInt16.self))))
        case 0xc6:
            return .binary(Data(try readBytes(count: try readLength(UInt32.self))))
        case 0xc7:
            return try readExt(count: try readLength(UInt8.self))
        case 0xc8:
            return try readExt(count: try readLength(UInt16.self))
        case 0xc9:
            return try readExt(count: try readLength(UInt32.self))
        case 0xca:
            return .float(Float(bitPattern: try readInteger(UInt32.self)))
        case 0xcb:
            return .double(Double(bitPattern: try readInteger(UInt64.self)))
        case 0xcc:
            return .uint(UInt64(try readInteger(UInt8.self)))
        case 0xcd:
            return .uint(UInt64(try readInteger(UInt16.self)))
        case 0xce:
            return .uint(UInt64(try readInteger(UInt32.self)))
        case 0xcf:
            return .uint(try readInteger(UInt64.self))
        case 0xd0:
            return .int(Int64(try readInteger(Int8.self)))
        case 0xd1:
            return .int(Int64(try readInteger(Int16.self)))
        case 0xd2:
            return .int(Int64(try readInteger(Int32.self)))
        case 0xd3:
            return .int(try readInteger(Int64.self))
        case 0xd4:
            return try readExt(count: 1)
        case 0xd5:
            return try readExt(count: 2)
        case 0xd6:
            return try readExt(count: 4)
        case 0xd7:
            return try readExt(count: 8)
        case 0xd8:
            return try readExt(count: 16)
        case 0xd9:
            return .string(try readString(count: try readLength(UInt8.self)))
        case 0xda:
            return .string(try readString(count: try readLength(UInt16.self)))
        case 0xdb:
            return .string(try readString(count: try readLength(UInt32.self)))
        case 0xdc:
            return try readArray(count: try readLength(UInt16.self), depth: depth)
        case 0xdd:
            return try readArray(count: try readLength(UInt32.self), depth: depth)
        case 0xde:
            return try readMap(count: try readLength(UInt16.self), depth: depth)
        case 0xdf:
            return try readMap(count: try readLength(UInt32.self), depth: depth)
        case 0xe0...0xff:
            return .int(Int64(Int8(bitPattern: format)))
        default:
            // 0xc1 is never used.
            throw MessagePackError.invalidFormat(format)
        }
    }

    private mutating func readByte() throws -> UInt8 {
        guard offset < bytes.count else { throw MessagePackError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    private mutating func readBytes(count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, count <= remaining else { throw MessagePackError.truncated }
        defer { offset += count }
        return bytes[offset..<(offset + count)]
    }

    private mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let slice = try readBytes(count: MemoryLayout<T>.size)
        return slice.reduce(T.zero) { ($0 << 8) | T(truncatingIfNeeded: $1) }
    }

    /// Reads a length prefix. A 32-bit length can exceed `Int` on 32-bit watchOS, so the conversion is checked.
    private mutating func readLength<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type) throws -> Int {
        guard let length = Int(exactly: try readInteger(type)) else { throw MessagePackError.truncated }
        return length
    }

    private mutating func readString(count: Int) throws -> String {
        String(decoding: try readBytes(count: count), as: UTF8.self)
    }

    private mutating func readExt(count: Int) throws -> MessagePackValue {
        let type = Int8(bitPattern: try readByte())
        return .ext(type: type, data: Data(try readBytes(count: count)))
    }

    private mutating func readArray(count: Int, depth: Int) throws -> MessagePackValue {
        guard depth < MessagePack.maximumDepth else { throw MessagePackError.nestingTooDeep }
        // Every element takes at least one byte, so a larger count cannot be satisfied.
        guard count <= remaining else { throw MessagePackError.truncated }
        var elements: [MessagePackValue] = []
        elements.reserveCapacity(count)
        for _ in 0..<count {
            elements.append(try readValue(depth: depth + 1))
        }
        return .array(elements)
    }

    private mutating func readMap(count: Int, depth: Int) throws -> MessagePackValue {
        guard depth < MessagePack.maximumDepth else { throw MessagePackError.nestingTooDeep }
        // Every pair takes at least two bytes.
        guard count <= remaining / 2 else { throw MessagePackError.truncated }
        var pairs: [(key: MessagePackValue, value: MessagePackValue)] = []
        pairs.reserveCapacity(count)
        for _ in 0..<count {
            let key = try readValue(depth: depth + 1)
            let value = try readValue(depth: depth + 1)
            pairs.append((key: key, value: value))
        }
        return .map(pairs)
    }
}
