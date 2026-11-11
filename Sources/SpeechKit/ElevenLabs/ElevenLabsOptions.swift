import Foundation

// MARK: - Shared value types

/// How Scribe v3 writes numbers in the transcript.
public enum ElevenLabsNumbersFormat: String, Sendable, CaseIterable {
    /// Numbers are written as digits, such as `42`.
    case digits
    /// Numbers are written as words, such as `forty-two`.
    case words
}

/// An entity category ElevenLabs can detect in a transcript.
public enum ElevenLabsEntityCategory: String, Sendable, CaseIterable {
    /// Personally identifiable information.
    case pii
    /// Protected health information.
    case phi
    /// Payment card information.
    case pci
    /// Entities that fit no other category.
    case other
    /// Offensive language.
    case offensiveLanguage = "offensive_language"
}

/// What ElevenLabs should detect in the transcript.
public enum ElevenLabsEntityDetection: Sendable, Equatable {
    /// Detect every entity type.
    case all
    /// Detect every entity in the listed categories.
    case categories([ElevenLabsEntityCategory])
    /// Detect the listed entity types, such as `name` or `location`.
    case types([String])

    /// The repeated `entity_detection` values these options produce.
    var parameterValues: [String] {
        switch self {
        case .all:
            return ["all"]
        case .categories(let categories):
            return categories.map(\.rawValue)
        case .types(let types):
            return types
        }
    }
}

/// How an ElevenLabs realtime session decides that a transcript segment is final.
///
/// ElevenLabs' own default is `manual`, which never commits on its own.
/// SpeechKit's default is ``automatic``, which resolves by model:
/// `turn_prediction` on Scribe v3 Live and `vad` on Scribe v2 Realtime.
public enum ElevenLabsCommitStrategy: Sendable, Equatable, CaseIterable {
    /// Resolve by model: turn prediction on Scribe v3 Live, VAD on other models.
    case automatic
    /// Segments commit only when you call ``ElevenLabsService/commitRealtimeSegment()``.
    case manual
    /// Segments commit after the configured silence.
    case vad
    /// Segments commit when the model's turn probability reaches its threshold.
    ///
    /// Scribe v3 Live only; other models reject it.
    case turnPrediction

    /// The `commit_strategy` query value for a model.
    func parameterValue(for modelID: ElevenLabsModelID) -> String {
        switch self {
        case .automatic:
            return modelID == .scribeV3Live ? "turn_prediction" : "vad"
        case .manual:
            return "manual"
        case .vad:
            return "vad"
        case .turnPrediction:
            return "turn_prediction"
        }
    }
}

// MARK: - File options

/// Options for an ElevenLabs file transcription request.
///
/// ``ElevenLabsConfiguration/fileOptions`` holds the defaults;
/// ``SpeechFileTranscriptionOptions/elevenLabs(modelID:language:secondaryLanguages:numbersFormat:diarize:speakerCount:diarizationThreshold:keyterms:tagAudioEvents:noVerbatim:entityDetection:timeoutInterval:)``
/// overrides them per request. ElevenLabs rejects unsupported combinations
/// with a vague `invalid_parameters`, so SpeechKit validates them before
/// uploading.
public struct ElevenLabsFileTranscriptionOptions: Sendable, Equatable {
    /// The Scribe model to use.
    public var modelID: ElevenLabsModelID
    /// An ISO 639-1 or 639-3 language code such as `"en"`, or `nil` to let ElevenLabs detect the language.
    public var language: String?
    /// Other languages expected in the audio. Scribe v3 only.
    public var secondaryLanguages: [String]
    /// How Scribe v3 writes numbers, or `nil` to let the model choose. Scribe v3 only.
    public var numbersFormat: ElevenLabsNumbersFormat?
    /// A Boolean value that indicates whether ElevenLabs should label each word with its speaker.
    public var diarize: Bool
    /// The maximum number of speakers, from 1 to 32, or `nil` for the model maximum.
    ///
    /// Requires ``diarize``.
    public var speakerCount: Int?
    /// How eagerly ElevenLabs splits speakers, normally around `0.22`.
    ///
    /// Higher values predict fewer speakers. Requires ``diarize`` and cannot
    /// be combined with ``speakerCount``.
    public var diarizationThreshold: Double?
    /// Terms that bias transcription toward the right spelling: up to 1,000
    /// terms of up to 50 characters and 5 words each.
    public var keyterms: [String]
    /// A Boolean value that indicates whether ElevenLabs should mark sounds such as laughter.
    ///
    /// They come back as ``ElevenLabsWordTimestamp`` values of type `audio_event`.
    public var tagAudioEvents: Bool
    /// A Boolean value that indicates whether ElevenLabs should remove filler words and false starts.
    public var noVerbatim: Bool
    /// The entities ElevenLabs should detect, returned as ``ElevenLabsFileTranscriptionResponse/entities``.
    public var entityDetection: ElevenLabsEntityDetection?
    /// The network timeout for the upload request.
    public var timeoutInterval: TimeInterval

    /// Creates ElevenLabs file transcription options.
    public init(
        modelID: ElevenLabsModelID = .scribeV3,
        language: String? = nil,
        secondaryLanguages: [String] = [],
        numbersFormat: ElevenLabsNumbersFormat? = nil,
        diarize: Bool = false,
        speakerCount: Int? = nil,
        diarizationThreshold: Double? = nil,
        keyterms: [String] = [],
        tagAudioEvents: Bool = false,
        noVerbatim: Bool = false,
        entityDetection: ElevenLabsEntityDetection? = nil,
        timeoutInterval: TimeInterval = 15 * 60
    ) {
        self.modelID = modelID
        self.language = language
        self.secondaryLanguages = secondaryLanguages
        self.numbersFormat = numbersFormat
        self.diarize = diarize
        self.speakerCount = speakerCount
        self.diarizationThreshold = diarizationThreshold
        self.keyterms = keyterms
        self.tagAudioEvents = tagAudioEvents
        self.noVerbatim = noVerbatim
        self.entityDetection = entityDetection
        self.timeoutInterval = timeoutInterval
    }

    /// The `entity_detection` form values these options produce.
    var entityDetectionValues: [String] {
        entityDetection?.parameterValues ?? []
    }

    func validate() throws {
        guard modelID.supportsFileTranscription else {
            throw ElevenLabsError.unsupportedModel(.invalidOptions)
        }
        try ElevenLabsValidation.validateFileOptions(self)
    }
}

// MARK: - Realtime options

/// Options for an ElevenLabs realtime transcription session.
///
/// SpeechKit sends these values as query parameters when it opens the
/// WebSocket, so changes apply to the next session. ElevenLabs closes the
/// connection on an unsupported combination, so SpeechKit validates them
/// before connecting. ``ElevenLabsConfiguration/realtimeOptions`` holds the
/// defaults.
public struct ElevenLabsRealtimeOptions: Sendable, Equatable {
    /// An ISO 639-1 or 639-3 language code, or `nil` to let ElevenLabs detect the language.
    public var language: String?
    /// Other languages detection is limited to. Repeated as `secondary_languages`.
    public var secondaryLanguages: [String]
    /// A Boolean value that indicates whether Scribe v3 Live follows language switches mid-sentence.
    ///
    /// Scribe v3 Live only. Multilingual mode can pick up background speech,
    /// and short phrases are more often wrong.
    public var multilingual: Bool
    /// How the session decides that a transcript segment is final.
    ///
    /// The default ``ElevenLabsCommitStrategy/automatic`` resolves to turn
    /// prediction on Scribe v3 Live and VAD on Scribe v2 Realtime.
    public var commitStrategy: ElevenLabsCommitStrategy
    /// The silence that ends a VAD segment, in seconds, from 0.192 to 3.0. `nil` keeps ElevenLabs' default.
    public var vadSilenceThresholdSeconds: Double?
    /// The VAD activation threshold. `nil` keeps ElevenLabs' default.
    public var vadThreshold: Double?
    /// The minimum speech that opens a VAD segment, in milliseconds. `nil` keeps ElevenLabs' default.
    public var minSpeechDurationMilliseconds: Int?
    /// The minimum silence that ends a VAD segment, in milliseconds. `nil` keeps ElevenLabs' default.
    public var minSilenceDurationMilliseconds: Int?
    /// A Boolean value that indicates whether Scribe v3 Live should label words with their speaker.
    ///
    /// Scribe v3 Live only. Each commit is followed by a `diarized_transcript`
    /// message that SpeechKit resolves into speaker-labelled entries.
    public var diarize: Bool
    /// Terms that bias recognition: up to 50 terms of up to 20 characters each.
    public var keyterms: [String]
    /// The session's keyterm library: up to 10,000 terms of up to 50 characters each, 2 MB in total.
    ///
    /// Scribe v3 Live only. Sent inside the first audio message.
    public var keytermLibrary: [String]
    /// A Boolean value that indicates whether committed transcripts carry word timestamps.
    public var includeTimestamps: Bool
    /// A Boolean value that indicates whether committed transcripts carry the detected language.
    public var includeLanguageDetection: Bool
    /// A Boolean value that indicates whether ElevenLabs should remove filler words and false starts.
    public var noVerbatim: Bool
    /// The entities ElevenLabs should detect, delivered as `committed_transcript_entities` messages.
    public var entityDetection: ElevenLabsEntityDetection?
    /// Transcript context sent in the first audio message, or `nil`.
    public var previousText: String?

    /// Creates ElevenLabs realtime session options.
    public init(
        language: String? = nil,
        secondaryLanguages: [String] = [],
        multilingual: Bool = false,
        commitStrategy: ElevenLabsCommitStrategy = .automatic,
        vadSilenceThresholdSeconds: Double? = nil,
        vadThreshold: Double? = nil,
        minSpeechDurationMilliseconds: Int? = nil,
        minSilenceDurationMilliseconds: Int? = nil,
        diarize: Bool = false,
        keyterms: [String] = [],
        keytermLibrary: [String] = [],
        includeTimestamps: Bool = false,
        includeLanguageDetection: Bool = false,
        noVerbatim: Bool = false,
        entityDetection: ElevenLabsEntityDetection? = nil,
        previousText: String? = nil
    ) {
        self.language = language
        self.secondaryLanguages = secondaryLanguages
        self.multilingual = multilingual
        self.commitStrategy = commitStrategy
        self.vadSilenceThresholdSeconds = vadSilenceThresholdSeconds
        self.vadThreshold = vadThreshold
        self.minSpeechDurationMilliseconds = minSpeechDurationMilliseconds
        self.minSilenceDurationMilliseconds = minSilenceDurationMilliseconds
        self.diarize = diarize
        self.keyterms = keyterms
        self.keytermLibrary = keytermLibrary
        self.includeTimestamps = includeTimestamps
        self.includeLanguageDetection = includeLanguageDetection
        self.noVerbatim = noVerbatim
        self.entityDetection = entityDetection
        self.previousText = previousText
    }

    /// The `entity_detection` query values these options produce.
    var entityDetectionValues: [String] {
        entityDetection?.parameterValues ?? []
    }

    /// The resolved `commit_strategy` value for a model.
    func commitStrategyParameter(for modelID: ElevenLabsModelID) -> String {
        commitStrategy.parameterValue(for: modelID)
    }

    /// A Boolean value that indicates whether the session accepts manual commits for a model.
    func allowsManualCommits(for modelID: ElevenLabsModelID) -> Bool {
        commitStrategyParameter(for: modelID) == "manual"
    }

    func validate(modelID: ElevenLabsModelID) throws {
        guard modelID.supportsRealtime else {
            throw ElevenLabsError.unsupportedModel(.invalidOptions)
        }
        try ElevenLabsValidation.validateRealtimeOptions(self, modelID: modelID)
    }
}

// MARK: - Validation

/// Validation shared by ElevenLabs file and realtime requests.
enum ElevenLabsValidation {
    /// The most file `keyterms` ElevenLabs accepts.
    static let maximumFileKeytermCount = 1000
    /// The longest file `keyterm` ElevenLabs accepts, in characters.
    static let maximumFileKeytermLength = 50
    /// The most words one file `keyterm` may hold.
    static let maximumFileKeytermWords = 5
    /// The most realtime `keyterms` ElevenLabs accepts.
    static let maximumRealtimeKeytermCount = 50
    /// The longest realtime `keyterm` ElevenLabs accepts, in characters.
    static let maximumRealtimeKeytermLength = 20
    /// The most terms a realtime `keyterm_library` holds.
    static let maximumKeytermLibraryCount = 10_000
    /// The longest `keyterm_library` term, in characters.
    static let maximumKeytermLibraryTermLength = 50
    /// The largest `keyterm_library`, in UTF-8 bytes.
    static let maximumKeytermLibraryBytes = 2 * 1024 * 1024
    /// The `num_speakers` range ElevenLabs accepts.
    static let speakerCountRange = 1...32
    /// The `vad_silence_threshold_secs` range ElevenLabs accepts.
    static let vadSilenceThresholdRange = 0.192...3.0
    /// The characters ElevenLabs forbids inside a keyterm.
    static let forbiddenKeytermCharacters = CharacterSet(charactersIn: "<>{}[]\\")

    private static func invalidOptions() -> SpeechError {
        SpeechError.providerFailure(provider: .elevenLabs, reason: .invalidOptions)
    }

    /// Rejects a language code that is not a two- or three-letter ISO 639 code.
    static func validateLanguageCode(_ code: String?) throws {
        guard let code else { return }
        let valid = (2...3).contains(code.count) && code.allSatisfy { $0.isASCII && $0.isLetter }
        guard valid else { throw invalidOptions() }
    }

    /// Rejects keyterms over the count, length, word count, or character limits.
    static func validateKeyterms(_ keyterms: [String], maximumCount: Int, maximumLength: Int) throws {
        if keyterms.count > maximumCount { throw invalidOptions() }
        for term in keyterms {
            if term.isEmpty || term.count > maximumLength { throw invalidOptions() }
            if term.split(whereSeparator: \.isWhitespace).count > maximumFileKeytermWords {
                throw invalidOptions()
            }
            if term.rangeOfCharacter(from: forbiddenKeytermCharacters) != nil {
                throw invalidOptions()
            }
        }
    }

    /// Rejects a `keyterm_library` over the term, length, or total size limits.
    static func validateKeytermLibrary(_ keytermLibrary: [String]) throws {
        if keytermLibrary.count > maximumKeytermLibraryCount { throw invalidOptions() }
        var totalBytes = 0
        for term in keytermLibrary {
            if term.isEmpty || term.count > maximumKeytermLibraryTermLength { throw invalidOptions() }
            totalBytes += term.utf8.count
        }
        if totalBytes > maximumKeytermLibraryBytes { throw invalidOptions() }
    }

    /// The Decision 4 checks for a file transcription request.
    static func validateFileOptions(_ options: ElevenLabsFileTranscriptionOptions) throws {
        if options.modelID != .scribeV3,
           options.numbersFormat != nil || !options.secondaryLanguages.isEmpty {
            throw invalidOptions()
        }
        try validateLanguageCode(options.language)
        for code in options.secondaryLanguages {
            try validateLanguageCode(code)
        }
        if let threshold = options.diarizationThreshold {
            if !options.diarize || options.speakerCount != nil || !(0.0...1.0).contains(threshold) {
                throw invalidOptions()
            }
        }
        if let speakerCount = options.speakerCount {
            if !options.diarize || !speakerCountRange.contains(speakerCount) {
                throw invalidOptions()
            }
        }
        try validateKeyterms(
            options.keyterms,
            maximumCount: maximumFileKeytermCount,
            maximumLength: maximumFileKeytermLength
        )
        if options.timeoutInterval <= 0 { throw invalidOptions() }
    }

    /// The Decision 4 checks for a realtime session.
    static func validateRealtimeOptions(_ options: ElevenLabsRealtimeOptions, modelID: ElevenLabsModelID) throws {
        if modelID != .scribeV3Live,
           options.diarize || options.multilingual || options.commitStrategy == .turnPrediction
                || !options.keytermLibrary.isEmpty {
            throw invalidOptions()
        }
        try validateLanguageCode(options.language)
        for code in options.secondaryLanguages {
            try validateLanguageCode(code)
        }
        if let threshold = options.vadSilenceThresholdSeconds, !vadSilenceThresholdRange.contains(threshold) {
            throw invalidOptions()
        }
        if let threshold = options.vadThreshold, threshold < 0 {
            throw invalidOptions()
        }
        if let milliseconds = options.minSpeechDurationMilliseconds, milliseconds < 0 {
            throw invalidOptions()
        }
        if let milliseconds = options.minSilenceDurationMilliseconds, milliseconds < 0 {
            throw invalidOptions()
        }
        try validateKeyterms(
            options.keyterms,
            maximumCount: maximumRealtimeKeytermCount,
            maximumLength: maximumRealtimeKeytermLength
        )
        try validateKeytermLibrary(options.keytermLibrary)
    }
}
