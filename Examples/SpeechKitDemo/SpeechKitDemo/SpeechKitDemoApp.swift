import SpeechKit
import SwiftUI

/// The demo app entry point that owns the shared `SpeechService` for all sample workflows.
@main
struct SpeechKitDemoApp: App {
    @State private var speech = SpeechService()

    /// Creates the main window and injects SpeechKit into SwiftUI environment values.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
        }
    }
}
