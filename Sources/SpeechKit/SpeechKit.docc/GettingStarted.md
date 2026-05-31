# Getting Started

Configure ``SpeechService`` with the providers your app uses.

## Overview

SpeechKit uses Swift concurrency for all network work and SwiftUI observation for realtime transcript state. Most apps create one ``SpeechService`` and share it through SwiftUI's environment.

```swift
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        elevenLabs: ElevenLabsConfiguration(apiKey: "<ELEVENLABS_API_KEY>"),
        cohere: CohereConfiguration(apiKey: "<COHERE_API_KEY>")
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
        }
    }
}
```

Inside a view, read the service from SwiftUI's `speechService` environment value.

```swift
struct ContentView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        Text(speech.transcriptText)
    }
}
```

Apps that use realtime microphone transcription must include the platform's microphone permission usage description in their app target.

## Topics

### Next Steps

- <doc:RealtimeTranscription>
- <doc:FileTranscription>
- <doc:ProviderConfiguration>
