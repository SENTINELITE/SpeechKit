import SwiftUI

private struct SpeechServiceKey: EnvironmentKey {
    static var defaultValue: SpeechService {
        MainActor.assumeIsolated { SpeechService() }
    }
}

extension EnvironmentValues {
    public var speechService: SpeechService {
        get { self[SpeechServiceKey.self] }
        set { self[SpeechServiceKey.self] = newValue }
    }
}
