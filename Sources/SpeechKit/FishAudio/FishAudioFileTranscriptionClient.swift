import Foundation

/// Fish Audio file transcription model identifiers supported by SpeechKit.
///
/// Fish Audio selects the model from a `model` HTTP header rather than a body
/// field. A missing or misspelled header silently falls back to the retired
/// `transcribe-1` model, so SpeechKit always sends this header.
public enum FishAudioFileTranscriptionModelID: String, Sendable, CaseIterable {
    /// Transcribe 1 Pro, Fish Audio's file transcription model.
    case transcribe1Pro = "transcribe-1-pro"
}

/// Speaker diarization modes for Fish Audio file transcription.
public enum FishAudioDiarization: String, Sendable, CaseIterable {
    /// Fish Audio decides whether to label speakers.
    case auto
    /// Fish Audio always labels speakers.
    case on = "true"
    /// Fish Audio never labels speakers.
    case off = "false"
}

/// A hint for the number of speakers in a Fish Audio file transcription.
public enum FishAudioSpeakerCount: Sendable, Equatable {
    /// The audio has exactly this many speakers. Sent as `num_speakers`.
    case exact(Int)
    /// The audio has between `min` and `max` speakers. Sent as `min_speakers` and `max_speakers`.
    ///
    /// Pass `nil` for either bound to leave it open. At least one bound is required.
    case range(min: Int?, max: Int?)
}

/// Options for a Fish Audio file transcription request.
public struct FishAudioFileTranscriptionOptions: Sendable, Equatable {
    /// The Fish Audio transcription model to use. Sent as the `model` header.
    public var modelID: FishAudioFileTranscriptionModelID
    /// A lowercase two-letter ISO 639-1 language hint such as `"en"`, or `nil` to let Fish Audio detect the language.
    ///
    /// The hint helps detection but does not force the transcript language.
    public var language: String?
    /// A Boolean value that indicates whether Fish Audio should return word segments and speaker turns.
    ///
    /// Timestamps are on by default so the response carries words. Turning
    /// them off sends `ignore_timestamps=true`, which is faster but leaves
    /// ``FishAudioFileTranscriptionResponse/segments`` and
    /// ``FishAudioFileTranscriptionResponse/speakerTurns`` empty.
    public var timestamps: Bool
    /// The speaker diarization mode.
    public var diarize: FishAudioDiarization
    /// An optional hint for the number of speakers.
    ///
    /// A speaker count cannot be combined with ``FishAudioDiarization/off``.
    public var speakerCount: FishAudioSpeakerCount?
    /// A Boolean value that indicates whether Fish Audio should keep sound cues such as `[laughter]` in the text.
    public var tagAudioEvents: Bool
    /// The network timeout for the upload request.
    ///
    /// Fish Audio responds only after the whole file is transcribed, so long
    /// files can take several minutes. The default is 15 minutes.
    public var timeoutInterval: TimeInterval

    /// Creates Fish Audio file transcription options.
    public init(
        modelID: FishAudioFileTranscriptionModelID = .transcribe1Pro,
        language: String? = nil,
        timestamps: Bool = true,
        diarize: FishAudioDiarization = .auto,
        speakerCount: FishAudioSpeakerCount? = nil,
        tagAudioEvents: Bool = true,
        timeoutInterval: TimeInterval = 15 * 60
    ) {
        self.modelID = modelID
        self.language = language
        self.timestamps = timestamps
        self.diarize = diarize
        self.speakerCount = speakerCount
        self.tagAudioEvents = tagAudioEvents
        self.timeoutInterval = timeoutInterval
    }
}

/// One timed word from a Fish Audio transcription.
///
/// Fish Audio returns segment text without punctuation or speaker labels, and
/// may normalise it, for example `35` for `3.5`.
public struct FishAudioTranscriptionSegment: Decodable, Sendable, Equatable {
    /// The word text.
    public let text: String
    /// The word start time, in seconds.
    public let start: Double?
    /// The word end time, in seconds.
    public let end: Double?

    /// Creates a Fish Audio transcript segment.
    public init(text: String, start: Double? = nil, end: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case start
        case end
    }

    /// Creates a segment by decoding Fish Audio's JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.start = try container.decodeIfPresent(Double.self, forKey: .start)
        self.end = try container.decodeIfPresent(Double.self, forKey: .end)
    }
}

/// One speaker turn from a Fish Audio transcription.
public struct FishAudioSpeakerTurn: Decodable, Sendable, Equatable {
    /// The speaker label, such as `"speaker:0"`.
    public let speaker: String
    /// The punctuated turn text.
    public let text: String
    /// The turn start time, in seconds.
    public let start: Double?
    /// The turn end time, in seconds.
    public let end: Double?

    /// Creates a Fish Audio speaker turn.
    public init(speaker: String, text: String, start: Double? = nil, end: Double? = nil) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }

    private enum CodingKeys: String, CodingKey {
        case speaker
        case text
        case start
        case end
    }

    /// Creates a speaker turn by decoding Fish Audio's JSON.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.speaker = try container.decodeIfPresent(String.self, forKey: .speaker) ?? ""
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.start = try container.decodeIfPresent(Double.self, forKey: .start)
        self.end = try container.decodeIfPresent(Double.self, forKey: .end)
    }
}

/// A timed transcript word that SpeechKit derives from a Fish Audio response.
///
/// Each word comes from a ``FishAudioTranscriptionSegment``. SpeechKit labels
/// it with the speaker whose turn contains the word's midpoint, and copies
/// punctuation and capitalisation from the matching token in the punctuated
/// speaker turn text when the two agree.
public struct FishAudioTranscriptWord: Sendable, Equatable {
    /// The word text, with punctuation when SpeechKit could match it to a speaker turn.
    public let text: String
    /// The word start time, in seconds.
    public let start: Double?
    /// The word end time, in seconds.
    public let end: Double?
    /// The speaker label, such as `"speaker:0"`, when a speaker turn contains the word.
    public let speaker: String?

    /// Creates a Fish Audio transcript word.
    public init(text: String, start: Double? = nil, end: Double? = nil, speaker: String? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// A detailed Fish Audio file transcription response.
///
/// The raw fields are kept exactly as Fish Audio returned them.
/// ``transcriptText`` and ``words`` are derived from them for callers that
/// want plain text and punctuated, speaker-labelled words.
public struct FishAudioFileTranscriptionResponse: Decodable, Sendable, Equatable {
    /// The raw transcript text, including inline `<|speaker:N|>` markers and `[cue]` tags.
    public let text: String
    /// The duration of the audio, in seconds.
    public let duration: Double?
    /// The timed words. Empty when timestamps are off, or when Fish Audio has no timing for the audio.
    public let segments: [FishAudioTranscriptionSegment]
    /// The punctuated speaker turns. Empty when timestamps are off.
    public let speakerTurns: [FishAudioSpeakerTurn]
    /// The detected language as an English name, such as `"English"`.
    public let language: String?
    /// The detected language code, such as `"en"`.
    public let languageCode: String?
    /// The request identifier assigned by Fish Audio.
    public let requestID: String?

    /// The transcript text with `<|speaker:N|>` markers removed.
    ///
    /// Sound cues such as `[laughter]` are kept.
    public let transcriptText: String
    /// Timed words derived from ``segments``, labelled with speakers and punctuated from ``speakerTurns``.
    public let words: [FishAudioTranscriptWord]

    /// Creates a detailed Fish Audio file transcription response.
    public init(
        text: String,
        duration: Double? = nil,
        segments: [FishAudioTranscriptionSegment] = [],
        speakerTurns: [FishAudioSpeakerTurn] = [],
        language: String? = nil,
        languageCode: String? = nil,
        requestID: String? = nil
    ) {
        self.text = text
        self.duration = duration
        self.segments = segments
        self.speakerTurns = speakerTurns
        self.language = language
        self.languageCode = languageCode
        self.requestID = requestID
        self.transcriptText = FishAudioTranscriptMapping.removingSpeakerMarkers(from: text)
        self.words = FishAudioTranscriptMapping.words(
            segments: segments,
            speakerTurns: speakerTurns,
            fallbackText: text
        )
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case duration
        case segments
        case speakerTurns = "speaker_turns"
        case language
        case languageCode = "language_code"
        case requestID = "request_id"
    }

    /// Creates a response by decoding Fish Audio's JSON.
    ///
    /// Fish Audio omits fields it does not return rather than sending `null`,
    /// so every field is optional.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
            duration: try container.decodeIfPresent(Double.self, forKey: .duration),
            segments: try container.decodeIfPresent([FishAudioTranscriptionSegment].self, forKey: .segments) ?? [],
            speakerTurns: try container.decodeIfPresent([FishAudioSpeakerTurn].self, forKey: .speakerTurns) ?? [],
            language: try container.decodeIfPresent(String.self, forKey: .language),
            languageCode: try container.decodeIfPresent(String.self, forKey: .languageCode),
            requestID: try container.decodeIfPresent(String.self, forKey: .requestID)
        )
    }
}

struct FishAudioFileTranscriptionClient {
    static let defaultUploadURL = URL(string: "https://api.fish.audio/v1/asr")
    /// Fish Audio's maximum audio duration, in seconds.
    static let maxUploadDuration: TimeInterval = 3600
    /// Extensions Fish Audio rejects. AIFF and CAF are common on Apple platforms, so they fail before upload.
    static let rejectedExtensions: Set<String> = ["aif", "aiff", "aifc", "caf"]

    private let credential: SpeechCredential
    private let urlSession: URLSession
    private let uploadURL: URL?

    init(apiKey: String, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.init(credential: .apiKey(apiKey), endpoint: endpoint, urlSession: urlSession)
    }

    init(credential: SpeechCredential, endpoint: URL? = nil, urlSession: URLSession = SpeechTransport.session()) {
        self.credential = credential
        self.urlSession = SpeechTransport.session(copying: urlSession, pinnedPublicKeyHashes: credential.pinnedPublicKeyHashes)
        self.uploadURL = endpoint ?? Self.defaultUploadURL
    }

    func transcribeAudioFile(
        file: URL,
        options: FishAudioFileTranscriptionOptions = FishAudioFileTranscriptionOptions()
    ) async throws -> String {
        let response = try await transcribeAudioFileDetailed(file: file, options: options)
        return response.transcriptText
    }

    func transcribeAudioFileDetailed(
        file: URL,
        options: FishAudioFileTranscriptionOptions = FishAudioFileTranscriptionOptions()
    ) async throws -> FishAudioFileTranscriptionResponse {
        let prepared = try await SpeechRelayAudioImport.prepare(file: file, provider: .fishAudio,
            optimizeUploads: credential.optimizeUploads, maxDuration: Self.maxUploadDuration)
        defer { prepared.remove() }
        let file = prepared.file
        let request = try await makeRequest(file: file, options: options)
        let (data, response) = try await SpeechTransport.data(for: request, session: urlSession, prepare: self.credential.relayRequestPreparation)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechError.invalidResponse(provider: .fishAudio)
        }
        return try Self.decodeResponse(data: data, statusCode: httpResponse.statusCode)
    }

    /// Decodes a Fish Audio response body, or maps a non-2xx status to a ``SpeechError``.
    static func decodeResponse(data: Data, statusCode: Int) throws -> FishAudioFileTranscriptionResponse {
        guard (200...299).contains(statusCode) else {
            throw FishAudioAPIFailure(statusCode: statusCode, body: data).speechError
        }

        do {
            return try JSONDecoder().decode(FishAudioFileTranscriptionResponse.self, from: data)
        } catch {
            throw SpeechError.decodingFailed(provider: .fishAudio, reason: .decodingFailed)
        }
    }

    func makeRequest(
        file: URL,
        options: FishAudioFileTranscriptionOptions = FishAudioFileTranscriptionOptions()
    ) async throws -> URLRequest {
        guard credential.isConfigured else {
            throw SpeechError.providerNotConfigured(.fishAudio)
        }
        try validate(options)
        try Self.validateFileExtension(file)
        try await SpeechFileUploadSupport.validateFileDuration(
            file,
            maxDuration: Self.maxUploadDuration,
            provider: .fishAudio
        )
        try validate(options)
        let resolved = try await credential.resolved(for: .fishAudio, model: options.modelID.rawValue, endpoint: uploadURL)
        return try makeRequest(file: file, options: options, secret: resolved.secret)
    }

    /// Builds an upload request from an already-resolved secret.
    ///
    /// API keys and custom proxy credentials use Bearer authorization. This
    /// overload does not check the audio duration; the async overload does.
    func makeRequest(
        file: URL,
        options: FishAudioFileTranscriptionOptions = FishAudioFileTranscriptionOptions(),
        secret: String
    ) throws -> URLRequest {
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechError.providerNotConfigured(.fishAudio)
        }
        guard let uploadURL else {
            throw SpeechError.invalidResponse(provider: .fishAudio)
        }

        try validate(options)
        try Self.validateFileExtension(file)

        let audioData = try readFileData(from: file)
        let boundary = "SpeechKit-\(UUID().uuidString)"
        var parts: [SpeechMultipartFormPart] = []
        if let language = options.language {
            parts.append(.text(name: "language", value: language))
        }
        // Fish Audio treats any multipart boolean other than "true" as false,
        // so booleans are always sent as the literal strings.
        parts.append(.text(name: "ignore_timestamps", value: options.timestamps ? "false" : "true"))
        parts.append(.text(name: "tag_audio_events", value: options.tagAudioEvents ? "true" : "false"))
        parts.append(.text(name: "diarize", value: options.diarize.rawValue))
        switch options.speakerCount {
        case .exact(let count):
            parts.append(.text(name: "num_speakers", value: String(count)))
        case .range(let minimum, let maximum):
            if let minimum {
                parts.append(.text(name: "min_speakers", value: String(minimum)))
            }
            if let maximum {
                parts.append(.text(name: "max_speakers", value: String(maximum)))
            }
        case nil:
            break
        }
        parts.append(
            .file(
                name: "audio",
                fileURL: credential.uploadFileURL(file),
                fileData: audioData,
                contentType: SpeechFileUploadSupport.mimeType(for: credential.uploadFileURL(file))
            )
        )

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeoutInterval
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        // The model is chosen by this header. Without an exact match Fish Audio
        // silently runs, and bills, the retired transcribe-1 model.
        request.setValue(options.modelID.rawValue, forHTTPHeaderField: "model")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpeechFileUploadSupport.makeMultipartBody(boundary: boundary, parts: parts)
        return request
    }

    private func validate(_ options: FishAudioFileTranscriptionOptions) throws {
        try FishAudioValidation.validateLanguage(options.language)
        try FishAudioValidation.validateSpeakerCount(options.speakerCount, diarize: options.diarize)

        if options.timeoutInterval <= 0 {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
        }
    }

    static func validateFileExtension(_ fileURL: URL) throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        guard !rejectedExtensions.contains(fileExtension) else {
            throw SpeechError.providerFailure(
                provider: .fishAudio,
                reason: .requestFailed)
        }
    }

    private func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
        }
    }
}

/// Validation for Fish Audio requests.
enum FishAudioValidation {
    /// Rejects a language that is not a lowercase two-letter ISO 639-1 code.
    static func validateLanguage(_ language: String?) throws {
        guard let language else { return }
        let isLowercaseTwoLetterCode = language.count == 2
            && language.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
        guard isLowercaseTwoLetterCode else {
            throw SpeechError.providerFailure(
                provider: .fishAudio,
                reason: .requestFailed)
        }
    }

    /// Rejects speaker counts that are out of range, empty, or combined with diarization turned off.
    static func validateSpeakerCount(_ speakerCount: FishAudioSpeakerCount?, diarize: FishAudioDiarization) throws {
        guard let speakerCount else { return }
        if diarize == .off {
            throw SpeechError.providerFailure(
                provider: .fishAudio,
                reason: .requestFailed)
        }

        switch speakerCount {
        case .exact(let count):
            if count < 1 {
                throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
            }
        case .range(let minimum, let maximum):
            if minimum == nil, maximum == nil {
                throw SpeechError.providerFailure(
                    provider: .fishAudio,
                    reason: .requestFailed)
            }
            if let minimum, minimum < 1 {
                throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
            }
            if let maximum, maximum < 1 {
                throw SpeechError.providerFailure(provider: .fishAudio, reason: .requestFailed)
            }
            if let minimum, let maximum, minimum > maximum {
                throw SpeechError.providerFailure(
                    provider: .fishAudio,
                    reason: .requestFailed)
            }
        }
    }
}

/// A Fish Audio error response, `{status, message, code?, request_id?}`.
///
/// Errors from Fish Audio's network edge can arrive with no body or a
/// non-JSON body, so every field is optional.
struct FishAudioAPIFailure: Sendable, Equatable {
    let statusCode: Int
    let code: String?
    let message: String?
    let requestID: String?

    private struct Body: Decodable {
        let message: String?
        let code: String?
        let requestID: String?

        private enum CodingKeys: String, CodingKey {
            case message
            case code
            case requestID = "request_id"
        }
    }

    init(statusCode: Int, code: String? = nil, message: String? = nil, requestID: String? = nil) {
        self.statusCode = statusCode
        self.code = code
        self.message = message
        self.requestID = requestID
    }

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        if let decoded = try? JSONDecoder().decode(Body.self, from: body) {
            self.code = decoded.code
            self.message = decoded.message
            self.requestID = decoded.requestID
        } else {
            self.code = nil
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.message = (text?.isEmpty ?? true) ? nil : text
            self.requestID = nil
        }
    }

    /// A Boolean value that indicates whether the same request may succeed if retried later.
    ///
    /// Fish Audio's concurrency limit (`429`) and its `5xx` failures are
    /// transient. Every other failure needs a different request.
    var isRetryable: Bool {
        statusCode == 429 || (500...599).contains(statusCode)
    }

    /// A short explanation of the failure, chosen by `code` first and then by HTTP status.
    var summary: String {
        switch code {
        case "invalid_request":
            return "The request was invalid"
        case "invalid_parameter":
            return "A request parameter was invalid"
        case "invalid_audio":
            return "The audio could not be decoded"
        case "audio_too_long":
            return "The audio exceeds Fish Audio's 60-minute limit"
        case "audio_too_short":
            return "The audio is too short to transcribe"
        case "upstream_unavailable":
            return "The transcription service is temporarily unavailable; retry later"
        case "upstream_timeout":
            return "The transcription service timed out; retry later"
        case "excessive_repetition":
            return "The transcription stopped because of excessive repetition; retry later"
        case "diarization_failed":
            return "Speaker diarization failed; retry later or turn diarization off"
        default:
            break
        }

        switch statusCode {
        case 400:
            return "The request was invalid"
        case 401:
            return "The API key is invalid"
        case 402:
            return "The account has no remaining credit"
        case 413:
            return "The audio file is too large; upload compressed audio such as MP3 or M4A"
        case 429:
            return "Too many concurrent requests; retry after an in-flight request finishes"
        case 500...599:
            return "Fish Audio had a server error; retry later"
        default:
            return "The request failed"
        }
    }

    /// The failure as a SpeechKit error.
    var speechError: SpeechError {
        var reason = summary
        if let message, !message.isEmpty {
            reason += ": \(message)"
        }
        var details = ["HTTP \(statusCode)"]
        if let code {
            details.append("code \(code)")
        }
        if let requestID {
            details.append("request \(requestID)")
        }
        reason += " (\(details.joined(separator: ", ")))."
        return .httpFailure(provider: .fishAudio, statusCode: statusCode)
    }
}

/// Maps a raw Fish Audio response onto plain text and timed words.
enum FishAudioTranscriptMapping {
    /// How many tokens ahead SpeechKit looks for a word after a mismatch.
    static let resyncWindow = 3

    /// Removes `<|speaker:N|>` markers and tidies the whitespace they leave behind.
    static func removingSpeakerMarkers(from text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"<\|speaker:[^|>]*\|>"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds speaker-labelled, punctuated words from segments and speaker turns.
    ///
    /// Each segment becomes one word with its timing unchanged. Its speaker is
    /// the turn containing its midpoint. Punctuation and capitalisation come
    /// from walking the punctuated turn text alongside the segments, matching
    /// tokens case-insensitively with punctuation removed. `[cue]` tags are
    /// skipped. When a token does not match, for example because Fish Audio
    /// normalised the segment text, the word keeps its segment text and the
    /// walk resyncs on a later match within ``resyncWindow`` tokens.
    ///
    /// When there are no speaker turns, the top-level text is used as the
    /// punctuated source instead.
    static func words(
        segments: [FishAudioTranscriptionSegment],
        speakerTurns: [FishAudioSpeakerTurn],
        fallbackText: String
    ) -> [FishAudioTranscriptWord] {
        guard !segments.isEmpty else { return [] }

        let punctuatedText = speakerTurns.isEmpty
            ? fallbackText
            : speakerTurns.map(\.text).joined(separator: " ")
        let tokens = punctuatedTokens(from: punctuatedText)

        var tokenIndex = 0
        return segments.map { segment in
            let speaker = speaker(for: segment, in: speakerTurns)
            let key = isCueTag(segment.text) ? "" : matchKey(segment.text)
            var text = segment.text

            if !key.isEmpty, tokenIndex < tokens.count {
                let lastCandidate = min(tokenIndex + resyncWindow, tokens.count - 1)
                if let match = (tokenIndex...lastCandidate).first(where: { tokens[$0].key == key }) {
                    text = tokens[match].text
                    tokenIndex = match + 1
                }
            }

            return FishAudioTranscriptWord(text: text, start: segment.start, end: segment.end, speaker: speaker)
        }
    }

    /// The speaker of the turn that contains the segment's midpoint.
    static func speaker(for segment: FishAudioTranscriptionSegment, in speakerTurns: [FishAudioSpeakerTurn]) -> String? {
        guard let start = segment.start, let end = segment.end else { return nil }
        let midpoint = (start + end) / 2
        let turn = speakerTurns.first { turn in
            guard let turnStart = turn.start, let turnEnd = turn.end else { return false }
            return turnStart <= midpoint && midpoint <= turnEnd
        }
        guard let speaker = turn?.speaker, !speaker.isEmpty else { return nil }
        return speaker
    }

    /// Splits punctuated text into tokens, dropping speaker markers, `[cue]` tags, and punctuation-only tokens.
    static func punctuatedTokens(from text: String) -> [(text: String, key: String)] {
        let withoutMarkers = text.replacingOccurrences(
            of: #"<\|speaker:[^|>]*\|>"#,
            with: " ",
            options: .regularExpression
        )
        let withoutCues = withoutMarkers.replacingOccurrences(
            of: #"\[[^\[\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        return withoutCues
            .split(whereSeparator: \.isWhitespace)
            .map { token in (text: String(token), key: matchKey(String(token))) }
            .filter { !$0.key.isEmpty }
    }

    /// A Boolean value that indicates whether the text is a single `[cue]` tag, such as `[laughter]`.
    static func isCueTag(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"^\[[^\[\]]*\]$"#, options: .regularExpression) != nil
    }

    /// The comparison key for a token: lowercased, with punctuation and symbols removed.
    static func matchKey(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.filter { scalar in
            !CharacterSet.punctuationCharacters.contains(scalar)
                && !CharacterSet.symbols.contains(scalar)
                && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
