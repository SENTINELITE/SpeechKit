import Foundation

protocol SpeechRedactedDiagnostics: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {}

extension SpeechRedactedDiagnostics {
    nonisolated public var description: String { "\(String(describing: Self.self))(<redacted>)" }
    nonisolated public var debugDescription: String { description }
    nonisolated public var customMirror: Mirror { Mirror(self, children: [:]) }
}

extension SpeechCredential: SpeechRedactedDiagnostics {}
extension SpeechResolvedCredential: SpeechRedactedDiagnostics {}
extension MetaHandshakeMessage: SpeechRedactedDiagnostics {}
extension MetaHandshakeMessage.Authorization: SpeechRedactedDiagnostics {}
extension ElevenLabsConfiguration: SpeechRedactedDiagnostics {}
extension CohereConfiguration: SpeechRedactedDiagnostics {}
extension GrokConfiguration: SpeechRedactedDiagnostics {}
extension AquaConfiguration: SpeechRedactedDiagnostics {}
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AppleSpeechConfiguration: SpeechRedactedDiagnostics {}
extension OpenAIConfiguration: SpeechRedactedDiagnostics {}
extension MetaConfiguration: SpeechRedactedDiagnostics {}
extension GeminiConfiguration: SpeechRedactedDiagnostics {}
extension MistralConfiguration: SpeechRedactedDiagnostics {}
extension FishAudioConfiguration: SpeechRedactedDiagnostics {}
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
extension AppleSpeechFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension CohereFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension FishAudioFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension FishAudioRealtimeService: SpeechRedactedDiagnostics {}
extension GeminiRealtimeService: SpeechRedactedDiagnostics {}
extension GeminiFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension GeminiFilesClient: SpeechRedactedDiagnostics {}
extension MetaRealtimeService: SpeechRedactedDiagnostics {}
extension MetaFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension GrokRealtimeService: SpeechRedactedDiagnostics {}
extension GrokFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension ElevenLabsFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension AquaFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension MistralFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension MistralRealtimeService: SpeechRedactedDiagnostics {}
extension OpenAIFileTranscriptionClient: SpeechRedactedDiagnostics {}
extension OpenAIRealtimeService: SpeechRedactedDiagnostics {}
extension SpeechService: SpeechRedactedDiagnostics {}
extension ElevenLabsService: SpeechRedactedDiagnostics {}
