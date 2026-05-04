# ``SpeechKit``

Add realtime speech-to-text and audio file transcription to Swift and SwiftUI apps.

## Overview

SpeechKit provides one observable service, ``SpeechService``, for realtime microphone transcription and provider-backed audio file transcription. Realtime transcription uses ElevenLabs Scribe realtime models. File transcription supports ElevenLabs, Aqua, Cohere, and Grok.

Create a service with the provider configurations your app needs, then place it in SwiftUI's environment or keep it in your own model layer.

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

## Topics

### Essentials

- <doc:GettingStarted>
- ``SpeechService``

### Realtime Transcription

- <doc:RealtimeTranscription>
- ``ElevenLabsService``
- ``ElevenLabsConfig``
- ``ElevenLabsModelID``

### File Transcription

- <doc:FileTranscription>
- <doc:ProviderConfiguration>
- <doc:SecurityScopedFiles>
- ``SpeechFileProvider``
- ``SpeechFileTranscriptionOptions``
- ``SpeechError``

### ElevenLabs

- ``ElevenLabsService/ConnectionState``
- ``ElevenLabsService/TranscriptEntry``
- ``ElevenLabsService/FileTranscriptionResponse``
- ``WordTimestamp``
- ``ElevenLabsError``

### Aqua

- ``AquaConfig``
- ``AquaModelID``
- ``AquaLanguage``
- ``AquaFileTranscriptionOptions``
- ``AquaFileTranscriptionResponse``

### Cohere

- ``CohereConfig``
- ``CohereModelID``
- ``CohereLanguage``

### Grok

- ``GrokConfig``
- ``GrokModelID``
- ``GrokLanguage``
- ``GrokAudioFormat``
- ``GrokTimestampGranularity``
- ``GrokFileTranscriptionOptions``
- ``GrokFileTranscriptionResponse``
- ``GrokWordTimestamp``
- ``GrokTranscriptionChannel``
