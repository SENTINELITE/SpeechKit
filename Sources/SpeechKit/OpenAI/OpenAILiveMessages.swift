import Foundation

// MARK: - Options

/// An OpenAI GPT-Live speech-to-speech model.
public enum OpenAILiveModelID: String, Sendable, CaseIterable {
    /// The only GPT-Live snapshot: audio and text in, audio and text out.
    case gptLive1 = "gpt-live-1"
}

/// A GPT-Live output voice.
///
/// This is a string-backed struct rather than an enum so a voice that OpenAI
/// adds after a SpeechKit release still works without a package update.
public struct OpenAILiveVoice: RawRepresentable, Sendable, Equatable, Hashable, Identifiable, ExpressibleByStringLiteral {
    /// The voice name sent to OpenAI.
    public let rawValue: String

    /// The voice name, so voices can drive a `ForEach` directly.
    public var id: String { rawValue }

    /// Creates a voice from its OpenAI name.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a voice from its OpenAI name.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a voice from a string literal.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// The default GPT-Live voice.
    public static let marin = OpenAILiveVoice("marin")
    /// The `cedar` GPT-Live voice.
    public static let cedar = OpenAILiveVoice("cedar")
    /// The `alloy` GPT-Live voice.
    public static let alloy = OpenAILiveVoice("alloy")

    /// The voices SpeechKit has verified against GPT-Live.
    ///
    /// OpenAI does not publish the full list, and an unavailable voice is
    /// rejected with a `forbidden` error before the session starts.
    public static let knownVoices: [OpenAILiveVoice] = [.marin, .cedar, .alloy]
}

/// The wire audio format used for GPT-Live input and output audio.
///
/// Every format carries raw little-endian PCM samples with no container.
public enum OpenAILiveAudioFormat: Sendable, Equatable {
    /// 24 kHz PCM16, the GPT-Live default.
    case pcm24k
    /// 16 kHz PCM16.
    case pcm16k
    /// 8 kHz G.711 µ-law.
    case pcmu8k
    /// 8 kHz G.711 A-law.
    case pcma8k

    /// The OpenAI media type for the format.
    public var mimeType: String {
        switch self {
        case .pcm24k, .pcm16k:
            return "audio/pcm"
        case .pcmu8k:
            return "audio/pcmu"
        case .pcma8k:
            return "audio/pcma"
        }
    }

    /// The sample rate, in hertz.
    public var sampleRate: Int {
        switch self {
        case .pcm24k:
            return 24000
        case .pcm16k:
            return 16000
        case .pcmu8k, .pcma8k:
            return 8000
        }
    }
}

/// How the delegated backend model chooses tools.
public enum OpenAILiveToolChoice: Sendable, Equatable {
    /// Let the model decide whether to call a tool.
    case auto
    /// Require the model to call some tool.
    case required
    /// Forbid tool calls.
    case none
    /// Require a specific function by name.
    case function(name: String)
}

extension OpenAILiveToolChoice: Encodable {
    /// Encodes the tool choice as either a bare string or a function reference object.
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .auto, .required, .none:
            var container = encoder.singleValueContainer()
            try container.encode(namedValue)
        case .function(let name):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("function", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }

    private var namedValue: String {
        switch self {
        case .auto:
            return "auto"
        case .required:
            return "required"
        case .none:
            return "none"
        case .function:
            return "function"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
}

/// A JSON value passed through to or from OpenAI without interpretation.
///
/// Tool schemas and nested Responses events keep their exact shape, so SpeechKit
/// never has to model the whole Responses API to forward a payload.
public enum OpenAIJSONValue: Sendable, Equatable, Codable {
    /// A JSON `null`.
    case null
    /// A JSON boolean.
    case bool(Bool)
    /// A JSON number.
    case number(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array.
    case array([OpenAIJSONValue])
    /// A JSON object.
    case object([String: OpenAIJSONValue])

    /// Decodes any JSON value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([OpenAIJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: OpenAIJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    /// Encodes the value back to JSON unchanged.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// The string payload, when the value is a JSON string.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The object payload, when the value is a JSON object.
    public var objectValue: [String: OpenAIJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

extension OpenAIJSONValue: ExpressibleByNilLiteral {
    /// Creates a JSON `null`.
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension OpenAIJSONValue: ExpressibleByBooleanLiteral {
    /// Creates a JSON boolean.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension OpenAIJSONValue: ExpressibleByIntegerLiteral {
    /// Creates a JSON number from an integer literal.
    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

extension OpenAIJSONValue: ExpressibleByFloatLiteral {
    /// Creates a JSON number from a floating-point literal.
    public init(floatLiteral value: Double) {
        self = .number(value)
    }
}

extension OpenAIJSONValue: ExpressibleByStringLiteral {
    /// Creates a JSON string.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension OpenAIJSONValue: ExpressibleByArrayLiteral {
    /// Creates a JSON array.
    public init(arrayLiteral elements: OpenAIJSONValue...) {
        self = .array(elements)
    }
}

extension OpenAIJSONValue: ExpressibleByDictionaryLiteral {
    /// Creates a JSON object.
    public init(dictionaryLiteral elements: (String, OpenAIJSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

/// Settings for the backend model that answers a GPT-Live session through Responses delegation.
public struct OpenAILiveResponsesDelegation: Sendable, Equatable {
    /// The backend model that produces the answers GPT-Live speaks.
    public var model: String
    /// Instructions for the backend model.
    public var instructions: String?
    /// Raw Responses tool definitions, forwarded untouched.
    public var tools: [OpenAIJSONValue]
    /// How the backend model chooses tools.
    public var toolChoice: OpenAILiveToolChoice?
    /// Whether the backend model may call tools in parallel.
    public var parallelToolCalls: Bool?
    /// The maximum number of output tokens per backend response.
    public var maxOutputTokens: Int?
    /// The Responses service tier.
    public var serviceTier: String?

    /// Creates Responses delegation settings.
    public init(
        model: String = "gpt-5.6-luna",
        instructions: String? = nil,
        tools: [OpenAIJSONValue] = [],
        toolChoice: OpenAILiveToolChoice? = nil,
        parallelToolCalls: Bool? = nil,
        maxOutputTokens: Int? = nil,
        serviceTier: String? = nil
    ) {
        self.model = model
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.maxOutputTokens = maxOutputTokens
        self.serviceTier = serviceTier
    }
}

/// Who answers the user during a GPT-Live session.
public enum OpenAILiveDelegation: Sendable, Equatable {
    /// Omit the `delegation` field and let GPT-Live answer on its own.
    case none
    /// Let OpenAI run a backend Responses model and stream the result back.
    case responses(OpenAILiveResponsesDelegation)
    /// Answer from the app, driven by `session.delegation.created` events.
    case client
}

/// Options for an OpenAI GPT-Live speech-to-speech session.
public struct OpenAILiveSessionOptions: Sendable, Equatable {
    /// The GPT-Live model that hosts the session.
    public var modelID: OpenAILiveModelID
    /// Instructions that shape how the model speaks.
    public var instructions: String?
    /// The output voice.
    public var voice: OpenAILiveVoice
    /// The wire format for input and output audio.
    public var audioFormat: OpenAILiveAudioFormat
    /// Who answers the user.
    public var delegation: OpenAILiveDelegation
    /// How long to wait for `session.closed` after asking to close, in seconds.
    public var closeTimeout: TimeInterval
    /// The largest silence, in milliseconds, that still continues a transcript entry.
    public var turnGapMilliseconds: Int

    /// Creates GPT-Live session options.
    public init(
        modelID: OpenAILiveModelID = .gptLive1,
        instructions: String? = nil,
        voice: OpenAILiveVoice = .marin,
        audioFormat: OpenAILiveAudioFormat = .pcm24k,
        delegation: OpenAILiveDelegation = .none,
        closeTimeout: TimeInterval = 15,
        turnGapMilliseconds: Int = 1200
    ) {
        self.modelID = modelID
        self.instructions = instructions
        self.voice = voice
        self.audioFormat = audioFormat
        self.delegation = delegation
        self.closeTimeout = closeTimeout
        self.turnGapMilliseconds = turnGapMilliseconds
    }
}

extension OpenAILiveSessionOptions {
    func validate() throws {
        if voice.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OpenAILiveError.invalidOptions("voice cannot be empty.")
        }
        if case .responses(let responses) = delegation,
           let maxOutputTokens = responses.maxOutputTokens,
           maxOutputTokens < 16 {
            throw OpenAILiveError.invalidOptions("maxOutputTokens must be at least 16.")
        }
        if closeTimeout <= 0 {
            throw OpenAILiveError.invalidOptions("closeTimeout must be greater than zero.")
        }
        if turnGapMilliseconds < 0 {
            throw OpenAILiveError.invalidOptions("turnGapMilliseconds cannot be negative.")
        }
    }
}

// MARK: - Client events

/// The wire payload for a `delegation` object.
struct OpenAILiveDelegationPayload: Encodable, Sendable {
    let type: String
    let responses: OpenAILiveResponsesDelegationPayload?

    init?(delegation: OpenAILiveDelegation) {
        switch delegation {
        case .none:
            return nil
        case .client:
            self.type = "client"
            self.responses = nil
        case .responses(let responses):
            self.type = "responses"
            self.responses = OpenAILiveResponsesDelegationPayload(responses)
        }
    }
}

/// The wire payload for `delegation.responses`.
struct OpenAILiveResponsesDelegationPayload: Encodable, Sendable {
    let model: String
    let instructions: String?
    let tools: [OpenAIJSONValue]?
    let toolChoice: OpenAILiveToolChoice?
    let parallelToolCalls: Bool?
    let maxOutputTokens: Int?
    let serviceTier: String?

    init(_ delegation: OpenAILiveResponsesDelegation) {
        self.model = delegation.model
        self.instructions = delegation.instructions
        self.tools = delegation.tools.isEmpty ? nil : delegation.tools
        self.toolChoice = delegation.toolChoice
        self.parallelToolCalls = delegation.parallelToolCalls
        self.maxOutputTokens = delegation.maxOutputTokens
        self.serviceTier = delegation.serviceTier
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case maxOutputTokens = "max_output_tokens"
        case serviceTier = "service_tier"
    }
}

/// The first client event of every GPT-Live session.
struct OpenAILiveSessionStartMessage: Encodable, Sendable {
    let type = "session.start"
    let eventID: String
    let session: Session

    struct Session: Encodable, Sendable {
        let model: String
        let instructions: String?
        let audio: Audio
        let delegation: OpenAILiveDelegationPayload?
    }

    struct Audio: Encodable, Sendable {
        let format: Format
        let output: Output
    }

    struct Format: Encodable, Sendable {
        let type: String
        let rate: Int
    }

    struct Output: Encodable, Sendable {
        let voice: String
    }

    init(options: OpenAILiveSessionOptions, eventID: String = "evt_session_start") {
        self.eventID = eventID
        self.session = Session(
            model: options.modelID.rawValue,
            instructions: options.instructions,
            audio: Audio(
                format: Format(type: options.audioFormat.mimeType, rate: options.audioFormat.sampleRate),
                output: Output(voice: options.voice.rawValue)
            ),
            delegation: OpenAILiveDelegationPayload(delegation: options.delegation)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
        case session
    }
}

/// A chunk of microphone audio streamed to GPT-Live.
struct OpenAILiveInputAudioAppendMessage: Encodable, Sendable {
    let type = "session.input_audio.append"
    let audio: String
    let byteCount: Int

    init(audioData: Data) {
        self.audio = audioData.base64EncodedString()
        self.byteCount = audioData.count
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case audio
    }
}

/// Stops GPT-Live from hearing microphone audio without ending the session.
struct OpenAILiveInputAudioMuteMessage: Encodable, Sendable {
    let type = "session.input_audio.mute"
}

/// Lets GPT-Live hear microphone audio again.
struct OpenAILiveInputAudioUnmuteMessage: Encodable, Sendable {
    let type = "session.input_audio.unmute"
}

/// Updates the mutable part of a running session, which is only `delegation.responses`.
struct OpenAILiveSessionUpdateMessage: Encodable, Sendable {
    let type = "session.update"
    let eventID: String
    let session: Session

    struct Session: Encodable, Sendable {
        let delegation: OpenAILiveDelegationPayload?
    }

    init(responses: OpenAILiveResponsesDelegation, eventID: String = UUID().uuidString) {
        self.eventID = eventID
        self.session = Session(delegation: OpenAILiveDelegationPayload(delegation: .responses(responses)))
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
        case session
    }
}

/// The kinds of context an app can push into a running GPT-Live session.
public enum OpenAILiveContextKind: String, Sendable, Equatable, CaseIterable {
    /// Trusted app directives the model must follow.
    case instructions
    /// Quiet factual context the model never speaks.
    case thinking
    /// Content the model may paraphrase aloud.
    case commentary

    /// The client event type that carries this context.
    public var clientEventType: String {
        "session.\(rawValue).append"
    }

    /// The server event type that acknowledges this context.
    public var serverEventType: String {
        "session.\(rawValue).appended"
    }

    /// Creates a context kind from a server acknowledgement type, when it is one.
    init?(serverEventType: String) {
        guard let kind = OpenAILiveContextKind.allCases.first(where: { $0.serverEventType == serverEventType }) else {
            return nil
        }
        self = kind
    }
}

/// Pushes instructions, thinking, or commentary into a running session.
struct OpenAILiveContextAppendMessage: Encodable, Sendable {
    let kind: OpenAILiveContextKind
    let eventID: String
    let delegationID: String?
    let content: String

    init(kind: OpenAILiveContextKind, content: String, delegationID: String? = nil, eventID: String = UUID().uuidString) {
        self.kind = kind
        self.content = content
        self.delegationID = delegationID
        self.eventID = eventID
    }

    /// Encodes the event, sending an explicit JSON `null` delegation id for session-wide context.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.clientEventType, forKey: .type)
        try container.encode(eventID, forKey: .eventID)
        if let delegationID {
            try container.encode(delegationID, forKey: .delegationID)
        } else {
            try container.encodeNil(forKey: .delegationID)
        }
        try container.encode(content, forKey: .content)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
        case delegationID = "delegation_id"
        case content
    }
}

/// Forwards a raw Responses item to a delegated backend.
struct OpenAILiveResponseItemCreateMessage: Encodable, Sendable {
    let type = "response.item.create"
    let eventID: String
    let delegationID: String?
    let item: OpenAIJSONValue

    init(item: OpenAIJSONValue, delegationID: String? = nil, eventID: String = UUID().uuidString) {
        self.item = item
        self.delegationID = delegationID
        self.eventID = eventID
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
        case delegationID = "delegation_id"
        case item
    }
}

/// Asks a delegated backend to answer over the items queued so far.
///
/// GPT-Live rejects every parameter beyond `type`, `event_id`, and
/// `delegation_id` with `unknown_parameter`: the request body belongs on
/// ``OpenAILiveResponseItemCreateMessage`` instead.
struct OpenAILiveResponseCreateMessage: Encodable, Sendable {
    let type = "response.create"
    let eventID: String
    let delegationID: String?

    init(delegationID: String? = nil, eventID: String = UUID().uuidString) {
        self.delegationID = delegationID
        self.eventID = eventID
    }

    /// Encodes the event, omitting `delegation_id` when the session has only one delegation.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(eventID, forKey: .eventID)
        try container.encodeIfPresent(delegationID, forKey: .delegationID)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
        case delegationID = "delegation_id"
    }
}

/// Asks GPT-Live to end the session gracefully.
struct OpenAILiveSessionCloseMessage: Encodable, Sendable {
    let type = "session.close"
    let eventID: String

    init(eventID: String = "evt_session_close") {
        self.eventID = eventID
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case eventID = "event_id"
    }
}

// MARK: - Server events

/// The resolved configuration of a GPT-Live session.
public struct OpenAILiveSessionInfo: Sendable, Equatable, Decodable {
    /// The provider session identifier.
    public let id: String
    /// The moment the session expires, when the provider reports one.
    public let expiresAt: Date?
    /// The resolved model name.
    public let model: String?
    /// The resolved output voice.
    public let voice: OpenAILiveVoice?
    /// The session status reported by the provider, such as `active`.
    public let status: String?

    /// Creates session information.
    public init(
        id: String,
        expiresAt: Date? = nil,
        model: String? = nil,
        voice: OpenAILiveVoice? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.expiresAt = expiresAt
        self.model = model
        self.voice = voice
        self.status = status
    }

    /// Decodes the `session` object of a GPT-Live server event.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)

        if let expiresAt = try container.decodeIfPresent(Double.self, forKey: .expiresAt) {
            self.expiresAt = Date(timeIntervalSince1970: expiresAt)
        } else {
            self.expiresAt = nil
        }

        if let audio = try? container.nestedContainer(keyedBy: AudioCodingKeys.self, forKey: .audio),
           let output = try? audio.nestedContainer(keyedBy: OutputCodingKeys.self, forKey: .output),
           let voice = try output.decodeIfPresent(String.self, forKey: .voice) {
            self.voice = OpenAILiveVoice(voice)
        } else {
            self.voice = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case expiresAt = "expires_at"
        case model
        case status
        case audio
    }

    private enum AudioCodingKeys: String, CodingKey {
        case output
    }

    private enum OutputCodingKeys: String, CodingKey {
        case voice
    }
}

/// A transcript fragment with its window on the session timeline.
struct OpenAILiveTranscriptDelta: Decodable, Sendable, Equatable {
    let delta: String
    let startMilliseconds: Int
    let endMilliseconds: Int
    let eventID: String?

    private enum CodingKeys: String, CodingKey {
        case delta
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
        case eventID = "event_id"
    }
}

/// An acknowledgement that pushed context landed on the session timeline.
struct OpenAILiveContextAppended: Sendable, Equatable {
    let kind: OpenAILiveContextKind
    let clientEventID: String?
    let startMilliseconds: Int?
    let endMilliseconds: Int?
}

/// A delegated turn GPT-Live opened, either for the app or for an OpenAI backend.
///
/// A session with ``OpenAILiveDelegation/client`` delegation must answer the
/// request itself through the context append events; a session with
/// ``OpenAILiveDelegation/responses(_:)`` delegation receives this as a receipt
/// and the answer arrives as ``OpenAILiveResponseEvent`` values.
public struct OpenAILiveDelegationRequest: Sendable, Equatable, Decodable {
    /// The delegation identifier to echo back on context append events.
    public let id: String
    /// The delegation target reported by the provider, such as `client` or `responses`.
    public let target: String?
    /// The backend response the delegation belongs to, when the provider reports one.
    public let responseID: String?
    /// The `event_id` of the client event that opened the delegation, when the provider echoes one.
    public let clientEventID: String?
    /// Where the delegation sits on the session timeline, in milliseconds.
    public let offsetMilliseconds: Int?

    /// Creates a delegation request.
    public init(
        id: String,
        target: String? = nil,
        responseID: String? = nil,
        clientEventID: String? = nil,
        offsetMilliseconds: Int? = nil
    ) {
        self.id = id
        self.target = target
        self.responseID = responseID
        self.clientEventID = clientEventID
        self.offsetMilliseconds = offsetMilliseconds
    }

    /// Decodes the `delegation` object of a `session.delegation.created` event.
    ///
    /// `client_event_id` and `offset_ms` live on the event rather than the
    /// delegation, so ``OpenAILiveMessage`` fills them in.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.target = try container.decodeIfPresent(String.self, forKey: .target)
        self.responseID = try container.decodeIfPresent(String.self, forKey: .responseID)
        self.clientEventID = nil
        self.offsetMilliseconds = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case target
        case responseID = "response_id"
    }
}

/// A GPT-Live acknowledgement or rejection of pushed context.
///
/// GPT-Live only acknowledges pushed context once the session timeline advances,
/// which needs audio. A silent session receives no `*.appended` event at all and
/// instead reports `context_injection_incomplete` for each append when it closes,
/// so context appends are fire-and-forget and their outcome arrives here.
public enum OpenAILiveContextEvent: Sendable, Equatable {
    /// The provider placed pushed context on the session timeline.
    case appended(
        kind: OpenAILiveContextKind,
        clientEventID: String,
        startMilliseconds: Int?,
        endMilliseconds: Int?
    )
    /// The provider refused pushed context, or the session ended before it landed.
    case rejected(clientEventID: String, code: String?, message: String)
}

/// A nested Responses stream event produced by a delegated backend.
public struct OpenAILiveResponseEvent: Sendable, Equatable {
    /// The delegation that produced the event, when the provider reports one.
    public let delegationID: String?
    /// The `type` of the nested Responses event.
    public let eventType: String
    /// The nested event, unchanged.
    public let raw: OpenAIJSONValue

    /// Creates a response event.
    public init(delegationID: String?, eventType: String, raw: OpenAIJSONValue) {
        self.delegationID = delegationID
        self.eventType = eventType
        self.raw = raw
    }
}

/// A cumulative usage snapshot for a GPT-Live session.
public struct OpenAILiveUsage: Sendable, Equatable {
    /// The cumulative billed seconds. This is a snapshot, not an increment.
    public let seconds: Double
    /// How much of the model's context window the session has used, from 0 to 1.
    public let contextWindowUsageRatio: Double?

    /// Creates a usage snapshot.
    public init(seconds: Double, contextWindowUsageRatio: Double? = nil) {
        self.seconds = seconds
        self.contextWindowUsageRatio = contextWindowUsageRatio
    }
}

/// The final event of a GPT-Live session.
struct OpenAILiveSessionClosed: Sendable, Equatable {
    let reason: SpeechConversationEndReason
    let seconds: Double?
    let session: OpenAILiveSessionInfo?
}

/// An error event from GPT-Live.
///
/// A moderation error can cut speech short without closing the session, so not
/// every error event is fatal.
struct OpenAILiveErrorPayload: Sendable, Equatable {
    let type: String?
    let code: String?
    let message: String
    let param: String?
    let clientEventID: String?
}

/// A decoded GPT-Live server event.
enum OpenAILiveMessage: Decodable, Sendable {
    /// The session is ready and audio can start streaming.
    case sessionStarted(OpenAILiveSessionInfo)
    /// A `session.update` was applied, carrying the `event_id` of the request it answers.
    case sessionUpdated(OpenAILiveSessionInfo, clientEventID: String?)
    /// A chunk of assistant audio, already base64-decoded.
    case outputAudioDelta(Data)
    /// A fragment of the user's transcript.
    case inputTranscriptDelta(OpenAILiveTranscriptDelta)
    /// A fragment of the assistant's transcript.
    case outputTranscriptDelta(OpenAILiveTranscriptDelta)
    /// The provider stopped listening to microphone audio.
    case inputAudioMuted
    /// The provider resumed listening to microphone audio.
    case inputAudioUnmuted
    /// Pushed context landed on the session timeline.
    case contextAppended(OpenAILiveContextAppended)
    /// The provider asked the app to answer a turn.
    case delegationCreated(OpenAILiveDelegationRequest)
    /// A nested Responses event from a delegated backend.
    case responseEvent(OpenAILiveResponseEvent)
    /// A cumulative usage snapshot.
    case usageUpdated(OpenAILiveUsage)
    /// The session ended.
    case sessionClosed(OpenAILiveSessionClosed)
    /// An error event, which may or may not end the session.
    case error(OpenAILiveErrorPayload)
    /// An event type this version of SpeechKit does not model.
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let singleValueContainer = try decoder.singleValueContainer()

        switch type {
        case "session.started":
            self = .sessionStarted(try container.decode(OpenAILiveSessionInfo.self, forKey: .session))
        case "session.updated":
            self = .sessionUpdated(
                try container.decode(OpenAILiveSessionInfo.self, forKey: .session),
                clientEventID: try container.decodeIfPresent(String.self, forKey: .clientEventID)
            )
        case "session.output_audio.delta":
            let base64 = try container.decode(String.self, forKey: .delta)
            guard let audio = Data(base64Encoded: base64) else {
                self = .unknown(type)
                return
            }
            self = .outputAudioDelta(audio)
        case "session.input_transcript.delta":
            self = .inputTranscriptDelta(try singleValueContainer.decode(OpenAILiveTranscriptDelta.self))
        case "session.output_transcript.delta":
            self = .outputTranscriptDelta(try singleValueContainer.decode(OpenAILiveTranscriptDelta.self))
        case "session.input_audio.muted":
            self = .inputAudioMuted
        case "session.input_audio.unmuted":
            self = .inputAudioUnmuted
        case "session.delegation.created":
            let delegation = try container.decode(OpenAILiveDelegationRequest.self, forKey: .delegation)
            self = .delegationCreated(
                OpenAILiveDelegationRequest(
                    id: delegation.id,
                    target: delegation.target,
                    responseID: delegation.responseID,
                    clientEventID: try container.decodeIfPresent(String.self, forKey: .clientEventID),
                    offsetMilliseconds: try container.decodeIfPresent(Int.self, forKey: .offsetMilliseconds)
                )
            )
        case "response.event":
            let event = try container.decode(OpenAIJSONValue.self, forKey: .event)
            let eventType = event.objectValue?["type"]?.stringValue ?? "unknown"
            self = .responseEvent(
                OpenAILiveResponseEvent(
                    delegationID: try container.decodeIfPresent(String.self, forKey: .delegationID),
                    eventType: eventType,
                    raw: event
                )
            )
        case "session.usage.updated":
            self = .usageUpdated(
                OpenAILiveUsage(
                    seconds: Self.decodeUsageSeconds(from: container) ?? 0,
                    contextWindowUsageRatio: Self.decodeContextWindowUsageRatio(from: container)
                )
            )
        case "session.closed":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .sessionClosed(
                OpenAILiveSessionClosed(
                    reason: SpeechConversationEndReason(providerRawValue: reason ?? ""),
                    seconds: Self.decodeUsageSeconds(from: container),
                    session: try container.decodeIfPresent(OpenAILiveSessionInfo.self, forKey: .session)
                )
            )
        case "error":
            self = .error(try Self.decodeError(from: container))
        default:
            if let kind = OpenAILiveContextKind(serverEventType: type) {
                self = .contextAppended(
                    OpenAILiveContextAppended(
                        kind: kind,
                        clientEventID: try container.decodeIfPresent(String.self, forKey: .clientEventID),
                        startMilliseconds: try container.decodeIfPresent(Int.self, forKey: .startMilliseconds),
                        endMilliseconds: try container.decodeIfPresent(Int.self, forKey: .endMilliseconds)
                    )
                )
            } else {
                self = .unknown(type)
            }
        }
    }

    private static func decodeUsageSeconds(from container: KeyedDecodingContainer<CodingKeys>) -> Double? {
        guard let usage = try? container.nestedContainer(keyedBy: UsageCodingKeys.self, forKey: .usage) else {
            return nil
        }
        return try? usage.decodeIfPresent(Double.self, forKey: .seconds)
    }

    private static func decodeContextWindowUsageRatio(from container: KeyedDecodingContainer<CodingKeys>) -> Double? {
        guard let window = try? container.nestedContainer(keyedBy: ContextWindowCodingKeys.self, forKey: .contextWindow) else {
            return nil
        }
        return try? window.decodeIfPresent(Double.self, forKey: .usageRatio)
    }

    private static func decodeError(from container: KeyedDecodingContainer<CodingKeys>) throws -> OpenAILiveErrorPayload {
        let fallbackMessage = "OpenAI GPT-Live error."
        let topLevelClientEventID = try container.decodeIfPresent(String.self, forKey: .clientEventID)
        guard let error = try? container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error) else {
            return OpenAILiveErrorPayload(
                type: nil,
                code: nil,
                message: fallbackMessage,
                param: nil,
                clientEventID: topLevelClientEventID
            )
        }

        return OpenAILiveErrorPayload(
            type: try error.decodeIfPresent(String.self, forKey: .type),
            code: try error.decodeIfPresent(String.self, forKey: .code),
            message: try error.decodeIfPresent(String.self, forKey: .message) ?? fallbackMessage,
            param: try error.decodeIfPresent(String.self, forKey: .param),
            clientEventID: try error.decodeIfPresent(String.self, forKey: .clientEventID) ?? topLevelClientEventID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case session
        case delta
        case error
        case usage
        case reason
        case delegation
        case event
        case startMilliseconds = "start_ms"
        case endMilliseconds = "end_ms"
        case clientEventID = "client_event_id"
        case delegationID = "delegation_id"
        case contextWindow = "context_window"
        case offsetMilliseconds = "offset_ms"
    }

    private enum UsageCodingKeys: String, CodingKey {
        case seconds
    }

    private enum ContextWindowCodingKeys: String, CodingKey {
        case usageRatio = "usage_ratio"
    }

    private enum ErrorCodingKeys: String, CodingKey {
        case type
        case code
        case message
        case param
        case clientEventID = "client_event_id"
    }
}

/// Errors returned by OpenAI GPT-Live speech-to-speech sessions.
public enum OpenAILiveError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid GPT-Live URL.
    case invalidURL
    /// The GPT-Live connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing GPT-Live message.
    case encodingFailed
    /// The GPT-Live WebSocket disconnected.
    case disconnected
    /// The user denied microphone permission.
    case permissionDenied
    /// The OpenAI API key is empty.
    case apiKeyMissing
    /// The supplied GPT-Live options are invalid.
    case invalidOptions(String)
    /// The provider rejected the session before it started.
    case sessionRejected(code: String?, message: String)
    /// The provider rejected a client event.
    case commandRejected(clientEventID: String?, code: String?, message: String)
    /// The provider never acknowledged `session.close`.
    case closeTimedOut

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OpenAI GPT-Live URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .permissionDenied:
            return "Microphone permission denied"
        case .apiKeyMissing:
            return "API key not configured"
        case .invalidOptions(let message):
            return message
        case .sessionRejected(let code, let message):
            guard let code else { return message }
            return "\(message) (\(code))"
        case .commandRejected(_, let code, let message):
            guard let code else { return message }
            return "\(message) (\(code))"
        case .closeTimedOut:
            return "Timed out waiting for the session to close"
        }
    }
}
