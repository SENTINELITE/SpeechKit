import Foundation

// MARK: - Public options

/// How a Fish Audio realtime session decides that a turn has ended.
public enum FishAudioTurnDetectionMode: String, Sendable, CaseIterable {
    /// Fish Audio's turn detection judges when the speaker has finished, from what was said and how.
    ///
    /// Other voices and noise are committed as non-user turns. SpeechKit still
    /// emits them; check ``FishAudioRealtimeTurn/kind`` to filter them.
    case auto
    /// A turn ends after ``FishAudioRealtimeOptions/silenceTimeout`` of silence. Every turn is a user turn.
    case vad
    /// A turn ends when you call ``FishAudioRealtimeService/finalizeTurn()``. Every turn is a user turn.
    case manual

    /// The `silence_timeout_ms` range Fish Audio accepts in this mode, in milliseconds.
    public var allowedSilenceTimeoutMilliseconds: ClosedRange<Int> {
        switch self {
        case .auto:
            return 3000...60000
        case .vad, .manual:
            return 300...60000
        }
    }
}

/// Who said a line of Fish Audio realtime conversation context.
public enum FishAudioContextRole: String, Sendable, CaseIterable {
    /// The person being transcribed.
    case user
    /// The other party, such as your voice agent.
    case assistant
}

/// One line of earlier conversation that helps Fish Audio recognize names and follow-ups.
public struct FishAudioContextItem: Sendable, Equatable {
    /// Who said the line.
    public var role: FishAudioContextRole
    /// What was said, up to 2,000 characters.
    public var text: String

    /// Creates a context item.
    public init(role: FishAudioContextRole, text: String) {
        self.role = role
        self.text = text
    }
}

/// Options for a Fish Audio realtime transcription session.
///
/// SpeechKit sends these values in the `config` message that opens the
/// session. Fish Audio closes the session on any invalid value, so SpeechKit
/// validates them before connecting. The defaults suit transcription rather
/// than a voice agent: live drafts, word timings, and speaker labels are on.
public struct FishAudioRealtimeOptions: Sendable, Equatable {
    /// The sample rates Fish Audio accepts, in hertz.
    public static let supportedSampleRates: Set<Int> = [8000, 12000, 16000, 22050, 24000, 32000, 44100, 48000]
    /// The most ``terms`` Fish Audio accepts.
    public static let maximumTermCount = 100
    /// The longest term Fish Audio accepts, in Unicode code points.
    public static let maximumTermLength = 32
    /// The most ``history`` items Fish Audio accepts in one message.
    public static let maximumHistoryCount = 32
    /// The longest ``history`` item Fish Audio accepts, in Unicode code points.
    public static let maximumHistoryTextLength = 2000

    /// How the session decides that a turn has ended.
    public var mode: FishAudioTurnDetectionMode
    /// A Boolean value that indicates whether Fish Audio sends an early end-of-turn signal in ``FishAudioTurnDetectionMode/auto`` mode.
    ///
    /// SpeechKit does not change its transcript for the signal. It is useful
    /// only to voice agents that read the raw protocol.
    public var eager: Bool
    /// The silence timeout, or `nil` for the mode's default.
    ///
    /// In ``FishAudioTurnDetectionMode/vad`` mode this is the silence that ends
    /// a turn (default 0.7 s, allowed 0.3–60 s). In the other modes it is a
    /// safety net (``FishAudioTurnDetectionMode/auto``: default 5 s, allowed
    /// 3–60 s; ``FishAudioTurnDetectionMode/manual``: default and maximum
    /// 60 s, minimum 0.3 s). Fish Audio takes whole milliseconds.
    public var silenceTimeout: TimeInterval?
    /// A Boolean value that indicates whether Fish Audio sends live drafts of the open turn.
    ///
    /// SpeechKit publishes the latest draft as the partial transcript entry.
    public var drafts: Bool
    /// A Boolean value that indicates whether committed turns carry word timings.
    ///
    /// Sent as `ignore_timestamps`, inverted.
    public var timestamps: Bool
    /// A Boolean value that indicates whether Fish Audio labels speakers.
    public var diarize: Bool
    /// Names, products, and jargon to recognize: up to 100 terms of up to 32 Unicode code points each.
    public var terms: [String]
    /// Earlier conversation, oldest first: up to 32 items of up to 2,000 Unicode code points each.
    public var history: [FishAudioContextItem]
    /// The microphone capture sample rate, in hertz.
    ///
    /// SpeechKit streams 16-bit signed little-endian mono PCM at this rate.
    /// Fish Audio uses 16 kHz natively and resamples anything else on the server.
    public var sampleRate: Int

    /// Creates Fish Audio realtime session options.
    public init(
        mode: FishAudioTurnDetectionMode = .auto,
        eager: Bool = false,
        silenceTimeout: TimeInterval? = nil,
        drafts: Bool = true,
        timestamps: Bool = true,
        diarize: Bool = true,
        terms: [String] = [],
        history: [FishAudioContextItem] = [],
        sampleRate: Int = 16000
    ) {
        self.mode = mode
        self.eager = eager
        self.silenceTimeout = silenceTimeout
        self.drafts = drafts
        self.timestamps = timestamps
        self.diarize = diarize
        self.terms = terms
        self.history = history
        self.sampleRate = sampleRate
    }

    /// ``silenceTimeout`` in whole milliseconds, as Fish Audio expects it.
    var silenceTimeoutMilliseconds: Int? {
        silenceTimeout.flatMap(Self.wholeMilliseconds)
    }

    /// Seconds as whole milliseconds, or `nil` when the value cannot be an `Int`.
    static func wholeMilliseconds(_ seconds: TimeInterval) -> Int? {
        let milliseconds = (seconds * 1000).rounded()
        guard milliseconds.isFinite else { return nil }
        return Int(exactly: milliseconds)
    }

    /// The bytes in 100 ms of 16-bit mono audio at ``sampleRate``.
    var chunkByteCount: Int {
        sampleRate * 2 / 10
    }

    func validate() throws {
        guard Self.supportedSampleRates.contains(sampleRate) else {
            throw SpeechError.providerFailure(
                provider: .fishAudio,
                reason: "Unsupported realtime sampleRate: \(sampleRate). Use 8000, 12000, 16000, 22050, 24000, 32000, 44100, or 48000."
            )
        }

        if silenceTimeout != nil {
            let range = mode.allowedSilenceTimeoutMilliseconds
            guard let milliseconds = silenceTimeoutMilliseconds, range.contains(milliseconds) else {
                throw SpeechError.providerFailure(
                    provider: .fishAudio,
                    reason: "silenceTimeout must be between \(Double(range.lowerBound) / 1000) and \(Double(range.upperBound) / 1000) seconds in \(mode.rawValue) mode."
                )
            }
        }

        try FishAudioValidation.validateTerms(terms)
        try FishAudioValidation.validateContextItems(history, name: "history")
    }

    /// The `config` message that opens a session with these options.
    func configMessage() -> FishAudioRealtimeClientMessage {
        .config(self)
    }
}

extension FishAudioValidation {
    /// Rejects more than 100 terms, an empty term, or a term over 32 characters.
    static func validateTerms(_ terms: [String]) throws {
        if terms.count > FishAudioRealtimeOptions.maximumTermCount {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: "terms cannot contain more than 100 entries.")
        }
        if terms.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: "terms cannot contain empty entries.")
        }
        // Fish Audio's limits count Unicode code points, not grapheme clusters.
        if let term = terms.first(where: { $0.unicodeScalars.count > FishAudioRealtimeOptions.maximumTermLength }) {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: "terms cannot be longer than 32 Unicode code points: \"\(term)\".")
        }
    }

    /// Rejects more than 32 context items or an item over 2,000 characters.
    static func validateContextItems(_ items: [FishAudioContextItem], name: String) throws {
        if items.count > FishAudioRealtimeOptions.maximumHistoryCount {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: "\(name) cannot contain more than 32 items.")
        }
        if items.contains(where: { $0.text.unicodeScalars.count > FishAudioRealtimeOptions.maximumHistoryTextLength }) {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: "\(name) items cannot be longer than 2000 Unicode code points.")
        }
    }
}

// MARK: - Public turn metadata

/// What kind of turn Fish Audio committed.
public enum FishAudioRealtimeTurnKind: String, Sendable, CaseIterable {
    /// The user's turn.
    case user
    /// A non-user turn holding a short acknowledgement, such as "mm-hm", made while your agent was speaking.
    case backchannel
    /// A non-user turn: noise, another voice, or unclear audio.
    ///
    /// SpeechKit also uses this for a kind it does not recognize.
    case other
}

/// A committed Fish Audio realtime turn, with the metadata that does not fit ``SpeechTranscriptEntry``.
///
/// Each emitted turn produces one transcript entry per speaker in it.
/// ``entryIDs`` links the turn to those entries.
public struct FishAudioRealtimeTurn: Sendable, Equatable, Identifiable {
    /// The turn index, counting from 0 within the session.
    public let turnIndex: Int
    /// The kind of turn.
    public let kind: FishAudioRealtimeTurnKind
    /// The raw turn text, including `<|speaker:N|>` tags and sound tags.
    public let text: String
    /// Why the turn ended, such as `"eot"`, `"finalize"`, `"silence_timeout"`, `"max_turn_duration"`, or `"audio_done"`.
    public let reason: String?
    /// A Boolean value that indicates whether Fish Audio's final pass failed.
    ///
    /// A degraded turn carries the text of its last draft and no words.
    public let isDegraded: Bool
    /// The turn's language as an English name, when Fish Audio could tell.
    public let language: String?
    /// The turn's ISO 639-1 language code, when Fish Audio could tell.
    public let languageCode: String?
    /// The turn start, in seconds of session audio.
    public let start: Double?
    /// The turn end, in seconds of session audio.
    public let end: Double?
    /// The identifiers of the transcript entries made from this turn, in order.
    public let entryIDs: [UUID]

    /// The turn index, which identifies the turn within its session.
    public var id: Int { turnIndex }
    /// A Boolean value that indicates whether this is the user's turn.
    public var isUserTurn: Bool { kind == .user }
}

// MARK: - Errors

/// Errors returned by Fish Audio-specific realtime APIs.
public enum FishAudioRealtimeError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid Fish Audio realtime URL.
    case invalidURL
    /// The Fish Audio API key is empty.
    case apiKeyMissing
    /// The realtime WebSocket is not connected.
    case disconnected
    /// Fish Audio did not start the session in time.
    case handshakeTimedOut
    /// Fish Audio refused the WebSocket upgrade with a plain HTTP status: 401, 402, 429, or 503.
    case connectionRefused(statusCode: Int)
    /// Fish Audio reported an error during the session.
    ///
    /// `code` is Fish Audio's HTTP-style status and `errorType` its machine-readable type, such as `invalid_request` or `engine_error`.
    case serverError(errorType: String, code: Int?, message: String?)
    /// Fish Audio closed the session with an error close code: 4400, 4408, 4413, 4500, or 1009.
    ///
    /// `errorType` and `message` come from the `error` message Fish Audio sent before closing, when there was one.
    case sessionClosed(code: Int, errorType: String?, message: String?)
    /// Fish Audio is restarting and closed the session with code 1012.
    ///
    /// The open turn was committed first. A new session can start at once.
    case serverRestarting

    /// A Boolean value that indicates whether the same session settings may succeed if you start again.
    public var isRetryable: Bool {
        switch self {
        case .connectionRefused(let statusCode):
            return statusCode == 429 || statusCode == 503
        case .serverError(_, let code, _):
            return code.map { $0 >= 500 } ?? false
        case .sessionClosed(let code, _, _):
            return code == 4500
        case .serverRestarting, .handshakeTimedOut, .disconnected:
            return true
        case .invalidURL, .apiKeyMissing:
            return false
        }
    }

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Fish Audio realtime URL"
        case .apiKeyMissing:
            return "API key not configured"
        case .disconnected:
            return "WebSocket disconnected"
        case .handshakeTimedOut:
            return "Fish Audio did not start the realtime session"
        case .connectionRefused(let statusCode):
            switch statusCode {
            case 401:
                return "Fish Audio rejected the API key (HTTP 401)"
            case 402:
                return "The Fish Audio account has no remaining credit (HTTP 402)"
            case 429:
                return "Fish Audio is at its concurrency limit; retry later (HTTP 429)"
            case 503:
                return "Fish Audio is restarting; retry (HTTP 503)"
            default:
                return "Fish Audio refused the realtime connection (HTTP \(statusCode))"
            }
        case .serverError(let errorType, let code, let message):
            let detail = message.map { ": \($0)" } ?? ""
            let status = code.map { ", \($0)" } ?? ""
            return "Fish Audio error (\(errorType)\(status))\(detail)"
        case .sessionClosed(let code, let errorType, let message):
            let summary: String
            switch code {
            case 4400:
                summary = "Fish Audio rejected the session configuration or audio"
            case 4408:
                summary = "Fish Audio closed the idle session"
            case 4413:
                summary = "The session reached Fish Audio's 60-minute limit"
            case 4500:
                summary = "Fish Audio had an internal error"
            case 1009:
                summary = "An audio message exceeded Fish Audio's 1 MiB frame limit"
            default:
                summary = "Fish Audio closed the session"
            }
            var details = ["close \(code)"]
            if let errorType {
                details.append(errorType)
            }
            let detail = message.map { ": \($0)" } ?? ""
            return "\(summary) (\(details.joined(separator: ", ")))\(detail)"
        case .serverRestarting:
            return "Fish Audio is restarting; start a new session"
        }
    }
}

// MARK: - Client messages

/// A message SpeechKit sends to Fish Audio, encoded as one MessagePack map.
///
/// Fish Audio treats an unknown field in `config` as fatal, so each message
/// carries only documented fields.
enum FishAudioRealtimeClientMessage: Sendable, Equatable {
    /// Opens the session. Must be the first message.
    case config(FishAudioRealtimeOptions)
    /// Raw 16-bit little-endian PCM, sent as MessagePack `bin`.
    case audio(Data)
    /// Commits the open turn now.
    case finalize
    /// Changes settings during the session. Fields left `nil` keep their current value.
    case configure(FishAudioRealtimeConfigureRequest)
    /// Adds conversation context.
    case contextAdd(items: [FishAudioContextItem], resetHistory: Bool)
    /// Keeps an idle session open.
    case keepalive
    /// Ends the audio. Fish Audio commits the open turn, sends `session_done`, and closes.
    case audioDone
    /// Tells Fish Audio whether a voice agent's reply is playing.
    case agentSpeaking(Bool)

    var typeName: String {
        switch self {
        case .config: return "config"
        case .audio: return "audio"
        case .finalize: return "finalize"
        case .configure: return "configure"
        case .contextAdd: return "context_add"
        case .keepalive: return "keepalive"
        case .audioDone: return "audio_done"
        case .agentSpeaking: return "agent_speaking"
        }
    }

    var messagePackValue: MessagePackValue {
        var pairs: [(key: MessagePackValue, value: MessagePackValue)] = [(.string("type"), .string(typeName))]

        switch self {
        case .config(let options):
            pairs.append((.string("audio"), .map([
                (.string("format"), .string("pcm_s16le")),
                (.string("sample_rate"), .int(Int64(options.sampleRate))),
                (.string("channels"), .int(1))
            ])))
            var turnDetection: [(key: MessagePackValue, value: MessagePackValue)] = [
                (.string("mode"), .string(options.mode.rawValue)),
                (.string("eager"), .bool(options.eager))
            ]
            if let milliseconds = options.silenceTimeoutMilliseconds {
                turnDetection.append((.string("silence_timeout_ms"), .int(Int64(milliseconds))))
            }
            pairs.append((.string("turn_detection"), .map(turnDetection)))
            pairs.append((.string("results"), .map([
                (.string("drafts"), .bool(options.drafts)),
                (.string("ignore_timestamps"), .bool(!options.timestamps)),
                (.string("diarize"), .bool(options.diarize))
            ])))
            var context: [(key: MessagePackValue, value: MessagePackValue)] = []
            if !options.history.isEmpty {
                context.append((.string("history"), Self.contextItems(options.history)))
            }
            if !options.terms.isEmpty {
                context.append((.string("terms"), .array(options.terms.map { .string($0) })))
            }
            if !context.isEmpty {
                pairs.append((.string("context"), .map(context)))
            }

        case .audio(let data):
            pairs.append((.string("data"), .binary(data)))

        case .configure(let request):
            var turnDetection: [(key: MessagePackValue, value: MessagePackValue)] = []
            if let mode = request.mode {
                turnDetection.append((.string("mode"), .string(mode.rawValue)))
            }
            if let eager = request.eager {
                turnDetection.append((.string("eager"), .bool(eager)))
            }
            if let milliseconds = request.silenceTimeout.flatMap(FishAudioRealtimeOptions.wholeMilliseconds) {
                turnDetection.append((.string("silence_timeout_ms"), .int(Int64(milliseconds))))
            }
            if !turnDetection.isEmpty {
                pairs.append((.string("turn_detection"), .map(turnDetection)))
            }
            var results: [(key: MessagePackValue, value: MessagePackValue)] = []
            if let drafts = request.drafts {
                results.append((.string("drafts"), .bool(drafts)))
            }
            if let timestamps = request.timestamps {
                results.append((.string("ignore_timestamps"), .bool(!timestamps)))
            }
            if let diarize = request.diarize {
                results.append((.string("diarize"), .bool(diarize)))
            }
            if !results.isEmpty {
                pairs.append((.string("results"), .map(results)))
            }
            if let terms = request.terms {
                pairs.append((.string("context"), .map([
                    (.string("terms"), .array(terms.map { .string($0) }))
                ])))
            }

        case .contextAdd(let items, let resetHistory):
            pairs.append((.string("items"), Self.contextItems(items)))
            pairs.append((.string("reset_history"), .bool(resetHistory)))

        case .agentSpeaking(let speaking):
            pairs.append((.string("speaking"), .bool(speaking)))

        case .finalize, .keepalive, .audioDone:
            break
        }

        return .map(pairs)
    }

    /// The message as one MessagePack-encoded binary frame.
    func encoded() -> Data {
        MessagePack.encode(messagePackValue)
    }

    private static func contextItems(_ items: [FishAudioContextItem]) -> MessagePackValue {
        .array(items.map { item in
            .map([
                (.string("role"), .string(item.role.rawValue)),
                (.string("text"), .string(item.text))
            ])
        })
    }
}

/// The settings a `configure` message changes. A `nil` field keeps its current value.
struct FishAudioRealtimeConfigureRequest: Sendable, Equatable {
    var mode: FishAudioTurnDetectionMode?
    var eager: Bool?
    var silenceTimeout: TimeInterval?
    var drafts: Bool?
    var timestamps: Bool?
    var diarize: Bool?
    var terms: [String]?
}

// MARK: - Server messages

/// A timed word from a committed Fish Audio turn.
struct FishAudioRealtimeWord: Sendable, Equatable {
    let text: String
    let startMilliseconds: Int?
    let endMilliseconds: Int?
}

/// A live draft of an open turn.
struct FishAudioRealtimeDraft: Sendable, Equatable {
    let turnIndex: Int
    let text: String
    let settledText: String
    let languageCode: String?
}

/// The final transcript of a turn.
struct FishAudioRealtimeCommit: Sendable, Equatable {
    let turnIndex: Int
    let text: String
    /// `nil` when Fish Audio sent no `words` field, as with timestamps off or a degraded commit.
    let words: [FishAudioRealtimeWord]?
    let language: String?
    let languageCode: String?
    let audioStartMilliseconds: Int?
    let audioEndMilliseconds: Int?
    let reason: String?
    let degraded: Bool
    let userTurn: Bool
    let turnKind: FishAudioRealtimeTurnKind

    init(
        turnIndex: Int,
        text: String,
        words: [FishAudioRealtimeWord]? = nil,
        language: String? = nil,
        languageCode: String? = nil,
        audioStartMilliseconds: Int? = nil,
        audioEndMilliseconds: Int? = nil,
        reason: String? = "eot",
        degraded: Bool = false,
        userTurn: Bool = true,
        turnKind: FishAudioRealtimeTurnKind? = nil
    ) {
        self.turnIndex = turnIndex
        self.text = text
        self.words = words
        self.language = language
        self.languageCode = languageCode
        self.audioStartMilliseconds = audioStartMilliseconds
        self.audioEndMilliseconds = audioEndMilliseconds
        self.reason = reason
        self.degraded = degraded
        self.userTurn = userTurn
        self.turnKind = turnKind ?? (userTurn ? .user : .other)
    }
}

/// An `error` message from Fish Audio.
struct FishAudioRealtimeServerError: Sendable, Equatable {
    let code: Int?
    let errorType: String
    let message: String?
    let requestID: String?
    let recoverable: Bool
}

/// A message Fish Audio sends, decoded from one MessagePack map.
///
/// Unknown message types decode as ``unknown(_:)`` and unknown fields are
/// ignored, as Fish Audio's compatibility rules require.
enum FishAudioRealtimeServerMessage: Sendable, Equatable {
    case sessionStarted(sessionID: String?, requestID: String?)
    case speechStart(turnIndex: Int, audioMilliseconds: Int?)
    case userTurnTaken(turnIndex: Int)
    case draft(FishAudioRealtimeDraft)
    case eagerEndOfTurn(turnIndex: Int, text: String)
    case turnResumed(turnIndex: Int)
    case userBackchannel(turnIndex: Int)
    case committed(FishAudioRealtimeCommit)
    case vad(audioMilliseconds: Int?, score: Double?)
    case eotProbability(turnIndex: Int, probability: Double?)
    case progress
    case configured(ok: Bool, message: String?)
    case error(FishAudioRealtimeServerError)
    case sessionDone(requestID: String?)
    case unknown(String)

    /// Decodes a binary frame.
    static func decode(_ data: Data) throws -> FishAudioRealtimeServerMessage {
        try FishAudioRealtimeServerMessage(MessagePack.decode(data))
    }

    /// Interprets a decoded MessagePack value. A value that is not a map, or has no `type`, is ``unknown(_:)``.
    init(_ value: MessagePackValue) {
        guard let type = value["type"]?.stringValue else {
            self = .unknown("")
            return
        }
        let turnIndex = value["turn_index"]?.intValue ?? 0

        switch type {
        case "session_started":
            self = .sessionStarted(sessionID: value["session_id"]?.stringValue, requestID: value["request_id"]?.stringValue)
        case "speech_start":
            self = .speechStart(turnIndex: turnIndex, audioMilliseconds: value["audio_ms"]?.intValue)
        case "user_turn_taken":
            self = .userTurnTaken(turnIndex: turnIndex)
        case "draft":
            self = .draft(FishAudioRealtimeDraft(
                turnIndex: turnIndex,
                text: value["text"]?.stringValue ?? "",
                settledText: value["settled_text"]?.stringValue ?? "",
                languageCode: value["language_code"]?.stringValue
            ))
        case "eager_end_of_turn":
            self = .eagerEndOfTurn(turnIndex: turnIndex, text: value["text"]?.stringValue ?? "")
        case "turn_resumed":
            self = .turnResumed(turnIndex: turnIndex)
        case "user_backchannel":
            self = .userBackchannel(turnIndex: turnIndex)
        case "committed":
            let words = value["words"]?.arrayValue?.map { word in
                FishAudioRealtimeWord(
                    text: word["text"]?.stringValue ?? "",
                    startMilliseconds: word["start_ms"]?.intValue,
                    endMilliseconds: word["end_ms"]?.intValue
                )
            }
            // A missing `user_turn` is treated as true, as Fish Audio documents.
            let userTurn = value["user_turn"]?.boolValue ?? true
            let kind = value["turn_kind"]?.stringValue.flatMap(FishAudioRealtimeTurnKind.init(rawValue:))
            self = .committed(FishAudioRealtimeCommit(
                turnIndex: turnIndex,
                text: value["text"]?.stringValue ?? "",
                words: words,
                language: value["language"]?.stringValue,
                languageCode: value["language_code"]?.stringValue,
                audioStartMilliseconds: value["audio_start_ms"]?.intValue,
                audioEndMilliseconds: value["audio_end_ms"]?.intValue,
                reason: value["reason"]?.stringValue,
                degraded: value["degraded"]?.boolValue ?? false,
                userTurn: userTurn,
                // `user_turn` is authoritative: an unknown kind on a non-user turn is "other".
                turnKind: userTurn ? .user : (kind == .user ? .other : kind)
            ))
        case "vad":
            self = .vad(audioMilliseconds: value["audio_ms"]?.intValue, score: value["score"]?.doubleValue)
        case "eot_prob":
            self = .eotProbability(turnIndex: turnIndex, probability: value["prob"]?.doubleValue)
        case "progress":
            self = .progress
        case "configured":
            self = .configured(ok: value["ok"]?.boolValue ?? false, message: value["message"]?.stringValue)
        case "error":
            self = .error(FishAudioRealtimeServerError(
                code: value["code"]?.intValue,
                errorType: value["error_type"]?.stringValue ?? "unknown",
                message: value["message"]?.stringValue,
                requestID: value["request_id"]?.stringValue,
                recoverable: value["recoverable"]?.boolValue ?? false
            ))
        case "session_done":
            self = .sessionDone(requestID: value["stats"]?["request_id"]?.stringValue ?? value["request_id"]?.stringValue)
        default:
            self = .unknown(type)
        }
    }
}
