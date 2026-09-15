# Realtime Transcription

Stream microphone audio to ElevenLabs, OpenAI, xAI Grok, or Apple local Speech and observe partial and committed transcript text.

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

Apple local Speech is available on iOS 26, macOS 26, and visionOS 26. SpeechKit omits `.apple` from ``SpeechRealtimeProvider/allCases`` before those OS versions and on watchOS.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    try await speech.prepareAppleSpeechAssets()
    await speech.startListening(provider: .apple)
}
```

Configure provider-specific realtime defaults when creating ``SpeechService``:

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        realtimeTranscriptionModelID: .gptLiveTranscribe,
        languages: ["en", "fr"],
        keywords: ["SpeechKit", "AC-42"],
        realtimeDelay: .low,
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

`gpt-live-transcribe` is the low-latency default. Select `gpt-transcribe` for committed WebSocket turns when your app needs OpenAI's detected-language output. Both models use `languages` instead of the legacy singular `language` hint.

For provider-by-provider setup examples, see <doc:ProviderHowToGuides>.

## Apple Volatile Results

Apple Speech can emit volatile text and later replace it with a final result for the same audio range. SpeechKit keeps the volatile result in ``SpeechService/partialTranscriptEntry`` and upserts final entries by Apple's audio time range. This avoids duplicate committed text when Apple adds punctuation or revises words before finalization.

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
- ``SpeechError/appleSpeechUnavailable``
- ``SpeechRealtimeProvider``
- ``SpeechRealtimeConnectionState``
- ``SpeechTranscriptEntry``
- ``SpeechTranscriptWord``

### Realtime Operations

- ``SpeechService/startListening()``
- ``SpeechService/startListening(provider:)``
- ``SpeechService/stopListening()``
- ``SpeechService/clearTranscript()``
