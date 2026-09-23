import Foundation

/// A provider that can hold a full-duplex speech-to-speech conversation.
///
/// A conversation provider both listens to microphone audio and speaks back,
/// which is different from ``SpeechRealtimeProvider``, where the provider only
/// transcribes what it hears.
public enum SpeechConversationProvider: String, Sendable, CaseIterable {
    /// OpenAI GPT-Live speech-to-speech conversations.
    case openAI
}

/// The conversation lifecycle state.
public enum SpeechConversationState: Equatable, Sendable {
    /// The service has no conversation session.
    case idle
    /// The service is opening a conversation session.
    case connecting
    /// The service has an active conversation session.
    case active(sessionID: String)
    /// The service is closing a conversation session.
    case ending
    /// The session ended, carrying the provider reason and the final billed seconds when known.
    case ended(reason: SpeechConversationEndReason, seconds: Double?)
    /// The session stopped because of an error.
    case error(String)

    /// A Boolean value that indicates whether the service has an active conversation session.
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// A Boolean value that indicates whether the service is connecting, active, or ending.
    public var isLifecycleActive: Bool {
        switch self {
        case .connecting, .active, .ending:
            return true
        case .idle, .ended, .error:
            return false
        }
    }
}

/// The reason a conversation session ended.
public enum SpeechConversationEndReason: String, Sendable, Equatable {
    /// The client asked the provider to close the session.
    case closeRequested = "close_requested"
    /// The session reached its maximum duration.
    case expired
    /// The provider closed the session because of its content policy.
    case content
    /// The remote participant hung up.
    case remoteHangup = "remote_hangup"
    /// The transport dropped.
    case connectionLost = "connection_lost"
    /// The provider sent a reason SpeechKit does not recognize.
    case unknown

    /// Creates an end reason from a provider string, mapping unrecognized values to ``unknown``.
    ///
    /// - Parameter providerRawValue: The raw `reason` string sent by the provider.
    public init(providerRawValue: String) {
        self = SpeechConversationEndReason(rawValue: providerRawValue) ?? .unknown
    }
}

extension SpeechConversationEndReason: CustomStringConvertible {
    /// A short sentence suitable for status text.
    public var description: String {
        switch self {
        case .closeRequested:
            return "The conversation was ended by the app."
        case .expired:
            return "The conversation reached its maximum duration."
        case .content:
            return "The provider ended the conversation because of its content policy."
        case .remoteHangup:
            return "The remote participant hung up."
        case .connectionLost:
            return "The connection was lost."
        case .unknown:
            return "The conversation ended for an unknown reason."
        }
    }
}

/// The speaker that produced a conversation transcript entry.
public enum SpeechConversationRole: String, Sendable {
    /// The person talking into the microphone.
    case user
    /// The model talking back.
    case assistant
}

/// A normalized speech-to-speech transcript entry.
///
/// Conversation providers send transcript fragments rather than finished turns,
/// so SpeechKit groups fragments into entries and keeps the newest entry of each
/// role open while more fragments can still land in it.
public struct SpeechConversationTranscriptEntry: Identifiable, Equatable, Sendable {
    /// The stable identity of the entry.
    public let id: UUID
    /// The provider that produced the entry.
    public let provider: SpeechConversationProvider
    /// The speaker that produced the entry.
    public let role: SpeechConversationRole
    /// The raw concatenated fragments, including the provider's own leading spaces and punctuation.
    public internal(set) var text: String
    /// The entry start time on the session timeline, in milliseconds.
    public let startMilliseconds: Int
    /// The entry end time on the session timeline, in milliseconds.
    public internal(set) var endMilliseconds: Int
    /// The time when SpeechKit created the entry.
    public let timestamp: Date
    /// A Boolean value that indicates whether the entry can still receive fragments.
    public internal(set) var isOpen: Bool

    /// The entry text trimmed for display.
    public var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Creates a speech-to-speech transcript entry.
    public init(
        id: UUID = UUID(),
        provider: SpeechConversationProvider = .openAI,
        role: SpeechConversationRole,
        text: String,
        startMilliseconds: Int = 0,
        endMilliseconds: Int = 0,
        timestamp: Date = Date(),
        isOpen: Bool = true
    ) {
        self.id = id
        self.provider = provider
        self.role = role
        self.text = text
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.timestamp = timestamp
        self.isOpen = isOpen
    }
}

/// Errors returned by the speech-to-speech conversation layer.
public enum SpeechConversationError: Error, LocalizedError, Sendable, Equatable {
    /// The conversation provider has no usable credential.
    case providerNotConfigured(SpeechConversationProvider)
    /// A realtime transcription session already owns the microphone.
    case microphoneBusy
    /// A conversation session already owns the microphone.
    case transcriptionBusy
    /// The requested operation needs an active conversation session.
    case notActive
    /// The provider rejected a client event.
    case commandRejected(code: String?, message: String)

    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let provider):
            return "\(provider.rawValue) is not configured for conversations"
        case .microphoneBusy:
            return "A realtime transcription session is already using the microphone"
        case .transcriptionBusy:
            return "A conversation session is already using the microphone"
        case .notActive:
            return "No active conversation session"
        case .commandRejected(let code, let message):
            guard let code else { return message }
            return "\(message) (\(code))"
        }
    }
}

/// Groups conversation transcript fragments into interleaved per-role entries.
///
/// GPT-Live reports every fragment with a `[start, end)` window on the session
/// timeline, and fragments from the two speakers can overlap. A fragment extends
/// the newest open entry of the same role when its start is within
/// ``turnGapMilliseconds`` of that entry's end; otherwise it opens a new entry.
/// Fragments of the other role never close an open entry, so an interruption
/// leaves both rows growing.
struct SpeechConversationTranscriptAssembler: Sendable, Equatable {
    /// The largest silence, in milliseconds, that still continues the same entry.
    var turnGapMilliseconds: Int

    /// The grouped entries, oldest first.
    private(set) var entries: [SpeechConversationTranscriptEntry] = []

    /// Creates a transcript assembler.
    ///
    /// - Parameter turnGapMilliseconds: The largest silence that still continues the same entry.
    init(turnGapMilliseconds: Int = 1200) {
        self.turnGapMilliseconds = turnGapMilliseconds
    }

    /// Adds a transcript fragment and returns the updated entries.
    ///
    /// - Parameters:
    ///   - role: The speaker that produced the fragment.
    ///   - delta: The raw fragment text, appended without a separator.
    ///   - startMilliseconds: The fragment start on the session timeline.
    ///   - endMilliseconds: The fragment end on the session timeline.
    ///   - provider: The conversation provider that produced the fragment.
    /// - Returns: The grouped entries after adding the fragment.
    @discardableResult
    mutating func append(
        role: SpeechConversationRole,
        delta: String,
        startMilliseconds: Int,
        endMilliseconds: Int,
        provider: SpeechConversationProvider = .openAI
    ) -> [SpeechConversationTranscriptEntry] {
        if let index = newestIndex(for: role),
           entries[index].isOpen,
           startMilliseconds - entries[index].endMilliseconds <= turnGapMilliseconds {
            entries[index].text += delta
            entries[index].endMilliseconds = max(entries[index].endMilliseconds, endMilliseconds)
            return entries
        }

        if let index = newestIndex(for: role) {
            entries[index].isOpen = false
        }

        entries.append(
            SpeechConversationTranscriptEntry(
                provider: provider,
                role: role,
                text: delta,
                startMilliseconds: startMilliseconds,
                endMilliseconds: endMilliseconds
            )
        )
        return entries
    }

    /// The trimmed text of the newest open entry for a role, or an empty string when none is open.
    ///
    /// - Parameter role: The speaker to read.
    /// - Returns: The in-progress text for that speaker.
    func partialText(for role: SpeechConversationRole) -> String {
        guard let index = newestIndex(for: role), entries[index].isOpen else { return "" }
        return entries[index].displayText
    }

    /// Closes every open entry, so later fragments start fresh entries.
    mutating func closeOpenEntries() {
        for index in entries.indices where entries[index].isOpen {
            entries[index].isOpen = false
        }
    }

    /// Removes every entry.
    mutating func reset() {
        entries.removeAll()
    }

    private func newestIndex(for role: SpeechConversationRole) -> Int? {
        entries.lastIndex { $0.role == role }
    }
}
