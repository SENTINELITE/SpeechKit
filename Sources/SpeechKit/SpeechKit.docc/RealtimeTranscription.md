# Realtime Transcription

Stream microphone audio to ElevenLabs, OpenAI, xAI Grok, Meta, Gemini, Mistral, Fish Audio, or Apple local Speech and observe partial and committed transcript text.

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
await speech.startListening(provider: .meta)
await speech.startListening(provider: .gemini)
await speech.startListening(provider: .mistral)
await speech.startListening(provider: .fishAudio)
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
    ),
    meta: MetaConfiguration(
        apiKey: "<META_API_KEY>",
        realtimeOptions: MetaRealtimeOptions(
            mode: .diarization,
            audioEncoding: .pcm24kHz,
            partialMode: .cumulative,
            languageBias: [.english]
        )
    ),
    gemini: GeminiConfiguration(
        apiKey: "<GOOGLE_API_KEY>",
        realtimeOptions: GeminiRealtimeOptions(
            languageCodes: ["en-US"],
            mode: .verbatim
        )
    ),
    mistral: MistralConfiguration(
        apiKey: "<MISTRAL_API_KEY>",
        realtimeOptions: MistralRealtimeOptions(
            targetStreamingDelayMilliseconds: 480,
            diarize: true
        )
    ),
    fishAudio: FishAudioConfiguration(
        apiKey: "<FISH_AUDIO_API_KEY>",
        realtimeOptions: FishAudioRealtimeOptions(
            mode: .vad,
            silenceTimeout: 0.7,
            terms: ["SpeechKit"]
        )
    )
)
```

`gpt-live-transcribe` is the low-latency default. Select `gpt-transcribe` for committed WebSocket turns when your app needs OpenAI's detected-language output. Both models use `languages` instead of the legacy singular `language` hint.

Meta streams raw PCM and accepts 24 kHz or 16 kHz mono audio only, so ``MetaRealtimeOptions`` rejects ``MetaAudioEncoding/wav``. Use ``MetaPartialMode/cumulative`` when each partial event should carry the full turn text, and ``MetaPartialMode/delta`` when you only want the new words.

Gemini Live streams 16 kHz mono PCM, limits a session to 10 minutes, and returns neither speaker labels nor word timestamps. Use <doc:FileTranscription> with ``GeminiConfiguration/diarize`` or ``GeminiTimestampGranularity/word`` when you need either one.

Mistral streams 16-bit mono PCM and sends final text as it arrives, so the partial entry only grows. With turn detection, the default, SpeechKit commits one entry per turn. Mistral cannot combine turn detection with diarization: when ``MistralRealtimeOptions/diarize`` is `true`, SpeechKit leaves turn detection out, starts a new entry each time the speaker changes, and sets ``SpeechTranscriptEntry/speaker`` to Mistral's label, such as `speaker_1`, or to the name of a ``MistralSpeakerReference``. Mistral locks session settings when the first audio chunk arrives, so a change applies to the next session.

Fish Audio's realtime model, `transcribe-stream-1`, is in preview. Every message is MessagePack in a binary frame; SpeechKit handles the encoding. While a turn is open, its latest draft is the partial entry, and each draft replaces the last. When the turn commits, SpeechKit appends one final entry per speaker, with ``SpeechTranscriptEntry/speaker`` set to a label such as `speaker:0` and word timings when ``FishAudioRealtimeOptions/timestamps`` is `true`. In ``FishAudioTurnDetectionMode/auto`` mode, Fish Audio marks other voices and noise as non-user turns. SpeechKit keeps those turns. ``SpeechService`` does not report turn kinds, so use ``FishAudioRealtimeService`` directly and read ``FishAudioRealtimeTurn/kind`` from ``FishAudioRealtimeService/committedTurns`` when you need to filter them. SpeechKit validates ``FishAudioRealtimeOptions`` before connecting, because Fish Audio closes the session on any invalid setting.

Fish Audio bills a realtime session for every second the socket is open, including idle time. SpeechKit sends a keepalive while the socket is idle, so an open session keeps billing until you call ``SpeechService/stopListening()``.

| Provider | Capture format | Session limit |
| --- | --- | --- |
| Meta | 24 kHz or 16 kHz mono PCM16 | Not documented |
| Gemini | 16 kHz mono PCM16 | 10 minutes |
| Mistral | 16 kHz mono PCM16 by default, 8 to 48 kHz | Not documented |
| Fish Audio | 16 kHz mono PCM16 by default, 8 to 48 kHz | 60 minutes, 60 seconds per turn |

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

### Provider Realtime Services

- ``GrokRealtimeService``
- ``OpenAIRealtimeService``
- ``MetaRealtimeService``
- ``MetaRealtimeError``
- ``GeminiRealtimeService``
- ``GeminiRealtimeError``
- ``MistralRealtimeService``
- ``MistralRealtimeError``
- ``FishAudioRealtimeService``
- ``FishAudioRealtimeError``
- ``FishAudioRealtimeTurn``
- ``FishAudioRealtimeTurnKind``

### Realtime Operations

- ``SpeechService/startListening()``
- ``SpeechService/startListening(provider:)``
- ``SpeechService/stopListening()``
- ``SpeechService/clearTranscript()``
