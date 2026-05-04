# SpeechKit

SpeechKit is a Swift package for adding speech-to-text to Swift and SwiftUI apps with a small async/await API.

It supports realtime microphone transcription through ElevenLabs and file transcription through ElevenLabs, Aqua, Cohere, and Grok.

## Requirements

- Swift 6.2+
- iOS 18+
- macOS 15+
- watchOS 11+
- visionOS 2+

Apps that use realtime microphone transcription must include the platform's microphone permission usage description in their app target.

## Installation

Add SpeechKit as a Swift Package dependency in Xcode:

1. Open your app project.
2. Select `File > Add Package Dependencies...`.
3. Enter the SpeechKit package URL.
4. Add the `SpeechKit` library to your app target.

Then import it where you need speech features:

```swift
import SpeechKit
```

## Quick Start

Create one `SpeechService` and put it in SwiftUI's environment.

```swift
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        elevenLabs: ElevenLabsConfig(apiKey: "<ELEVENLABS_API_KEY>")
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
        }
    }
}
```

## Realtime Transcription

Use `startListening()` and `stopListening()` from a Swift concurrency task. The service exposes both partial and committed transcript text.

```swift
import SpeechKit
import SwiftUI

struct ContentView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(speech.fullTranscript)

            if !speech.partialTranscript.isEmpty {
                Text(speech.partialTranscript)
                    .foregroundStyle(.secondary)
            }

            Button(speech.connectionState.isListening ? "Stop" : "Start") {
                Task {
                    if speech.connectionState.isActive {
                        await speech.stopListening()
                    } else {
                        await speech.startListening()
                    }
                }
            }
        }
        .padding()
    }
}
```

For an even smaller example, start listening when a view appears:

```swift
struct TranscriptView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        ScrollView {
            Text(speech.fullTranscript)
        }
        .task {
            await speech.startListening()
        }
    }
}
```

## File Transcription

Configure the provider you want to use, then call `transcribeAudioFile(provider:file:)`.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfig(apiKey: "<ELEVENLABS_API_KEY>")
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL
)
```

Use a different provider by configuring it on the same service.

```swift
let speech = SpeechService(
    aqua: AquaConfig(apiKey: "<AQUA_API_KEY>"),
    cohere: CohereConfig(apiKey: "<COHERE_API_KEY>"),
    grok: GrokConfig(apiKey: "<XAI_API_KEY>")
)

let aquaText = try await speech.transcribeAudioFile(provider: .aqua, file: audioFileURL)
let cohereText = try await speech.transcribeAudioFile(provider: .cohere, file: audioFileURL)
let grokText = try await speech.transcribeAudioFile(provider: .grok, file: audioFileURL)
```

Provider-specific options are available when you need them:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL,
    options: .cohere(language: .english, temperature: 0.2)
)
```

For providers that return richer metadata, use the detailed helpers:

```swift
let response = try await speech.transcribeGrokAudioFile(file: audioFileURL)
print(response.text)
print(response.words ?? [])
```

## Security-Scoped Files

If your app receives a security-scoped file URL from a document picker, use the matching `securityScopedURL` overload:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    securityScopedURL: pickedURL
)
```

## Models and Providers

Realtime transcription currently uses ElevenLabs Scribe realtime models.

File transcription supports:

- ElevenLabs Scribe V1 and V2
- Aqua Avalon v1.5
- Cohere Transcribe
- Grok STT

Provider defaults are configured through `ElevenLabsConfig`, `AquaConfig`, `CohereConfig`, and `GrokConfig`.

## FAQ

### Does SpeechKit use async/await?

Yes. Starting and stopping realtime transcription is async, and all file transcription APIs use async/await.

### Does SpeechKit work with SwiftUI?

Yes. `SpeechService` is observable and can be placed in SwiftUI's environment with `environment(\.speechService, speech)`.

### Which Apple platforms are supported?

SpeechKit supports iOS, macOS, watchOS, and visionOS.

### Do I need all provider API keys?

No. Configure only the providers your app uses. For realtime transcription, configure ElevenLabs.

### How do I configure ElevenLabs?

Use `ElevenLabsConfig` with the main `SpeechService` initializer:

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfig(apiKey: "<ELEVENLABS_API_KEY>")
)
```
