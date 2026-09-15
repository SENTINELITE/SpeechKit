import Foundation
import Testing
@testable import SpeechKit

@Suite("SpeechService Extension Storage")
struct SpeechServiceExtensionStorageTests {
    private struct Attachment: Equatable, Sendable {
        var name: String
    }

    private static var attachmentKey: SpeechServiceExtensionKey<Attachment> {
        SpeechServiceExtensionKey("com.sentinelite.SpeechKitTests.attachment")
    }

    private static var counterKey: SpeechServiceExtensionKey<Int> {
        SpeechServiceExtensionKey("com.sentinelite.SpeechKitTests.counter")
    }

    @Test("an extension value round trips and clears when assigned nil")
    @MainActor
    func extensionValueRoundTripsAndClears() {
        let service = SpeechService()
        let key = Self.attachmentKey

        #expect(service[extension: key] == nil)

        service[extension: key] = Attachment(name: "voz")
        #expect(service[extension: key] == Attachment(name: "voz"))

        service[extension: key] = Attachment(name: "replaced")
        #expect(service[extension: key] == Attachment(name: "replaced"))

        service[extension: key] = nil
        #expect(service[extension: key] == nil)
    }

    @Test("reading a key with a mismatched value type returns nil and preserves the stored value")
    @MainActor
    func mismatchedValueTypeReturnsNil() {
        let service = SpeechService()
        service[extension: Self.counterKey] = 7

        let mismatched = SpeechServiceExtensionKey<String>("com.sentinelite.SpeechKitTests.counter")
        #expect(service[extension: mismatched] == nil)
        #expect(service[extension: Self.counterKey] == 7)

        let unrelated = SpeechServiceExtensionKey<Int>("com.sentinelite.SpeechKitTests.unrelated")
        #expect(service[extension: unrelated] == nil)
        #expect(Self.counterKey == SpeechServiceExtensionKey<Int>("com.sentinelite.SpeechKitTests.counter"))
        #expect(Self.counterKey != unrelated)
    }
}
