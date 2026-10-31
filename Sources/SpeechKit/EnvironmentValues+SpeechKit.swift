import SwiftUI

private struct SpeechServiceKey: EnvironmentKey {
    static var defaultValue: SpeechService {
        MainActor.assumeIsolated { SpeechService() }
    }
}

private struct SpeechTranscriptionKey: EnvironmentKey {
    static let defaultValue: SpeechTranscription? = nil
}

extension EnvironmentValues {
    /// A transcription-only capability. Defaults to the existing environment service's capability.
    /// Inject only this value to keep the configured service out of a view's environment.
    @MainActor
    public var speechTranscriber: SpeechTranscription {
        get { self[SpeechTranscriptionKey.self] ?? speechService.transcriber }
        set { self[SpeechTranscriptionKey.self] = newValue }
    }

    /// The speech service available to SwiftUI views in the environment.
    public var speechService: SpeechService {
        get { self[SpeechServiceKey.self] }
        set { self[SpeechServiceKey.self] = newValue }
    }
}
