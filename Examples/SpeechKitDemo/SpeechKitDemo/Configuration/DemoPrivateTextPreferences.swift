import Foundation

/// Keys written by older demo versions. Never restore this text into a new session.
enum DemoPrivateTextPreferences {
    static let keys = [
        "openAIPrompt", "openAIKeywords", "metaKeywords", "geminiCustomVocabulary",
        "mistralContextBias", "fishAudioRealtimeTerms", "appleContextualStrings"
    ]
    static func clearSavedValues(in defaults: UserDefaults) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
