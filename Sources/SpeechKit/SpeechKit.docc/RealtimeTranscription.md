# Realtime Transcription

Stream microphone audio to ElevenLabs, OpenAI, or xAI Grok and observe partial and committed transcript text.

## Overview

Realtime transcription requires a provider configuration for the selected realtime provider. Call ``SpeechService/startListening(provider:)`` and ``SpeechService/stopListening()`` from an asynchronous context. Calling ``SpeechService/startListening()`` without a provider starts ElevenLabs transcription. ``SpeechService`` is the recommended app-facing API; provider-specific realtime services are available when an app intentionally needs direct provider control.

```swift
struct TranscriptView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        VStack(alignment: .leading) {
            Text(speech.transcriptText)

            if let partial = speech.partialTranscriptEntry {
                Text(partial.text)
                    .foregroundStyle(.secondary)
            }

            Button(speech.realtimeConnectionState.isListening ? "Stop" : "Start") {
                Task {
                    if speech.realtimeConnectionState.isActive {
                        await speech.stopListening()
                    } else {
                        await speech.startListening(provider: .grok)
                    }
                }
            }
        }
    }
}
```

``SpeechService`` exposes committed entries through ``SpeechService/transcriptEntries``, the active partial entry through ``SpeechService/partialTranscriptEntry``, and the joined text through ``SpeechService/transcriptText``. Call ``SpeechService/clearTranscript()`` when the user starts a new dictation session.

Start a specific realtime provider by passing ``SpeechRealtimeProvider``:

```swift
await speech.startListening(provider: .openAI)
await speech.startListening(provider: .grok)
```

Configure provider-specific realtime defaults when creating ``SpeechService``:

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        realtimeTranscriptionModelID: .gpt4oTranscribe,
        realtimeDelay: .milliseconds(300),
        realtimeCommitInterval: 1
    ),
    grok: GrokConfiguration(
        apiKey: "<XAI_API_KEY>",
        realtimeOptions: GrokRealtimeOptions(
            language: .english,
            keyTerms: ["SpeechKit"]
        )
    )
)
```

For provider-by-provider setup examples, see <doc:ProviderHowToGuides>.

## Failure Handling

When a realtime provider is not configured, ``SpeechService/startListening(provider:)`` sets ``SpeechService/realtimeConnectionState`` to ``SpeechRealtimeConnectionState/error(_:)`` and exposes ``SpeechError/realtimeProviderNotConfigured(_:)`` through ``SpeechService/lastError``. Provider-specific failures still surface when using provider services directly.

## Topics

### Realtime State

- ``SpeechService/realtimeConnectionState``
- ``SpeechService/connectionState``
- ``SpeechService/partialTranscriptEntry``
- ``SpeechService/partialTranscriptText``
- ``SpeechService/transcriptEntries``
- ``SpeechService/transcriptText``
- ``SpeechService/lastError``
- ``SpeechError/realtimeProviderNotConfigured(_:)``
- ``SpeechRealtimeProvider``
- ``SpeechRealtimeConnectionState``
- ``SpeechTranscriptEntry``
- ``SpeechTranscriptWord``

### Realtime Operations

- ``SpeechService/startListening()``
- ``SpeechService/startListening(provider:)``
- ``SpeechService/stopListening()``
- ``SpeechService/clearTranscript()``
