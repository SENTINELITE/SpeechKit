# ``SpeechKit``

Add realtime speech-to-text and audio file transcription to Swift and SwiftUI apps.

## Overview

SpeechKit provides one observable service, ``SpeechService``, for realtime microphone transcription and provider-backed audio file transcription. Realtime transcription supports ElevenLabs, OpenAI, xAI Grok, Meta, Gemini, and Apple local Speech on supported OS versions. File transcription supports ElevenLabs, Aqua, Cohere, Grok, OpenAI, Meta, Gemini, and Apple local Speech on supported OS versions.

Create a service with the provider configurations your app needs, then place it in SwiftUI's environment or keep it in your own model layer. Use ``SpeechService`` as the main app-facing facade; provider-specific realtime services are advanced APIs for direct provider integrations.

```swift
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        elevenLabs: ElevenLabsConfiguration(apiKey: "<ELEVENLABS_API_KEY>")
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
- <doc:ProviderHowToGuides>
- <doc:AppleLocalSpeech>
- ``SpeechService``
- ``SpeechCredential``
- ``SpeechTokenProvider``
- ``SpeechServiceExtensionKey``
- ``SpeechService/subscript(extension:)``

### Realtime Transcription

- <doc:RealtimeTranscription>
- ``ElevenLabsService``
- ``ElevenLabsConfiguration``
- ``ElevenLabsModelID``

### File Transcription

- <doc:FileTranscription>
- <doc:ProviderConfiguration>
- <doc:SecurityScopedFiles>
- ``SpeechFileTranscriptionProvider``
- ``SpeechFileTranscriptionOptions``
- ``SpeechError``

### ElevenLabs

- ``ElevenLabsService/ConnectionState``
- ``ElevenLabsService/TranscriptEntry``
- ``ElevenLabsWordTimestamp``
- ``ElevenLabsFileTranscriptionResponse``
- ``ElevenLabsError``

### Shared Realtime

- ``SpeechRealtimeProvider``
- ``SpeechRealtimeConnectionState``
- ``SpeechTranscriptEntry``
- ``SpeechTranscriptWord``

### Aqua

- ``AquaConfiguration``
- ``AquaModelID``
- ``AquaLanguage``
- ``AquaFileTranscriptionOptions``
- ``AquaFileTranscriptionResponse``

### Cohere

- ``CohereConfiguration``
- ``CohereModelID``
- ``CohereLanguage``

### Grok

- ``GrokConfiguration``
- ``GrokModelID``
- ``GrokLanguage``
- ``GrokAudioFormat``
- ``GrokTimestampGranularity``
- ``GrokFileTranscriptionOptions``
- ``GrokFileTranscriptionResponse``
- ``GrokWordTimestamp``
- ``GrokTranscriptionChannel``
- ``GrokRealtimeOptions``
- ``GrokRealtimeAudioEncoding``
- ``GrokRealtimeService``

### OpenAI

- ``OpenAIConfiguration``
- ``OpenAIFileTranscriptionModelID``
- ``OpenAIRealtimeTranscriptionModelID``
- ``OpenAIRealtimeSessionModelID``
- ``OpenAIFileTranscriptionOptions``
- ``OpenAIFileTranscriptionResponse``
- ``OpenAIDiarizationChunkingStrategy``
- ``OpenAIDiarizationVADOptions``
- ``OpenAIKnownSpeaker``
- ``OpenAIRealtimeSessionOptions``
- ``OpenAIRealtimeService``

### Meta

- ``MetaConfiguration``
- ``MetaModelID``
- ``MetaTranscriptionMode``
- ``MetaAudioEncoding``
- ``MetaPartialMode``
- ``MetaLanguage``
- ``MetaFileTranscriptionOptions``
- ``MetaTranscriptionTurn``
- ``MetaFileTranscriptionResponse``
- ``MetaRealtimeOptions``
- ``MetaRealtimeService``
- ``MetaRealtimeError``

### Gemini

- ``GeminiConfiguration``
- ``GeminiFileTranscriptionModelID``
- ``GeminiRealtimeModelID``
- ``GeminiTranscriptionMode``
- ``GeminiTimestampGranularity``
- ``GeminiFileUploadStrategy``
- ``GeminiProcessingMode``
- ``GeminiFileTranscriptionOptions``
- ``GeminiWordInfo``
- ``GeminiFileTranscriptionResponse``
- ``GeminiRealtimeOptions``
- ``GeminiRealtimeService``
- ``GeminiRealtimeError``

### Apple Local Speech

- ``AppleSpeechConfiguration``
- ``AppleSpeechModelRetention``
- ``AppleSpeechFileTranscriptionOptions``
- ``AppleSpeechFileTranscriptionClient``
- ``AppleSpeechFileTranscriptionResponse``
