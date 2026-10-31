import Foundation
import SpeechKit
import SwiftUI
import Testing

@Suite("speechKit view modifier")
@MainActor
struct SpeechKitViewModifierTests {
    @MainActor
    final class Probe {
        var services: [SpeechService] = []
        var transcribers: [SpeechTranscription] = []
    }

    struct Reader: View {
        let probe: Probe
        @Environment(\.speechService) private var service
        @Environment(\.speechTranscriber) private var transcriber

        var body: some View {
            probe.services.append(service)
            probe.transcribers.append(transcriber)
            return Color.clear.frame(width: 1, height: 1)
        }
    }

    @Test func relayModifierInjectsRelayService() throws {
        let probe = Probe()
        let relay = SpeechRelay(url: URL(string: "https://relay.example")!, optimizedUploads: .off)
        _ = ImageRenderer(content: Reader(probe: probe).speechKit(relay: relay)).cgImage
        let service = try #require(probe.services.last)
        #expect(service.relay?.url == relay.url)
        #expect(service.relay?.optimizedUploads == .off)
        #expect(!probe.transcribers.isEmpty)
    }

    @Test func directModifierInjectsProviderConfiguration() throws {
        let probe = Probe()
        _ = ImageRenderer(content: Reader(probe: probe)
            .speechKit(openAI: OpenAIConfiguration(credential: .apiKey("synthetic-key")))).cgImage
        let service = try #require(probe.services.last)
        #expect(service.openAI?.hasCredential == true)
        #expect(service.relay == nil)
    }

    @Test func existingServiceModifierInjectsThatInstance() {
        let probe = Probe()
        let service = SpeechService()
        _ = ImageRenderer(content: Reader(probe: probe).speechKit(service)).cgImage
        #expect(probe.services.last === service)
    }
}
