import Foundation
import SpeechKit
import SwiftUI
import Testing

@Suite("Public transcription capability API")
@MainActor
struct SpeechTranscriptionPublicAPITests {
    @Test func capabilityAndAccountNamespaceArePublic() {
        let relay = SpeechRelay(url: URL(string: "https://relay.example")!, appAttestAccountID: "synthetic-account")
        let service = SpeechService(relay: relay)
        let transcriber: SpeechTranscription = service.transcriber
        #expect(relay.appAttestAccountID == "synthetic-account")
        #expect(transcriber.transcriptText.isEmpty)
        _ = Text(transcriber.transcriptText).environment(\.speechTranscriber, transcriber)
        let reset: @Sendable () async throws -> Void = { try await relay.resetAppAttestKey() }
        _ = reset
    }
}
