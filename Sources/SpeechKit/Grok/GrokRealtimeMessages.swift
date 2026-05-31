import Foundation

/// Audio encodings supported by Grok realtime transcription.
public enum GrokRealtimeAudioEncoding: String, Sendable, CaseIterable {
    /// Linear PCM audio.
    case pcm
    /// mu-law audio.
    case mulaw
    /// A-law audio.
    case alaw
}

/// Options for a Grok realtime transcription session.
///
/// SpeechKit sends these values as Grok realtime WebSocket query parameters.
public struct GrokRealtimeOptions: Sendable, Equatable {
    /// An optional language hint.
    public var language: GrokLanguage?
    /// The raw audio sample rate, in hertz.
    public var sampleRate: Int
    /// The raw audio encoding.
    public var encoding: GrokRealtimeAudioEncoding
    /// A Boolean value that indicates whether Grok should emit interim transcript events.
    public var interimResults: Bool
    /// Endpointing silence duration in milliseconds.
    public var endpointingMilliseconds: Int
    /// A Boolean value that indicates whether Grok should process multichannel audio.
    public var multichannel: Bool
    /// The number of audio channels.
    public var channels: Int
    /// A Boolean value that indicates whether Grok should identify speakers.
    public var diarize: Bool
    /// A Boolean value that indicates whether Grok should include filler words.
    public var fillerWords: Bool
    /// Key terms to bias transcription toward.
    public var keyTerms: [String]

    /// Creates Grok realtime session options.
    public init(
        language: GrokLanguage? = nil,
        sampleRate: Int = 16000,
        encoding: GrokRealtimeAudioEncoding = .pcm,
        interimResults: Bool = true,
        endpointingMilliseconds: Int = 10,
        multichannel: Bool = false,
        channels: Int = 1,
        diarize: Bool = false,
        fillerWords: Bool = false,
        keyTerms: [String] = []
    ) {
        self.language = language
        self.sampleRate = sampleRate
        self.encoding = encoding
        self.interimResults = interimResults
        self.endpointingMilliseconds = endpointingMilliseconds
        self.multichannel = multichannel
        self.channels = channels
        self.diarize = diarize
        self.fillerWords = fillerWords
        self.keyTerms = keyTerms
    }

    func validate() throws {
        if ![8000, 16000, 22050, 24000, 44100, 48000].contains(sampleRate) {
            throw SpeechError.providerFailure(provider: .grok, reason: "Unsupported realtime sample_rate: \(sampleRate).")
        }
        if !(0...5000).contains(endpointingMilliseconds) {
            throw SpeechError.providerFailure(provider: .grok, reason: "endpointingMilliseconds must be between 0 and 5000.")
        }
        if !(1...8).contains(channels) {
            throw SpeechError.providerFailure(provider: .grok, reason: "channels must be between 1 and 8.")
        }
        if keyTerms.count > 100 {
            throw SpeechError.providerFailure(provider: .grok, reason: "keyTerms cannot contain more than 100 items.")
        }
        if let keyTerm = keyTerms.first(where: { $0.count > 50 }) {
            throw SpeechError.providerFailure(provider: .grok, reason: "keyTerm exceeds 50 characters: \(keyTerm).")
        }
    }

    func queryItems() throws -> [URLQueryItem] {
        try validate()

        var items: [URLQueryItem] = [
            URLQueryItem(name: "sample_rate", value: String(sampleRate)),
            URLQueryItem(name: "encoding", value: encoding.rawValue),
            URLQueryItem(name: "interim_results", value: String(interimResults)),
            URLQueryItem(name: "endpointing", value: String(endpointingMilliseconds)),
            URLQueryItem(name: "multichannel", value: String(multichannel)),
            URLQueryItem(name: "channels", value: String(channels)),
            URLQueryItem(name: "diarize", value: String(diarize)),
            URLQueryItem(name: "filler_words", value: String(fillerWords))
        ]

        if let language {
            items.append(URLQueryItem(name: "language", value: language.rawValue))
        }

        for keyTerm in keyTerms {
            items.append(URLQueryItem(name: "keyterm", value: keyTerm))
        }

        return items
    }
}

struct GrokAudioDoneMessage: Encodable, Sendable {
    let type = "audio.done"
}

enum GrokRealtimeMessage: Decodable, Sendable {
    case transcriptCreated(GrokTranscriptCreated)
    case transcriptPartial(GrokTranscript)
    case transcriptDone(GrokTranscript)
    case error(String)
    case unknown(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case error
        case message
    }

    private enum ErrorCodingKeys: String, CodingKey {
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let singleValueContainer = try decoder.singleValueContainer()

        switch type {
        case "transcript.created":
            self = .transcriptCreated(try singleValueContainer.decode(GrokTranscriptCreated.self))
        case "transcript.partial":
            self = .transcriptPartial(try singleValueContainer.decode(GrokTranscript.self))
        case "transcript.done":
            self = .transcriptDone(try singleValueContainer.decode(GrokTranscript.self))
        case "error":
            if let error = try? container.nestedContainer(keyedBy: ErrorCodingKeys.self, forKey: .error),
               let message = try? error.decode(String.self, forKey: .message) {
                self = .error(message)
            } else {
                self = .error((try? container.decode(String.self, forKey: .message)) ?? "Grok realtime error.")
            }
        default:
            self = .unknown(type)
        }
    }
}

struct GrokTranscriptCreated: Decodable, Sendable {
    let sessionID: String?

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

struct GrokTranscript: Decodable, Sendable, Equatable {
    let text: String
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?
    let channelIndex: Int?
    let speaker: String?
    let words: [GrokRealtimeWord]?

    private enum CodingKeys: String, CodingKey {
        case text
        case isFinal = "is_final"
        case speechFinal = "speech_final"
        case start
        case duration
        case channelIndex = "channel_index"
        case speaker
        case words
    }
}

struct GrokRealtimeWord: Decodable, Sendable, Equatable {
    let text: String
    let start: Double?
    let end: Double?
    let speaker: String?
    let confidence: Double?
}

extension SpeechTranscriptWord {
    init(_ word: GrokRealtimeWord) {
        self.init(
            text: word.text,
            start: word.start,
            end: word.end,
            speaker: word.speaker,
            confidence: word.confidence
        )
    }
}

/// Errors returned by Grok-specific realtime APIs.
public enum GrokRealtimeError: Error, LocalizedError, Sendable, Equatable {
    /// SpeechKit could not construct a valid Grok realtime URL.
    case invalidURL
    /// The realtime connection failed.
    case connectionFailed(String)
    /// SpeechKit could not encode an outgoing realtime message.
    case encodingFailed
    /// The realtime WebSocket disconnected.
    case disconnected
    /// The Grok API key is empty.
    case apiKeyMissing

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Grok realtime URL"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .encodingFailed:
            return "Failed to encode message"
        case .disconnected:
            return "WebSocket disconnected"
        case .apiKeyMissing:
            return "API key not configured"
        }
    }
}
