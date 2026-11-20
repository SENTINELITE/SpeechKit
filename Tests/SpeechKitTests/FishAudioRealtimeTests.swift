import Foundation
import Testing
@testable import SpeechKit

// MARK: - MessagePack

@Suite("Fish Audio MessagePack")
struct FishAudioMessagePackTests {
    /// Known encodings for every format the codec writes.
    static let vectors: [(name: String, value: MessagePackValue, bytes: [UInt8])] = [
        ("nil", .null, [0xc0]),
        ("false", .bool(false), [0xc2]),
        ("true", .bool(true), [0xc3]),
        ("positive fixint 0", .uint(0), [0x00]),
        ("positive fixint 127", .uint(127), [0x7f]),
        ("negative fixint -1", .int(-1), [0xff]),
        ("negative fixint -32", .int(-32), [0xe0]),
        ("uint8", .uint(128), [0xcc, 0x80]),
        ("uint8 max", .uint(255), [0xcc, 0xff]),
        ("uint16", .uint(256), [0xcd, 0x01, 0x00]),
        ("uint32", .uint(65_536), [0xce, 0x00, 0x01, 0x00, 0x00]),
        ("uint64", .uint(4_294_967_296), [0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]),
        ("uint64 max", .uint(UInt64.max), [0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]),
        ("int8", .int(-33), [0xd0, 0xdf]),
        ("int8 min", .int(-128), [0xd0, 0x80]),
        ("int16", .int(-129), [0xd1, 0xff, 0x7f]),
        ("int32", .int(-32_769), [0xd2, 0xff, 0xff, 0x7f, 0xff]),
        ("int64", .int(-2_147_483_649), [0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff]),
        ("int64 min", .int(Int64.min), [0xd3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        ("float32", .float(1.5), [0xca, 0x3f, 0xc0, 0x00, 0x00]),
        ("float64", .double(1.5), [0xcb, 0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
        ("empty fixstr", .string(""), [0xa0]),
        ("fixstr", .string("abc"), [0xa3, 0x61, 0x62, 0x63]),
        ("fixstr max", .string(String(repeating: "a", count: 31)), [0xbf] + Array(repeating: 0x61, count: 31)),
        ("str8", .string(String(repeating: "a", count: 32)), [0xd9, 0x20] + Array(repeating: 0x61, count: 32)),
        ("str16", .string(String(repeating: "a", count: 256)), [0xda, 0x01, 0x00] + Array(repeating: 0x61, count: 256)),
        ("str32", .string(String(repeating: "a", count: 65_536)), [0xdb, 0x00, 0x01, 0x00, 0x00] + Array(repeating: 0x61, count: 65_536)),
        ("utf8 fixstr", .string("é"), [0xa2, 0xc3, 0xa9]),
        ("bin8", .binary(Data([1, 2])), [0xc4, 0x02, 0x01, 0x02]),
        ("empty bin8", .binary(Data()), [0xc4, 0x00]),
        ("bin16", .binary(Data(repeating: 7, count: 256)), [0xc5, 0x01, 0x00] + Array(repeating: 7, count: 256)),
        ("bin32", .binary(Data(repeating: 7, count: 65_536)), [0xc6, 0x00, 0x01, 0x00, 0x00] + Array(repeating: 7, count: 65_536)),
        ("empty fixarray", .array([]), [0x90]),
        ("fixarray", .array([.uint(1), .string("a")]), [0x92, 0x01, 0xa1, 0x61]),
        ("array16", .array(Array(repeating: .null, count: 16)), [0xdc, 0x00, 0x10] + Array(repeating: 0xc0, count: 16)),
        ("array32", .array(Array(repeating: .null, count: 65_536)), [0xdd, 0x00, 0x01, 0x00, 0x00] + Array(repeating: 0xc0, count: 65_536)),
        ("empty fixmap", .map([]), [0x80]),
        ("fixmap", .map([(key: .string("a"), value: .uint(1))]), [0x81, 0xa1, 0x61, 0x01]),
        (
            "map16",
            .map((0..<16).map { (key: .uint(UInt64($0)), value: .null) }),
            [0xde, 0x00, 0x10] + (0..<16).flatMap { [UInt8($0), 0xc0] }
        ),
        (
            "map32",
            .map((0..<65_536).map { _ in (key: .null, value: .null) }),
            [0xdf, 0x00, 0x01, 0x00, 0x00] + Array(repeating: 0xc0, count: 131_072)
        ),
        ("fixext1", .ext(type: 5, data: Data([0xaa])), [0xd4, 0x05, 0xaa]),
        ("ext8", .ext(type: -1, data: Data([1, 2, 3])), [0xc7, 0x03, 0xff, 0x01, 0x02, 0x03])
    ]

    @Test("MessagePack encodes and decodes every format as known bytes")
    func knownVectors() throws {
        for vector in Self.vectors {
            #expect(Array(MessagePack.encode(vector.value)) == vector.bytes, "encode \(vector.name)")
            #expect(try MessagePack.decode(Data(vector.bytes)) == vector.value, "decode \(vector.name)")
        }
    }

    @Test("MessagePack encodes a signed integer in the smallest format")
    func signedIntegersPickSmallestFormat() {
        #expect(Array(MessagePack.encode(.int(5))) == [0x05])
        #expect(Array(MessagePack.encode(.int(200))) == [0xcc, 0xc8])
        #expect(Array(MessagePack.encode(.int(70_000))) == [0xce, 0x00, 0x01, 0x11, 0x70])
        #expect(MessagePackValue.int(5) == .uint(5))
        #expect(MessagePackValue.int(-5) != .uint(5))
    }

    @Test("MessagePack reads integers in any width, as the server may send them")
    func integersInAnyWidth() throws {
        let encodings: [[UInt8]] = [
            [0x07],
            [0xcc, 0x07],
            [0xcd, 0x00, 0x07],
            [0xce, 0x00, 0x00, 0x00, 0x07],
            [0xcf, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07],
            [0xd0, 0x07],
            [0xd1, 0x00, 0x07],
            [0xd2, 0x00, 0x00, 0x00, 0x07],
            [0xd3, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07]
        ]
        for bytes in encodings {
            #expect(try MessagePack.decode(Data(bytes)).intValue == 7, "\(bytes)")
        }
        #expect(try MessagePack.decode(Data([0xca, 0x3f, 0xc0, 0x00, 0x00])).doubleValue == 1.5)
        #expect(try MessagePack.decode(Data([0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])).intValue == nil)
    }

    @Test("MessagePack round-trips nested values")
    func nestedRoundTrip() throws {
        let value = MessagePackValue.map([
            (key: .string("type"), value: .string("committed")),
            (key: .string("words"), value: .array([
                .map([(key: .string("text"), value: .string("hi")), (key: .string("start_ms"), value: .uint(300))])
            ])),
            (key: .string("score"), value: .double(-0.25)),
            (key: .string("data"), value: .binary(Data([0, 255]))),
            (key: .string("ok"), value: .bool(true)),
            (key: .string("none"), value: .null),
            (key: .string("delta"), value: .int(-40_000))
        ])

        let decoded = try MessagePack.decode(MessagePack.encode(value))

        #expect(decoded == value)
        #expect(decoded["words"]?.arrayValue?.first?["start_ms"]?.intValue == 300)
        #expect(decoded.mapKeys == ["type", "words", "score", "data", "ok", "none", "delta"])
    }

    @Test("MessagePack throws on every truncation instead of crashing")
    func truncatedInputThrows() throws {
        let samples = Self.vectors.filter { $0.bytes.count > 1 && $0.bytes.count < 1000 }.map(\.bytes) + [
            Array(MessagePack.encode(.map([(key: .string("audio"), value: .binary(Data(repeating: 1, count: 300)))])))
        ]
        for bytes in samples {
            for length in 0..<bytes.count {
                #expect(throws: MessagePackError.truncated) {
                    try MessagePack.decode(Data(bytes.prefix(length)))
                }
            }
        }

        // Lengths far beyond the input fail before allocating.
        for bytes: [UInt8] in [[0xdd, 0xff, 0xff, 0xff, 0xff], [0xdf, 0xff, 0xff, 0xff, 0xff], [0xdb, 0xff, 0xff, 0xff, 0xff], [0xc6, 0xff, 0xff, 0xff, 0xff]] {
            #expect(throws: MessagePackError.truncated) {
                try MessagePack.decode(Data(bytes))
            }
        }
    }

    @Test("MessagePack rejects 32-bit lengths beyond the input for every length-prefixed type")
    func oversized32BitLengthsThrow() {
        // On 32-bit watchOS these lengths exceed Int; decoding must throw, never trap.
        for format: UInt8 in [0xc6, 0xc9, 0xdb, 0xdd, 0xdf] {
            #expect(throws: MessagePackError.truncated) {
                try MessagePack.decode(Data([format, 0xff, 0xff, 0xff, 0xff, 0x00]))
            }
        }
    }

    @Test("MessagePack rejects the unused format byte, trailing bytes, and runaway nesting")
    func malformedInputThrows() {
        #expect(throws: MessagePackError.invalidFormat(0xc1)) {
            try MessagePack.decode(Data([0xc1]))
        }
        #expect(throws: MessagePackError.trailingBytes) {
            try MessagePack.decode(Data([0xc0, 0xc0]))
        }
        #expect(throws: MessagePackError.nestingTooDeep) {
            try MessagePack.decode(Data(Array(repeating: 0x91, count: 100) + [0xc0]))
        }
    }
}

// MARK: - Messages and options

@Suite("Fish Audio Realtime Messages")
struct FishAudioRealtimeMessageTests {
    /// Every field Fish Audio documents for `config`. Anything else is a fatal `invalid_config`.
    static let documentedConfigKeys: [String: Set<String>] = [
        "": ["type", "protocol_version", "audio", "turn_detection", "results", "context", "client_reference_id"],
        "audio": ["format", "sample_rate", "channels"],
        "turn_detection": ["mode", "eager", "silence_timeout_ms"],
        "results": ["drafts", "ignore_timestamps", "diarize", "vad_events", "eot_events"],
        "context": ["history", "terms"]
    ]

    @Test("Fish Audio config encodes the transcription defaults with documented fields only")
    func configDefaults() throws {
        let config = try MessagePack.decode(FishAudioRealtimeOptions().configMessage().encoded())

        #expect(config.mapKeys == ["type", "audio", "turn_detection", "results"])
        #expect(config["type"] == .string("config"))
        #expect(config["audio"] == .map([
            (key: .string("format"), value: .string("pcm_s16le")),
            (key: .string("sample_rate"), value: .uint(16000)),
            (key: .string("channels"), value: .uint(1))
        ]))
        #expect(config["turn_detection"] == .map([
            (key: .string("mode"), value: .string("auto")),
            (key: .string("eager"), value: .bool(false))
        ]))
        #expect(config["results"] == .map([
            (key: .string("drafts"), value: .bool(true)),
            (key: .string("ignore_timestamps"), value: .bool(false)),
            (key: .string("diarize"), value: .bool(true))
        ]))
        try expectOnlyDocumentedKeys(config)
    }

    @Test("Fish Audio config encodes every option with documented fields only")
    func configEveryOption() throws {
        let options = FishAudioRealtimeOptions(
            mode: .vad,
            eager: true,
            silenceTimeout: 0.7,
            drafts: false,
            timestamps: false,
            diarize: false,
            terms: ["Fish Audio", "SpeechKit"],
            history: [FishAudioContextItem(role: .assistant, text: "How can I help?")],
            sampleRate: 48000
        )
        let config = try MessagePack.decode(options.configMessage().encoded())

        #expect(config["audio"]?["sample_rate"]?.intValue == 48000)
        #expect(config["turn_detection"]?["mode"] == .string("vad"))
        #expect(config["turn_detection"]?["eager"] == .bool(true))
        #expect(config["turn_detection"]?["silence_timeout_ms"]?.intValue == 700)
        #expect(config["results"]?["drafts"] == .bool(false))
        #expect(config["results"]?["ignore_timestamps"] == .bool(true))
        #expect(config["results"]?["diarize"] == .bool(false))
        #expect(config["context"]?["terms"] == .array([.string("Fish Audio"), .string("SpeechKit")]))
        #expect(config["context"]?["history"] == .array([.map([
            (key: .string("role"), value: .string("assistant")),
            (key: .string("text"), value: .string("How can I help?"))
        ])]))
        try expectOnlyDocumentedKeys(config)
    }

    @Test("Fish Audio control messages encode as exact bytes")
    func controlMessageBytes() {
        let typeKey: [UInt8] = [0xa4] + Array("type".utf8)
        let singleField: [UInt8] = [0x81] + typeKey
        let twoFields: [UInt8] = [0x82] + typeKey

        func singleControl(_ name: String, marker: UInt8) -> [UInt8] {
            var expected = singleField
            expected.append(marker)
            expected.append(contentsOf: name.utf8)
            return expected
        }

        #expect(Array(FishAudioRealtimeClientMessage.keepalive.encoded()) == singleControl("keepalive", marker: 0xa9))
        #expect(Array(FishAudioRealtimeClientMessage.audioDone.encoded()) == singleControl("audio_done", marker: 0xaa))
        #expect(Array(FishAudioRealtimeClientMessage.finalize.encoded()) == singleControl("finalize", marker: 0xa8))

        // {"type": "agent_speaking", "speaking": true}
        var speaking = twoFields
        speaking.append(0xae)
        speaking.append(contentsOf: "agent_speaking".utf8)
        speaking.append(0xa8)
        speaking.append(contentsOf: "speaking".utf8)
        speaking.append(0xc3)
        #expect(Array(FishAudioRealtimeClientMessage.agentSpeaking(true).encoded()) == speaking)

        // {"type": "audio", "data": bin8}
        var audio = twoFields
        audio.append(0xa5)
        audio.append(contentsOf: "audio".utf8)
        audio.append(0xa4)
        audio.append(contentsOf: "data".utf8)
        audio.append(contentsOf: [0xc4, 0x04, 1, 2, 3, 4])
        #expect(Array(FishAudioRealtimeClientMessage.audio(Data([1, 2, 3, 4])).encoded()) == audio)
    }

    @Test("Fish Audio context_add and configure encode their fields")
    func contextAddAndConfigure() throws {
        let contextAdd = try MessagePack.decode(FishAudioRealtimeClientMessage.contextAdd(
            items: [FishAudioContextItem(role: .user, text: "Hi")],
            resetHistory: true
        ).encoded())
        #expect(contextAdd.mapKeys == ["type", "items", "reset_history"])
        #expect(contextAdd["type"] == .string("context_add"))
        #expect(contextAdd["reset_history"] == .bool(true))
        #expect(contextAdd["items"]?.arrayValue?.first?["role"] == .string("user"))

        let configure = try MessagePack.decode(FishAudioRealtimeClientMessage.configure(
            FishAudioRealtimeConfigureRequest(mode: .vad, silenceTimeout: 0.9, drafts: false, terms: ["Main Street"])
        ).encoded())
        #expect(configure.mapKeys == ["type", "turn_detection", "results", "context"])
        #expect(configure["turn_detection"]?.mapKeys == ["mode", "silence_timeout_ms"])
        #expect(configure["turn_detection"]?["silence_timeout_ms"]?.intValue == 900)
        #expect(configure["results"]?.mapKeys == ["drafts"])
        #expect(configure["context"]?.mapKeys == ["terms"])
    }

    @Test("Fish Audio server messages decode, ignoring unknown fields and types")
    func serverMessagesDecode() throws {
        #expect(try decodeServer(["type": .string("session_started"), "seq": .uint(0), "session_id": .string("s_1"), "request_id": .string("r_1"), "limits": .map([])])
            == .sessionStarted(sessionID: "s_1", requestID: "r_1"))
        #expect(try decodeServer(["type": .string("speech_start"), "turn_index": .uint(2), "audio_ms": .uint(300)])
            == .speechStart(turnIndex: 2, audioMilliseconds: 300))
        #expect(try decodeServer(["type": .string("draft"), "turn_index": .uint(0), "text": .string("hi"), "settled_text": .string(""), "brand_new_field": .array([])])
            == .draft(FishAudioRealtimeDraft(turnIndex: 0, text: "hi", settledText: "", languageCode: nil)))
        #expect(try decodeServer(["type": .string("configured"), "ok": .bool(false), "message": .string("bad")])
            == .configured(ok: false, message: "bad"))
        #expect(try decodeServer(["type": .string("session_done"), "stats": .map([(key: .string("request_id"), value: .string("r_1"))])])
            == .sessionDone(requestID: "r_1"))
        #expect(try decodeServer(["type": .string("error"), "code": .uint(503), "error_type": .string("server_restarting"), "recoverable": .bool(true)])
            == .error(FishAudioRealtimeServerError(code: 503, errorType: "server_restarting", message: nil, requestID: nil, recoverable: true)))
        #expect(try decodeServer(["type": .string("vad"), "audio_ms": .uint(100), "score": .float(0.5)]) == .vad(audioMilliseconds: 100, score: 0.5))
        #expect(try decodeServer(["type": .string("eot_prob"), "turn_index": .uint(1), "prob": .double(0.25)]) == .eotProbability(turnIndex: 1, probability: 0.25))
        #expect(try decodeServer(["type": .string("progress"), "audio_received_ms": .uint(5000)]) == .progress)
        #expect(try decodeServer(["type": .string("user_turn_taken"), "turn_index": .uint(1)]) == .userTurnTaken(turnIndex: 1))
        #expect(try decodeServer(["type": .string("user_backchannel"), "turn_index": .uint(1)]) == .userBackchannel(turnIndex: 1))
        #expect(try decodeServer(["type": .string("eager_end_of_turn"), "turn_index": .uint(1), "text": .string("ok")]) == .eagerEndOfTurn(turnIndex: 1, text: "ok"))
        #expect(try decodeServer(["type": .string("turn_resumed"), "turn_index": .uint(1)]) == .turnResumed(turnIndex: 1))
        #expect(try decodeServer(["type": .string("translation"), "text": .string("hola")]) == .unknown("translation"))
        #expect(FishAudioRealtimeServerMessage(.array([])) == .unknown(""))
    }

    @Test("Fish Audio committed messages decode words, any integer width, and turn kinds")
    func committedDecodes() throws {
        let message = try decodeServer([
            "type": .string("committed"),
            "seq": .uint(6),
            "turn_index": .uint(0),
            "text": .string("<|speaker:0|>What's the weather like?"),
            "words": .array([
                .map([(key: .string("text"), value: .string("what's")), (key: .string("start_ms"), value: .uint(300)), (key: .string("end_ms"), value: .uint(65_600))])
            ]),
            "language": .string("English"),
            "language_code": .string("en"),
            "audio_start_ms": .uint(300),
            "audio_end_ms": .uint(70_000),
            "reason": .string("eot"),
            "degraded": .bool(false),
            "user_turn": .bool(true),
            "turn_kind": .string("user"),
            "audio_processed_ms": .uint(2880)
        ])
        guard case .committed(let commit) = message else {
            Issue.record("Expected a commit, got \(message)")
            return
        }
        #expect(commit.words == [FishAudioRealtimeWord(text: "what's", startMilliseconds: 300, endMilliseconds: 65_600)])
        #expect(commit.audioEndMilliseconds == 70_000)
        #expect(commit.turnKind == .user)
        #expect(commit.languageCode == "en")

        // A missing user_turn counts as true; an unknown kind on a non-user turn is "other".
        guard case .committed(let missingUserTurn) = try decodeServer(["type": .string("committed"), "text": .string("Hi")]),
              case .committed(let unknownKind) = try decodeServer(["type": .string("committed"), "text": .string("Hi"), "user_turn": .bool(false), "turn_kind": .string("music")]),
              case .committed(let backchannel) = try decodeServer(["type": .string("committed"), "text": .string("Mm-hm."), "user_turn": .bool(false), "turn_kind": .string("backchannel")]) else {
            Issue.record("Expected commits")
            return
        }
        #expect(missingUserTurn.userTurn && missingUserTurn.turnKind == .user)
        #expect(missingUserTurn.words == nil)
        #expect(unknownKind.turnKind == .other)
        #expect(backchannel.turnKind == .backchannel)
    }

    @Test("Fish Audio realtime options validate every limit before connecting")
    func optionsValidate() throws {
        try FishAudioRealtimeOptions().validate()
        try FishAudioRealtimeOptions(mode: .auto, silenceTimeout: 3).validate()
        try FishAudioRealtimeOptions(mode: .auto, silenceTimeout: 60).validate()
        try FishAudioRealtimeOptions(mode: .vad, silenceTimeout: 0.3).validate()
        try FishAudioRealtimeOptions(mode: .manual, silenceTimeout: 60).validate()
        try FishAudioRealtimeOptions(terms: Array(repeating: String(repeating: "x", count: 32), count: 100)).validate()
        try FishAudioRealtimeOptions(history: Array(repeating: FishAudioContextItem(role: .user, text: String(repeating: "x", count: 2000)), count: 32)).validate()
        for rate in FishAudioRealtimeOptions.supportedSampleRates {
            try FishAudioRealtimeOptions(sampleRate: rate).validate()
        }

        let invalid: [(FishAudioRealtimeOptions, String)] = [
            (FishAudioRealtimeOptions(mode: .auto, silenceTimeout: 0.7), "silenceTimeout must be between 3.0 and 60.0 seconds in auto mode."),
            (FishAudioRealtimeOptions(mode: .auto, silenceTimeout: 60.001), "silenceTimeout must be between 3.0 and 60.0 seconds in auto mode."),
            (FishAudioRealtimeOptions(mode: .vad, silenceTimeout: 0.299), "silenceTimeout must be between 0.3 and 60.0 seconds in vad mode."),
            (FishAudioRealtimeOptions(mode: .manual, silenceTimeout: 61), "silenceTimeout must be between 0.3 and 60.0 seconds in manual mode."),
            (FishAudioRealtimeOptions(mode: .vad, silenceTimeout: .nan), "silenceTimeout must be between 0.3 and 60.0 seconds in vad mode."),
            (FishAudioRealtimeOptions(mode: .vad, silenceTimeout: .infinity), "silenceTimeout must be between 0.3 and 60.0 seconds in vad mode."),
            (FishAudioRealtimeOptions(mode: .vad, silenceTimeout: 1e300), "silenceTimeout must be between 0.3 and 60.0 seconds in vad mode."),
            (FishAudioRealtimeOptions(terms: Array(repeating: "x", count: 101)), "terms cannot contain more than 100 entries."),
            (FishAudioRealtimeOptions(terms: [String(repeating: "x", count: 33)]), "terms cannot be longer than 32 Unicode code points: \"\(String(repeating: "x", count: 33))\"."),
            (FishAudioRealtimeOptions(terms: [" "]), "terms cannot contain empty entries."),
            (FishAudioRealtimeOptions(history: Array(repeating: FishAudioContextItem(role: .user, text: "x"), count: 33)), "history cannot contain more than 32 items."),
            (FishAudioRealtimeOptions(history: [FishAudioContextItem(role: .user, text: String(repeating: "x", count: 2001))]), "history items cannot be longer than 2000 Unicode code points."),
            (FishAudioRealtimeOptions(sampleRate: 44000), "Unsupported realtime sampleRate: 44000. Use 8000, 12000, 16000, 22050, 24000, 32000, 44100, or 48000.")
        ]
        for (options, _) in invalid {
            #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
                try options.validate()
            }
        }
    }

    @Test("Fish Audio converts silence timeouts to milliseconds with a checked conversion")
    func wholeMilliseconds() {
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(0.7) == 700)
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(60) == 60_000)
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(.nan) == nil)
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(.infinity) == nil)
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(1e300) == nil)
        #expect(FishAudioRealtimeOptions.wholeMilliseconds(1e17) == nil)
    }

    @Test("Fish Audio counts term and history lengths in Unicode code points")
    func lengthsCountCodePoints() throws {
        let decomposedE = "e\u{0301}"
        #expect(decomposedE.count == 1)
        #expect(decomposedE.unicodeScalars.count == 2)

        try FishAudioRealtimeOptions(terms: [String(repeating: decomposedE, count: 16)]).validate()
        let longTerm = String(repeating: decomposedE, count: 17)
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioRealtimeOptions(terms: [longTerm]).validate()
        }

        try FishAudioRealtimeOptions(history: [FishAudioContextItem(role: .user, text: String(repeating: decomposedE, count: 1000))]).validate()
        #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try FishAudioRealtimeOptions(history: [FishAudioContextItem(role: .user, text: String(repeating: decomposedE, count: 1001))]).validate()
        }
    }

    @Test("Fish Audio realtime connect request carries the bearer and model headers")
    func connectRequest() throws {
        let request = try FishAudioRealtimeWebSocket.makeConnectRequest(credential: .apiKey("fish-key"), options: FishAudioRealtimeOptions())
        #expect(request.url?.absoluteString == "wss://api.fish.audio/v1/asr/realtime")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fish-key")
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-stream-1")

        let endpoint = try #require(URL(string: "wss://proxy.example.com/fish/realtime"))
        let proxied = try FishAudioRealtimeWebSocket.makeConnectRequest(credential: .bearer("fish-token"), options: FishAudioRealtimeOptions(), endpoint: endpoint)
        #expect(proxied.url == endpoint)
        #expect(proxied.value(forHTTPHeaderField: "Authorization") == "Bearer fish-token")

        #expect(throws: SpeechFailure(.invalidCredential)) {
            try FishAudioRealtimeWebSocket.makeConnectRequest(credential: .apiKey(""), options: FishAudioRealtimeOptions())
        }
    }

    @Test("Fish Audio realtime errors describe close codes and HTTP refusals")
    func errorDescriptions() {
        #expect(FishAudioRealtimeError.connectionRefused(statusCode: 401).errorDescription == "Fish Audio rejected the API key (HTTP 401)")
        #expect(FishAudioRealtimeError.connectionRefused(statusCode: 402).errorDescription == "The Fish Audio account has no remaining credit (HTTP 402)")
        #expect(FishAudioRealtimeError.connectionRefused(statusCode: 429).isRetryable)
        #expect(FishAudioRealtimeError.connectionRefused(statusCode: 503).isRetryable)
        #expect(!FishAudioRealtimeError.connectionRefused(statusCode: 401).isRetryable)
        #expect(FishAudioRealtimeError.sessionClosed(code: 4400).errorDescription
            == "Fish Audio rejected the session configuration or audio (close 4400)")
        #expect(FishAudioRealtimeError.sessionClosed(code: 4408).errorDescription == "Fish Audio closed the idle session (close 4408)")
        #expect(FishAudioRealtimeError.sessionClosed(code: 4413).errorDescription == "The session reached Fish Audio's 60-minute limit (close 4413)")
        #expect(FishAudioRealtimeError.sessionClosed(code: 4500).isRetryable)
        #expect(FishAudioRealtimeError.sessionClosed(code: 1009).errorDescription == "An audio message exceeded Fish Audio's 1 MiB frame limit (close 1009)")
        #expect(FishAudioRealtimeError.serverRestarting.isRetryable)
    }
}

// MARK: - Transcript mapping

@Suite("Fish Audio Realtime Mapping")
@MainActor
struct FishAudioRealtimeMappingTests {
    @Test("Fish Audio service connects on session_started and ignores a duplicate")
    func connectsOnSessionStarted() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")
        service.setLifecycleStateForTesting(.connecting)

        service.handleMessageForTesting(.sessionStarted(sessionID: "s_1", requestID: "r_1"))
        service.handleMessageForTesting(.sessionStarted(sessionID: "s_2", requestID: "r_2"))

        #expect(service.connectionState == .connected(sessionID: "s_1"))
    }

    @Test("Fish Audio drafts replace each other as one partial entry keyed by turn")
    func draftReplacement() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")

        service.handleMessageForTesting(.speechStart(turnIndex: 3, audioMilliseconds: 1500))
        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 3, text: "<|speaker:1|>what's the", settledText: "", languageCode: nil)))
        let first = service.partialTranscriptEntry
        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 3, text: "<|speaker:1|> what's the weather [laughs]", settledText: "what's", languageCode: "en")))
        let second = service.partialTranscriptEntry

        #expect(service.partialTranscriptText == "what's the weather [laughs]")
        #expect(second?.id == first?.id)
        #expect(second?.sourceID == "3")
        #expect(second?.provider == .fishAudio)
        #expect(second?.isFinal == false)
        #expect(second?.isUtteranceFinal == false)
        #expect(second?.speaker == "speaker:1")
        #expect(second?.start == 1.5)
        #expect(service.transcriptEntries.isEmpty)

        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 4, text: "next", settledText: "", languageCode: nil)))
        #expect(service.partialTranscriptEntry?.id != first?.id)
        #expect(service.partialTranscriptEntry?.sourceID == "4")
    }

    @Test("Fish Audio commit becomes a final entry with seconds, words, and speaker")
    func commitMapping() throws {
        let service = FishAudioRealtimeService(apiKey: "fish-key")
        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 0, text: "what's the weather", settledText: "", languageCode: nil)))

        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(
            turnIndex: 0,
            text: "<|speaker:0|>What's the weather like? [laughs]",
            words: [
                FishAudioRealtimeWord(text: "what's", startMilliseconds: 300, endMilliseconds: 600),
                FishAudioRealtimeWord(text: "the", startMilliseconds: 600, endMilliseconds: 700),
                FishAudioRealtimeWord(text: "weather", startMilliseconds: 700, endMilliseconds: 1200),
                FishAudioRealtimeWord(text: "like", startMilliseconds: 1200, endMilliseconds: 1500)
            ],
            language: "English",
            languageCode: "en",
            audioStartMilliseconds: 300,
            audioEndMilliseconds: 2880
        )))

        #expect(service.partialTranscriptEntry == nil)
        #expect(service.partialTranscriptText.isEmpty)
        let entry = try #require(service.transcriptEntries.first)
        #expect(service.transcriptEntries.count == 1)
        #expect(entry.text == "What's the weather like? [laughs]")
        #expect(entry.sourceID == "0")
        #expect(entry.isFinal)
        #expect(entry.isUtteranceFinal)
        #expect(entry.speaker == "speaker:0")
        #expect(entry.start == 0.3)
        #expect(abs((entry.duration ?? 0) - 2.58) < 0.000_1)
        #expect(entry.words.map(\.text) == ["What's", "the", "weather", "like?"])
        #expect(entry.words.map(\.start) == [0.3, 0.6, 0.7, 1.2])
        #expect(entry.words.map(\.end) == [0.6, 0.7, 1.2, 1.5])
        #expect(entry.words.allSatisfy { $0.speaker == "speaker:0" })

        let turn = try #require(service.turn(for: entry))
        #expect(turn.kind == .user)
        #expect(turn.isUserTurn)
        #expect(turn.reason == "eot")
        #expect(turn.languageCode == "en")
        #expect(turn.entryIDs == [entry.id])
        #expect(service.committedTurns == [turn])
    }

    @Test("Fish Audio splits a multi-speaker commit into one entry per speaker")
    func multiSpeakerSplit() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")

        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(
            turnIndex: 5,
            text: "<|speaker:0|>Can you hear me? <|speaker:1|> Yes, loud and clear.",
            words: [
                FishAudioRealtimeWord(text: "can", startMilliseconds: 1000, endMilliseconds: 1200),
                FishAudioRealtimeWord(text: "you", startMilliseconds: 1200, endMilliseconds: 1300),
                FishAudioRealtimeWord(text: "hear", startMilliseconds: 1300, endMilliseconds: 1500),
                FishAudioRealtimeWord(text: "me", startMilliseconds: 1500, endMilliseconds: 1700),
                FishAudioRealtimeWord(text: "yes", startMilliseconds: 2000, endMilliseconds: 2200),
                FishAudioRealtimeWord(text: "loud", startMilliseconds: 2300, endMilliseconds: 2500),
                FishAudioRealtimeWord(text: "and", startMilliseconds: 2500, endMilliseconds: 2600),
                FishAudioRealtimeWord(text: "clear", startMilliseconds: 2600, endMilliseconds: 3000)
            ],
            audioStartMilliseconds: 900,
            audioEndMilliseconds: 3200
        )))

        let entries = service.transcriptEntries
        #expect(entries.map(\.text) == ["Can you hear me?", "Yes, loud and clear."])
        #expect(entries.map(\.speaker) == ["speaker:0", "speaker:1"])
        #expect(entries.map(\.sourceID) == ["5", "5"])
        #expect(entries.map(\.start) == [1.0, 2.0])
        #expect(entries.map { $0.words.map(\.text) } == [["Can", "you", "hear", "me?"], ["Yes,", "loud", "and", "clear."]])
        #expect(entries[1].words.allSatisfy { $0.speaker == "speaker:1" })
        #expect(abs((entries[0].duration ?? 0) - 0.7) < 0.000_1)
        #expect(abs((entries[1].duration ?? 0) - 1.0) < 0.000_1)
        #expect(service.committedTurns.first?.entryIDs == entries.map(\.id))
    }

    @Test("Fish Audio aligns several timed words to one CJK token when splitting speakers")
    func cjkSplit() {
        let entries = FishAudioRealtimeMapping.entries(for: FishAudioRealtimeCommit(
            turnIndex: 0,
            text: "<|speaker:0|>你好。<|speaker:1|>再见。",
            words: [
                FishAudioRealtimeWord(text: "你", startMilliseconds: 0, endMilliseconds: 200),
                FishAudioRealtimeWord(text: "好", startMilliseconds: 200, endMilliseconds: 400),
                FishAudioRealtimeWord(text: "再", startMilliseconds: 800, endMilliseconds: 1000),
                FishAudioRealtimeWord(text: "见", startMilliseconds: 1000, endMilliseconds: 1200)
            ],
            audioStartMilliseconds: 0,
            audioEndMilliseconds: 1300
        ))

        #expect(entries.map(\.text) == ["你好。", "再见。"])
        #expect(entries.map { $0.words.map(\.text) } == [["你", "好"], ["再", "见"]])
        #expect(entries.map(\.start) == [0, 0.8])
        #expect(entries.allSatisfy { abs(($0.duration ?? 0) - 0.4) < 0.000_1 })
    }

    @Test("Fish Audio aligns mixed CJK and Latin words when splitting speakers")
    func mixedSplit() {
        let groups = FishAudioRealtimeMapping.distribute(
            ["我们", "用", "speechkit", "ok", "好的"].map { FishAudioRealtimeWord(text: $0, startMilliseconds: nil, endMilliseconds: nil) },
            across: FishAudioRealtimeMapping.speakerParts(in: "<|speaker:0|>我们用 SpeechKit。<|speaker:1|>OK, 好的。")
        )

        #expect(groups.map { $0.map(\.text) } == [["我们", "用", "speechkit"], ["ok", "好的"]])
    }

    @Test("Fish Audio keeps unaligned words only where both neighbours agree on the speaker")
    func unalignedWordsAreNotMisattributed() {
        let inside = FishAudioRealtimeMapping.distribute(
            ["i", "have", "three", "point", "five", "apples", "nice"].map { FishAudioRealtimeWord(text: $0, startMilliseconds: nil, endMilliseconds: nil) },
            across: FishAudioRealtimeMapping.speakerParts(in: "<|speaker:0|>I have 3.5 apples. <|speaker:1|>Nice.")
        )
        #expect(inside.map { $0.map(\.text) } == [["i", "have", "three", "point", "five", "apples"], ["nice"]])

        // A normalised word at the boundary is left out rather than given to the wrong speaker.
        let boundary = FishAudioRealtimeMapping.distribute(
            ["it", "costs", "three-fifty", "okay"].map { FishAudioRealtimeWord(text: $0, startMilliseconds: nil, endMilliseconds: nil) },
            across: FishAudioRealtimeMapping.speakerParts(in: "<|speaker:0|>It costs $3.50. <|speaker:1|>Okay.")
        )
        #expect(boundary.map { $0.map(\.text) } == [["it", "costs"], ["okay"]])
    }

    @Test("Fish Audio splits speaker tags without words using the turn bounds")
    func multiSpeakerSplitWithoutWords() {
        let entries = FishAudioRealtimeMapping.entries(for: FishAudioRealtimeCommit(
            turnIndex: 1,
            text: "Before tags <|speaker:0|>Hello. <|speaker:1|>Hi!",
            audioStartMilliseconds: 1000,
            audioEndMilliseconds: 4000
        ))

        #expect(entries.map(\.text) == ["Before tags", "Hello.", "Hi!"])
        #expect(entries.map(\.speaker) == [nil, "speaker:0", "speaker:1"])
        #expect(entries.map(\.start) == [1.0, nil, nil])
        #expect(entries.last?.duration == nil)
        #expect(entries.allSatisfy { $0.words.isEmpty })
    }

    @Test("Fish Audio emits a degraded commit without words")
    func degradedCommit() throws {
        let service = FishAudioRealtimeService(apiKey: "fish-key")

        service.handleMessageForTesting(.error(FishAudioRealtimeServerError(code: 500, errorType: "engine_error", message: "final pass failed", requestID: nil, recoverable: true)))
        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(
            turnIndex: 2,
            text: "what's the weather",
            words: [FishAudioRealtimeWord(text: "what's", startMilliseconds: 0, endMilliseconds: 100)],
            audioStartMilliseconds: 0,
            audioEndMilliseconds: 1000,
            reason: "eot",
            degraded: true
        )))

        let entry = try #require(service.transcriptEntries.first)
        #expect(entry.text == "what's the weather")
        #expect(entry.words.isEmpty)
        #expect(entry.duration == 1)
        #expect(service.turn(for: entry)?.isDegraded == true)
        // A recoverable engine error is reported but does not end the session.
        #expect(service.lastError as? FishAudioRealtimeError == .serverError(code: 500))
        #expect(service.connectionState == .disconnected)
    }

    @Test("Fish Audio keeps non-user turns and tags them with their kind")
    func nonUserTurnsKept() throws {
        let service = FishAudioRealtimeService(apiKey: "fish-key")

        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: 0, text: "Turn the TV down.", userTurn: false, turnKind: .other)))
        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: 1, text: "Mm-hm.", userTurn: false, turnKind: .backchannel)))
        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: 2, text: "Thanks.", userTurn: true)))

        #expect(service.transcriptText == "Turn the TV down. Mm-hm. Thanks.")
        #expect(service.committedTurns.map(\.kind) == [.other, .backchannel, .user])
        #expect(service.transcriptEntries.map { service.turn(for: $0)?.isUserTurn } == [false, false, true])
    }

    @Test("Fish Audio drops empty and tag-only turns")
    func emptyAndTagOnlyTurnsDropped() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")
        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 0, text: "uh", settledText: "", languageCode: nil)))

        for (index, text) in ["", "   ", "[cough]", "<|speaker:0|> [noise] [music]", "<|speaker:1|>"].enumerated() {
            service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: index, text: text, userTurn: false)))
        }

        #expect(service.transcriptEntries.isEmpty)
        #expect(service.committedTurns.isEmpty)
        // The dropped commit still closes its draft.
        #expect(service.partialTranscriptEntry == nil)
    }

    @Test("Fish Audio clears committed turns with the transcript")
    func clearTranscript() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")
        service.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: 0, text: "Hello.")))
        service.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 1, text: "Next", settledText: "", languageCode: nil)))

        service.clearTranscript()

        #expect(service.transcriptEntries.isEmpty)
        #expect(service.committedTurns.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
    }

    @Test("Fish Audio ignores message types it does not use")
    func ignoresOtherMessages() {
        let service = FishAudioRealtimeService(apiKey: "fish-key")
        service.setLifecycleStateForTesting(.listening)

        for message: FishAudioRealtimeServerMessage in [
            .unknown("translation"), .unknown("decode_error"), .progress, .vad(audioMilliseconds: 0, score: 0.1),
            .eotProbability(turnIndex: 0, probability: 0.5), .userTurnTaken(turnIndex: 0), .userBackchannel(turnIndex: 0),
            .eagerEndOfTurn(turnIndex: 0, text: "Hi"), .turnResumed(turnIndex: 0), .configured(ok: true, message: nil)
        ] {
            service.handleMessageForTesting(message)
        }

        #expect(service.connectionState == .listening)
        #expect(service.lastError == nil)
        #expect(service.transcriptEntries.isEmpty)
        #expect(service.partialTranscriptEntry == nil)
    }

    @Test("Fish Audio service rejects a missing key and invalid options before connecting")
    func rejectsBeforeConnecting() async {
        let missingKey = FishAudioRealtimeService()
        await missingKey.startListening()
        #expect(missingKey.connectionState == .error("Fish Audio is not configured"))
        #expect(missingKey.lastError as? FishAudioRealtimeError == .apiKeyMissing)

        let invalid = FishAudioRealtimeService(apiKey: "fish-key", options: FishAudioRealtimeOptions(mode: .auto, silenceTimeout: 1))
        await invalid.startListening()
        #expect(invalid.lastError as? SpeechError == .providerFailure(provider: .fishAudio, reason: .requestFailed))
        #expect(invalid.connectionState.isLifecycleActive == false)
    }

    @Test("Fish Audio session methods require an open session and valid context")
    func sessionMethodsRequireSession() async {
        let service = FishAudioRealtimeService(apiKey: "fish-key")

        await #expect(throws: FishAudioRealtimeError.disconnected) {
            try await service.agentSpeaking(true)
        }
        await #expect(throws: FishAudioRealtimeError.disconnected) {
            try await service.finalizeTurn()
        }
        await #expect(throws: SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)) {
            try await service.addContext(Array(repeating: FishAudioContextItem(role: .assistant, text: "x"), count: 33))
        }
    }
}

// MARK: - Session lifecycle over a fake socket

@Suite("Fish Audio Realtime Session")
@MainActor
struct FishAudioRealtimeSessionTests {
    @Test("Fish Audio sends config first and reports connected only on session_started")
    func configThenSessionStarted() async throws {
        let harness = FishAudioHarness()
        await harness.service.startListening()

        try await harness.waitUntil { harness.socket.sentMessages.count == 1 }
        #expect(harness.socket.sentTypes == ["config"])
        #expect(harness.service.connectionState == .connecting)
        #expect(harness.audio.isCapturing == false)

        let request = try #require(harness.socket.request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fish-key")
        #expect(request.value(forHTTPHeaderField: "model") == "transcribe-stream-1")

        harness.socket.pushServer(["type": .string("session_started"), "seq": .uint(0), "session_id": .string("s_1"), "request_id": .string("r_1")])
        try await harness.waitUntil { harness.service.connectionState == .listening }
        #expect(harness.audio.isCapturing)

        await harness.service.stopListening()
    }

    @Test("Fish Audio streams 100 ms audio messages and shuts down via audio_done and session_done")
    func audioThenGracefulShutdown() async throws {
        let harness = FishAudioHarness()
        harness.socket.answersAudioDoneLikeServer = false
        try await harness.start()

        // 250 ms of 16 kHz PCM16 in uneven pieces: two full 100 ms messages, then a 50 ms remainder at stop.
        harness.audio.feed(Data(repeating: 1, count: 3000))
        harness.audio.feed(Data(repeating: 2, count: 5000))
        try await harness.waitUntil { harness.socket.sentTypes.filter { $0 == "audio" }.count == 2 }

        harness.socket.pushServer(["type": .string("speech_start"), "turn_index": .uint(0), "audio_ms": .uint(0)])
        harness.socket.pushServer(["type": .string("draft"), "turn_index": .uint(0), "text": .string("hello"), "settled_text": .string("")])
        try await harness.waitUntil { harness.service.partialTranscriptText == "hello" }

        let stopTask = Task { await harness.service.stopListening() }
        try await harness.waitUntil { harness.socket.sentTypes.last == "audio_done" }
        #expect(harness.service.connectionState == .stopping)

        harness.socket.pushServer([
            "type": .string("committed"), "turn_index": .uint(0), "text": .string("Hello."),
            "audio_start_ms": .uint(0), "audio_end_ms": .uint(250), "reason": .string("audio_done"),
            "degraded": .bool(false), "user_turn": .bool(true), "turn_kind": .string("user")
        ])
        harness.socket.pushServer(["type": .string("session_done"), "stats": .map([(key: .string("turns"), value: .uint(1))])])
        harness.socket.push(.closed(code: 1000, reason: nil))
        await stopTask.value

        #expect(harness.socket.sentTypes == ["config", "audio", "audio", "audio", "audio_done"])
        let audioSizes = harness.socket.sentMessages.compactMap { $0["data"]?.binaryValue?.count }
        #expect(audioSizes == [3200, 3200, 1600])
        #expect(harness.service.transcriptText == "Hello.")
        #expect(harness.service.committedTurns.first?.reason == "audio_done")
        #expect(harness.service.connectionState == .disconnected)
        #expect(harness.service.lastError == nil)
        #expect(harness.service.partialTranscriptEntry == nil)
        #expect(harness.socket.isClosed)
    }

    @Test("Fish Audio stops after the timeout when session_done never arrives")
    func gracefulStopTimesOut() async throws {
        let harness = FishAudioHarness(gracefulStopTimeout: .milliseconds(100))
        harness.socket.answersAudioDoneLikeServer = false
        try await harness.start()

        await harness.service.stopListening()

        #expect(harness.socket.sentTypes.last == "audio_done")
        #expect(harness.service.connectionState == .disconnected)
        #expect(harness.socket.isClosed)
    }

    @Test("Fish Audio surfaces server_restarting without reconnecting")
    func serverRestarting() async throws {
        let harness = FishAudioHarness()
        try await harness.start()

        harness.socket.pushServer(["type": .string("error"), "code": .uint(503), "error_type": .string("server_restarting"), "recoverable": .bool(true)])
        harness.socket.pushServer(["type": .string("committed"), "turn_index": .uint(0), "text": .string("Half a"), "reason": .string("finalize")])
        harness.socket.push(.closed(code: 1012, reason: nil))

        try await harness.waitUntil { !harness.service.connectionState.isLifecycleActive }
        #expect(harness.service.lastError as? FishAudioRealtimeError == .serverRestarting)
        #expect(harness.service.connectionState == .error("Fish Audio is restarting; start a new session"))
        #expect(harness.service.transcriptText == "Half a")
        #expect(harness.factoryCallCount == 1)
    }

    @Test("Fish Audio maps an error close code with the preceding error message")
    func errorCloseCode() async throws {
        let harness = FishAudioHarness()
        await harness.service.startListening()
        try await harness.waitUntil { harness.socket.sentMessages.count == 1 }

        harness.socket.pushServer(["type": .string("error"), "code": .uint(400), "error_type": .string("invalid_config"), "message": .string("unknown field: foo"), "recoverable": .bool(false)])
        harness.socket.push(.closed(code: 4400, reason: nil))

        try await harness.waitUntil { !harness.service.connectionState.isLifecycleActive }
        #expect(harness.service.lastError as? FishAudioRealtimeError == .sessionClosed(code: 4400))
    }

    @Test("Fish Audio reports a refused upgrade and an idle close")
    func refusedAndIdle() async throws {
        let refused = FishAudioHarness()
        refused.socket.failReceive(with: FishAudioRealtimeError.connectionRefused(statusCode: 402))
        await refused.service.startListening()
        try await refused.waitUntil { !refused.service.connectionState.isLifecycleActive }
        #expect(refused.service.lastError as? FishAudioRealtimeError == .connectionRefused(statusCode: 402))

        let idle = FishAudioHarness()
        try await idle.start()
        idle.socket.push(.closed(code: 4408, reason: "idle"))
        try await idle.waitUntil { !idle.service.connectionState.isLifecycleActive }
        #expect(idle.service.lastError as? FishAudioRealtimeError == .sessionClosed(code: 4408))
    }

    @Test("Fish Audio fails the session when session_started never arrives")
    func handshakeTimeout() async throws {
        let harness = FishAudioHarness(handshakeTimeout: .milliseconds(100))
        await harness.service.startListening()

        try await harness.waitUntil { !harness.service.connectionState.isLifecycleActive }
        #expect(harness.service.lastError as? FishAudioRealtimeError == .handshakeTimedOut)
    }

    @Test("Fish Audio stop during the credential fetch cancels the pending start")
    func stopDuringCredentialFetch() async throws {
        let gate = FishAudioGate()
        let harness = FishAudioHarness(credential: .bearer(SpeechTokenResolver { _ in
            await gate.wait()
            return "fetched-token"
        }))

        let start = Task { await harness.service.startListening() }
        try await harness.waitUntil { harness.service.connectionState == .connecting }
        await harness.service.stopListening()
        #expect(harness.service.connectionState == .disconnected)

        gate.open()
        await start.value
        try await Task.sleep(for: .milliseconds(100))

        #expect(harness.factoryCallCount == 0)
        #expect(harness.audio.isCapturing == false)
        #expect(harness.service.connectionState == .disconnected)
    }

    @Test("Fish Audio closes the session when the microphone fails to start")
    func microphoneFailureClosesSession() async throws {
        let harness = FishAudioHarness(keepaliveInterval: .milliseconds(50))
        harness.audio.failsOnStart = true
        await harness.service.startListening()
        try await harness.waitUntil { harness.socket.sentMessages.count == 1 }

        harness.socket.pushServer(["type": .string("session_started"), "session_id": .string("s_1")])

        try await harness.waitUntil { harness.socket.isClosed }
        #expect(harness.service.connectionState == .error("Failed to start audio capture"))
        #expect(harness.service.lastError as? SpeechAudioCaptureError == .audioEngineError(.requestFailed))
        // No keepalive keeps the billed session open afterwards.
        try await Task.sleep(for: .milliseconds(200))
        #expect(harness.socket.sentTypes == ["config"])
        #expect(harness.service.connectionState == .error("Failed to start audio capture"))
    }

    @Test("Fish Audio concurrent stops share one shutdown")
    func concurrentStopsShareOneShutdown() async throws {
        let harness = FishAudioHarness()
        harness.socket.answersAudioDoneLikeServer = false
        try await harness.start()

        let first = Task { await harness.service.stopListening() }
        let second = Task { await harness.service.stopListening() }
        try await harness.waitUntil { harness.socket.sentTypes.contains("audio_done") }
        try await Task.sleep(for: .milliseconds(50))
        harness.socket.pushServer(["type": .string("session_done")])
        harness.socket.push(.closed(code: 1000, reason: nil))
        await first.value
        await second.value

        #expect(harness.socket.sentTypes.filter { $0 == "audio_done" }.count == 1)
        #expect(harness.service.connectionState == .disconnected)
    }

    @Test("Fish Audio keeps draining after an error during stop, so the final commit lands")
    func maxDurationDuringStopKeepsFinalCommit() async throws {
        let harness = FishAudioHarness()
        harness.socket.answersAudioDoneLikeServer = false
        try await harness.start()

        let stop = Task { await harness.service.stopListening() }
        try await harness.waitUntil { harness.socket.sentTypes.last == "audio_done" }
        harness.socket.pushServer(["type": .string("error"), "code": .uint(413), "error_type": .string("max_duration_exceeded"), "message": .string("limit"), "recoverable": .bool(false)])
        try await Task.sleep(for: .milliseconds(50))
        harness.socket.pushServer(["type": .string("committed"), "turn_index": .uint(4), "text": .string("Last words."), "reason": .string("finalize")])
        harness.socket.push(.closed(code: 4413, reason: nil))
        await stop.value

        #expect(harness.service.transcriptText == "Last words.")
        #expect(harness.service.lastError as? FishAudioRealtimeError == .sessionClosed(code: 4413))
        #expect(harness.service.connectionState == .disconnected)
    }

    @Test("Fish Audio stop deadline covers a stalled audio send")
    func stopDeadlineCoversStalledSend() async throws {
        let harness = FishAudioHarness(gracefulStopTimeout: .milliseconds(200))
        try await harness.start()
        harness.socket.stallsSends = true
        harness.audio.feed(Data(repeating: 1, count: 3200))
        try await Task.sleep(for: .milliseconds(50))

        let began = ContinuousClock.now
        await harness.service.stopListening()

        #expect(ContinuousClock.now - began < .seconds(2))
        #expect(harness.service.connectionState == .disconnected)
        #expect(harness.socket.isClosed)
    }

    @Test("Fish Audio sends keepalive while no audio flows")
    func keepalive() async throws {
        let harness = FishAudioHarness(keepaliveInterval: .milliseconds(100))
        try await harness.start()

        try await harness.waitUntil { harness.socket.sentTypes.contains("keepalive") }
        await harness.service.stopListening()
    }

    @Test("Fish Audio ignores unknown message types and text frames during a session")
    func ignoresUnknownMessages() async throws {
        let harness = FishAudioHarness()
        try await harness.start()

        harness.socket.pushServer(["type": .string("brand_new_event"), "payload": .array([.uint(1)])])
        harness.socket.push(.text("{\"type\":\"committed\"}"))
        harness.socket.push(.frame(Data([0xc1])))
        harness.socket.pushServer(["type": .string("committed"), "turn_index": .uint(0), "text": .string("Still here.")])

        try await harness.waitUntil { harness.service.transcriptText == "Still here." }
        #expect(harness.service.connectionState == .listening)
        #expect(harness.service.lastError == nil)
        await harness.service.stopListening()
    }

    @Test("Fish Audio sends agent_speaking, context_add, and finalize during a session")
    func sessionMethods() async throws {
        let harness = FishAudioHarness()
        try await harness.start()

        try await harness.service.agentSpeaking(true)
        try await harness.service.addContext([FishAudioContextItem(role: .assistant, text: "Which day?")], resetHistory: true)
        try await harness.service.finalizeTurn()

        let sent = harness.socket.sentMessages
        #expect(harness.socket.sentTypes.suffix(3) == ["agent_speaking", "context_add", "finalize"])
        #expect(sent[sent.count - 3]["speaking"] == .bool(true))
        #expect(sent[sent.count - 2]["reset_history"] == .bool(true))
        #expect(sent[sent.count - 2]["items"]?.arrayValue?.first?["text"] == .string("Which day?"))
        await harness.service.stopListening()
    }
}

@Suite("Fish Audio Realtime WebSocket")
struct FishAudioRealtimeWebSocketTests {
    @Test(arguments: [false, true])
    func suspendedConfigCannotCloseReplacement(fails: Bool) async throws {
        let first = GatedFishAudioSocket(fails: fails)
        let second = FakeFishAudioSocket()
        let counter = FishAudioCounter()
        let socket = FishAudioRealtimeWebSocket(socketFactory: { _ in
            counter.increment()
            if counter.value == 1 { return first }
            return second
        }, keepaliveInterval: .seconds(60), handshakeTimeout: .seconds(60))
        let pending = Task { try await socket.connect(credential: .apiKey("synthetic-key"), options: FishAudioRealtimeOptions()) }
        while !(await first.gate.entered) { await Task.yield() }
        let replacement = try await socket.connect(credential: .apiKey("synthetic-key"), options: FishAudioRealtimeOptions())
        await first.gate.open()
        do {
            _ = try await pending.value
            Issue.record("Replaced config send returned a live stream")
        } catch {}
        #expect(!second.isClosed)
        #expect(await socket.isConnected)
        await socket.disconnect()
        withExtendedLifetime(replacement) {}
    }

    @Test("Fish Audio reconnect is not closed by the replaced stream's termination")
    func reconnectSurvivesOldStreamTermination() async throws {
        let sockets = FishAudioSocketList()
        let webSocket = FishAudioRealtimeWebSocket(
            socketFactory: { _ in sockets.make() },
            keepaliveInterval: .seconds(60),
            handshakeTimeout: .seconds(60)
        )

        let first = try await webSocket.connect(credential: .apiKey("fish-key"), options: FishAudioRealtimeOptions())
        let second = try await webSocket.connect(credential: .apiKey("fish-key"), options: FishAudioRealtimeOptions())
        try await Task.sleep(for: .milliseconds(100))

        let all = sockets.all
        #expect(all.count == 2)
        #expect(all.first?.isClosed == true)
        #expect(all.last?.isClosed == false)
        #expect(await webSocket.isConnected)
        await webSocket.disconnect()
        // Keep both streams alive until here, so only the reconnect can end the first.
        withExtendedLifetime((first, second)) {}
    }
}

// MARK: - SpeechService wiring

@Suite("Fish Audio Realtime Wiring")
@MainActor
struct FishAudioRealtimeWiringTests {
    @Test(arguments: [SpeechRecordingRetention.retainUntilDiscarded, .discardOnStop])
    func recordingRetentionAndCallerFileOwnership(retention: SpeechRecordingRetention) async throws {
        let harness = FishAudioHarness()
        let file = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = try Data(contentsOf: file)
        harness.audio.recordedWAVData = bytes
        harness.service.recordingRetention = retention
        await harness.service.stopListening()
        #expect(harness.audio.recordedWAVData == (retention == .discardOnStop ? nil : bytes))
        harness.service.discardRecording()
        #expect(harness.audio.recordedWAVData == nil)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("Fish Audio configuration applies realtime options to the realtime service")
    func configurationAppliesRealtimeOptions() {
        let realtimeOptions = FishAudioRealtimeOptions(mode: .vad, silenceTimeout: 0.5, terms: ["SpeechKit"])
        let endpoint = URL(string: "wss://proxy.example.com/fish")
        let service = SpeechService(fishAudio: FishAudioConfiguration(apiKey: "fish", realtimeOptions: realtimeOptions, realtimeEndpoint: endpoint))

        #expect(service.fishAudioRealtimeService.credentialKind == .apiKey)
        #expect(service.fishAudioRealtimeService.options == realtimeOptions)
        #expect(service.fishAudioRealtimeService.realtimeEndpoint == endpoint)
        #expect(SpeechRealtimeProvider.allCases.contains(.fishAudio))
        #expect(FishAudioConfiguration(apiKey: "fish").realtimeOptions == FishAudioRealtimeOptions())

        service.fishAudio = nil
        #expect(service.fishAudioRealtimeService.credentialKind == .apiKey)
    }

    @Test("startListening surfaces missing Fish Audio configuration")
    func startListeningWithoutConfiguration() async {
        let service = SpeechService()

        await service.startListening(provider: .fishAudio)

        #expect(service.connectionState == .error("Fish Audio is not configured"))
        #expect(service.lastError as? SpeechError == .realtimeProviderNotConfigured(.fishAudio))
    }

    @Test("SpeechService routes Fish Audio realtime state through the injected service")
    func routesThroughInjectedService() {
        let fishService = FishAudioRealtimeService(apiKey: "fish")
        let service = SpeechService(
            fishAudio: FishAudioConfiguration(apiKey: "fish"),
            urlSession: .shared,
            elevenLabsRealtimeService: ElevenLabsService(),
            fishAudioRealtimeService: fishService
        )
        service.activeRealtimeProvider = .fishAudio

        fishService.handleMessageForTesting(.draft(FishAudioRealtimeDraft(turnIndex: 0, text: "hel", settledText: "", languageCode: nil)))
        #expect(service.partialTranscriptEntry?.text == "hel")
        fishService.handleMessageForTesting(.committed(FishAudioRealtimeCommit(turnIndex: 0, text: "Hello.")))
        #expect(service.transcriptText == "Hello.")
        #expect(service.partialTranscriptText.isEmpty)

        service.clearTranscript()
        #expect(fishService.transcriptEntries.isEmpty)
    }
}

// MARK: - Helpers

private func decodeServer(_ fields: KeyValuePairs<String, MessagePackValue>) throws -> FishAudioRealtimeServerMessage {
    try FishAudioRealtimeServerMessage.decode(fishServerFrame(fields))
}

private func fishServerFrame(_ fields: KeyValuePairs<String, MessagePackValue>) -> Data {
    MessagePack.encode(.map(fields.map { (key: .string($0.key), value: $0.value) }))
}

/// Fails unless every key in a `config` map, at every documented level, is a documented field.
private func expectOnlyDocumentedKeys(_ config: MessagePackValue) throws {
    let allowed = FishAudioRealtimeMessageTests.documentedConfigKeys
    #expect(Set(config.mapKeys).isSubset(of: try #require(allowed[""])))
    for section in ["audio", "turn_detection", "results", "context"] {
        guard let value = config[section] else { continue }
        #expect(Set(value.mapKeys).isSubset(of: try #require(allowed[section])), "\(section) has undocumented keys: \(value.mapKeys)")
    }
    for item in config["context"]?["history"]?.arrayValue ?? [] {
        #expect(Set(item.mapKeys) == ["role", "text"])
    }
}

/// A service wired to a fake socket and a fake microphone.
@MainActor
private final class FishAudioHarness {
    let socket = FakeFishAudioSocket()
    let audio = FakeFishAudioSource()
    let service: FishAudioRealtimeService
    private let factoryCounter = FishAudioCounter()

    var factoryCallCount: Int { factoryCounter.value }

    init(
        credential: SpeechCredential = .apiKey("fish-key"),
        keepaliveInterval: Duration = .seconds(60),
        handshakeTimeout: Duration = .seconds(5),
        gracefulStopTimeout: Duration = .seconds(5)
    ) {
        let socket = socket
        let counter = factoryCounter
        let webSocket = FishAudioRealtimeWebSocket(
            socketFactory: { request in
                counter.increment()
                socket.request = request
                return socket
            },
            keepaliveInterval: keepaliveInterval,
            handshakeTimeout: handshakeTimeout
        )
        service = FishAudioRealtimeService(
            credential: credential,
            options: FishAudioRealtimeOptions(),
            realtimeEndpoint: URL(string: "wss://proxy.example.com/fish"),
            audioSource: audio,
            webSocket: webSocket,
            gracefulStopTimeout: gracefulStopTimeout
        )
    }

    /// Starts a session and answers `config` with `session_started`.
    func start() async throws {
        await service.startListening()
        try await waitUntil { socket.sentMessages.count == 1 }
        socket.pushServer(["type": .string("session_started"), "session_id": .string("s_1")])
        try await waitUntil { service.connectionState == .listening }
    }

    func waitUntil(
        timeout: Duration = .seconds(3),
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for condition", sourceLocation: sourceLocation)
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class FishAudioCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() {
        lock.withLock { count += 1 }
    }
}

/// An in-memory socket: records sent frames and delivers pushed events in order.
private final class FakeFishAudioSocket: FishAudioRealtimeSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var sent: [Data] = []
    private var pending: [Result<FishAudioRealtimeSocketEvent, Error>] = []
    private var waiter: CheckedContinuation<FishAudioRealtimeSocketEvent, Error>?
    private var closed = false
    private var storedRequest: URLRequest?
    private var answersAudioDone = true
    private var stalls = false
    private var stalledSends: [CheckedContinuation<Void, Error>] = []

    /// Whether sends hang until the socket closes, like a stalled network.
    var stallsSends: Bool {
        get { lock.withLock { stalls } }
        set { lock.withLock { stalls = newValue } }
    }

    /// Whether the socket answers `audio_done` with `session_done` and a normal close, as Fish Audio does.
    var answersAudioDoneLikeServer: Bool {
        get { lock.withLock { answersAudioDone } }
        set { lock.withLock { answersAudioDone = newValue } }
    }

    var request: URLRequest? {
        get { lock.withLock { storedRequest } }
        set { lock.withLock { storedRequest = newValue } }
    }

    var isClosed: Bool { lock.withLock { closed } }

    var sentMessages: [MessagePackValue] {
        lock.withLock { sent }.compactMap { try? MessagePack.decode($0) }
    }

    var sentTypes: [String] {
        sentMessages.map { $0["type"]?.stringValue ?? "?" }
    }

    func send(_ data: Data) async throws {
        if stallsSends {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if closed {
                    lock.unlock()
                    continuation.resume(throwing: FishAudioRealtimeError.disconnected)
                } else {
                    stalledSends.append(continuation)
                    lock.unlock()
                }
            }
            return
        }
        let answers = try lock.withLock {
            guard !closed else { throw FishAudioRealtimeError.disconnected }
            sent.append(data)
            return answersAudioDone
        }
        if answers, (try? MessagePack.decode(data))?["type"] == .string("audio_done") {
            pushServer(["type": .string("session_done"), "stats": .map([])])
            push(.closed(code: 1000, reason: nil))
        }
    }

    func receive() async throws -> FishAudioRealtimeSocketEvent {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if !pending.isEmpty {
                let next = pending.removeFirst()
                lock.unlock()
                continuation.resume(with: next)
            } else if closed {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }

    func close() {
        lock.lock()
        closed = true
        let waiter = self.waiter
        self.waiter = nil
        let stalledSends = self.stalledSends
        self.stalledSends = []
        lock.unlock()
        waiter?.resume(throwing: CancellationError())
        for send in stalledSends {
            send.resume(throwing: FishAudioRealtimeError.disconnected)
        }
    }

    func push(_ event: FishAudioRealtimeSocketEvent) {
        deliver(.success(event))
    }

    func pushServer(_ fields: KeyValuePairs<String, MessagePackValue>) {
        push(.frame(fishServerFrame(fields)))
    }

    func failReceive(with error: Error) {
        deliver(.failure(error))
    }

    private func deliver(_ result: Result<FishAudioRealtimeSocketEvent, Error>) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(with: result)
        } else {
            pending.append(result)
            lock.unlock()
        }
    }
}

/// A microphone that yields only the audio a test feeds it.
private final class FakeFishAudioSource: FishAudioRealtimeAudioSource, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var capturing = false
    private var failsToStart = false

    /// Whether `startCapture()` throws, like a missing input device.
    var failsOnStart: Bool {
        get { lock.withLock { failsToStart } }
        set { lock.withLock { failsToStart = newValue } }
    }

    var isCapturing: Bool { lock.withLock { capturing } }
    let currentLevel = 0.0
    private var recording: Data?
    var recordedWAVData: Data? {
        get { lock.withLock { recording } }
        set { lock.withLock { recording = newValue } }
    }
    func discardRecording() { lock.withLock { recording = nil } }

    func setTargetSampleRate(_ targetSampleRate: Double) {}

    func requestPermission() async -> Bool { true }

    func startCapture() throws -> AsyncStream<Data> {
        if failsOnStart {
            throw SpeechAudioCaptureError.audioEngineError(.requestFailed)
        }
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        lock.withLock {
            self.continuation = continuation
            capturing = true
        }
        return stream
    }

    func stopCapture() {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            capturing = false
            return continuation
        }
        continuation?.finish()
    }

    func feed(_ data: Data) {
        _ = lock.withLock { continuation }?.yield(data)
    }
}

/// A gate a test opens to let a suspended token fetch finish.
private final class FishAudioGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        let waiters = lock.withLock {
            isOpen = true
            let waiters = self.waiters
            self.waiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}

/// Hands out a new fake socket for each connection.
private final class FishAudioSocketList: @unchecked Sendable {
    private let lock = NSLock()
    private var sockets: [FakeFishAudioSocket] = []

    var all: [FakeFishAudioSocket] { lock.withLock { sockets } }

    func make() -> FakeFishAudioSocket {
        let socket = FakeFishAudioSocket()
        lock.withLock { sockets.append(socket) }
        return socket
    }
}

private final class GatedFishAudioSocket: FishAudioRealtimeSocket, Sendable {
    let gate = SecurityGate()
    let fails: Bool
    init(fails: Bool) { self.fails = fails }
    func send(_ data: Data) async throws {
        await gate.wait()
        if fails { throw FishAudioRealtimeError.disconnected }
    }
    func receive() async throws -> FishAudioRealtimeSocketEvent { throw CancellationError() }
    func close() {}
}
