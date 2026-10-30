# Provider Configuration

Configure only the transcription providers your app uses.

## Overview

``SpeechService`` accepts optional provider configuration values. Realtime transcription requires a configuration for the selected provider. File transcription requires configuration for the selected provider.

```swift
let speech = SpeechService(
    aqua: AquaConfiguration(apiKey: "<AQUA_API_KEY>"),
    cohere: CohereConfiguration(apiKey: "<COHERE_API_KEY>"),
    grok: GrokConfiguration(apiKey: "<XAI_API_KEY>"),
    openAI: OpenAIConfiguration(apiKey: "<OPENAI_API_KEY>"),
    meta: MetaConfiguration(apiKey: "<META_API_KEY>"),
    gemini: GeminiConfiguration(apiKey: "<GOOGLE_API_KEY>"),
    mistral: MistralConfiguration(apiKey: "<MISTRAL_API_KEY>"),
    fishAudio: FishAudioConfiguration(apiKey: "<FISH_AUDIO_API_KEY>")
)
```

Apple local Speech is configured only on iOS 26, macOS 26, and visionOS 26. It does not require an API key and is unavailable on watchOS.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            preparesAssetsAutomatically: true,
            contextualStrings: ["SpeechKit"]
        )
    )
}
```

Each configuration type supplies provider defaults. Request-level options override those defaults for one upload.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        apiKey: "<ELEVENLABS_API_KEY>",
        realtimeModelID: .scribeV2Realtime,
        fileTranscriptionModelID: .scribeV2
    ),
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
        mode: .diarization,
        languageBias: [.english],
        keywords: ["SpeechKit"]
    ),
    gemini: GeminiConfiguration(
        apiKey: "<GOOGLE_API_KEY>",
        languageCodes: ["en-US"],
        mode: .verbatim,
        diarize: true,
        timestampGranularities: [.word]
    ),
    mistral: MistralConfiguration(
        apiKey: "<MISTRAL_API_KEY>",
        fileTranscriptionModelID: .voxtralSmallTranscribe3,
        contextBias: ["SpeechKit"],
        diarize: true,
        realtimeOptions: MistralRealtimeOptions(
            targetStreamingDelayMilliseconds: 480,
            diarize: true
        )
    ),
    fishAudio: FishAudioConfiguration(
        apiKey: "<FISH_AUDIO_API_KEY>",
        language: "en",
        diarize: .on,
        speakerCount: .range(min: 2, max: 4),
        realtimeOptions: FishAudioRealtimeOptions(
            mode: .vad,
            terms: ["SpeechKit"]
        )
    )
)
```

## Raw Language Codes

Provider configurations also include throwing initializers that accept raw language codes when your app stores codes as strings.

```swift
let cohere = try CohereConfiguration(apiKey: "<COHERE_API_KEY>", languageCode: "de")
let grok = try GrokConfiguration(apiKey: "<XAI_API_KEY>", languageCode: "fil")
let aqua = try AquaConfiguration(apiKey: "<AQUA_API_KEY>", languageCode: "ja")
```

Meta biases transcription with language names instead of codes, so ``MetaConfiguration/init(apiKey:modelID:mode:languageNames:keywords:realtimeOptions:timeoutInterval:fileEndpoint:realtimeEndpoint:)`` takes names such as `"English"` or `"Mandarin Chinese"` and throws when a name is not supported. Gemini takes free-form BCP-47 codes in ``GeminiConfiguration/languageCodes``, so it needs no typed language enum; an empty array lets Gemini detect the language. Mistral takes a two-letter ISO 639-1 code such as `"en"` in ``MistralConfiguration/language``, or `nil` to detect the language. Fish Audio takes a lowercase two-letter code in ``FishAudioConfiguration/language`` and throws at request time for anything else. The code is a hint for file transcription only; it does not force the language.

```swift
let meta = try MetaConfiguration(apiKey: "<META_API_KEY>", languageNames: ["English", "Spanish"])
let gemini = GeminiConfiguration(apiKey: "<GOOGLE_API_KEY>", languageCodes: ["en-US", "es-US"])
```

## Credentials and Endpoints

Every keyed configuration stores a ``SpeechCredential``. Use ``SpeechCredential/apiKey(_:)`` for a long-lived vendor key, or ``SpeechCredential/token(_:)`` with a ``SpeechTokenProvider`` that fetches a short-lived token from your own backend. SpeechKit resolves a token provider once per file transcription request and once per realtime session.

```swift
let openAI = OpenAIConfiguration(
    credential: .token(SpeechTokenProvider { try await backend.fetchClientSecret() })
)
```

The `apiKey` property remains available on every configuration and realtime service. Reading it returns the key for an API-key credential and an empty string for a token credential; writing it replaces the credential with ``SpeechCredential/apiKey(_:)``.

ElevenLabs issues single-use tokens for realtime Scribe, OpenAI issues ephemeral client secrets for Realtime, and Google issues ephemeral tokens for Gemini Live. Aqua, Cohere, Grok, Meta, Mistral, and Fish Audio have no first-party short-lived token, so route those through your own proxy. A Fish Audio ``SpeechCredential/token(_:)`` value is sent as the same bearer secret as an API key. A Google ephemeral token only authorizes Gemini Live; a token used for Gemini file transcription must be an OAuth access token or a credential your proxy accepts.

Each configuration also takes endpoint overrides so your app can route provider traffic through a proxy that injects the vendor key. `fileEndpoint` replaces the file transcription URL, `realtimeEndpoint` replaces the realtime WebSocket URL for ElevenLabs, OpenAI, Grok, Meta, Gemini, Mistral, and Fish Audio, and ``GeminiConfiguration/filesEndpoint`` replaces the Gemini Files API upload URL. A `nil` value keeps the vendor default, and SpeechKit still appends the query items each provider needs.

```swift
let grok = GrokConfiguration(
    credential: .token(SpeechTokenProvider { try await backend.fetchProxyToken() }),
    fileEndpoint: URL(string: "https://api.example.com/grok/stt"),
    realtimeEndpoint: URL(string: "wss://api.example.com/grok/stt")
)
```

## Topics

### Credentials

- ``SpeechCredential``
- ``SpeechTokenProvider``

### Configurations

- ``ElevenLabsConfiguration``
- ``AquaConfiguration``
- ``CohereConfiguration``
- ``GrokConfiguration``
- ``OpenAIConfiguration``
- ``MetaConfiguration``
- ``GeminiConfiguration``
- ``MistralConfiguration``
- ``FishAudioConfiguration``
- ``AppleSpeechConfiguration``
- ``AppleSpeechModelRetention``

### Model Identifiers

- ``ElevenLabsModelID``
- ``AquaModelID``
- ``CohereModelID``
- ``GrokModelID``
- ``OpenAIFileTranscriptionModelID``
- ``OpenAIRealtimeTranscriptionModelID``
- ``OpenAIRealtimeSessionModelID``
- ``MetaModelID``
- ``GeminiFileTranscriptionModelID``
- ``GeminiRealtimeModelID``
- ``MistralFileTranscriptionModelID``
- ``MistralRealtimeModelID``
- ``FishAudioFileTranscriptionModelID``

### Request Options

- ``AppleSpeechFileTranscriptionOptions``
- ``GrokRealtimeOptions``
- ``GrokRealtimeAudioEncoding``
- ``OpenAIRealtimeSessionOptions``
- ``OpenAIRealtimeDelay``
- ``MetaRealtimeOptions``
- ``MetaTranscriptionMode``
- ``MetaAudioEncoding``
- ``MetaPartialMode``
- ``GeminiRealtimeOptions``
- ``GeminiTranscriptionMode``
- ``GeminiTimestampGranularity``
- ``GeminiFileUploadStrategy``
- ``GeminiProcessingMode``
- ``MistralRealtimeOptions``
- ``MistralTurnDetection``
- ``MistralSpeakerReference``
- ``MistralTimestampGranularity``
- ``FishAudioRealtimeOptions``
- ``FishAudioTurnDetectionMode``
- ``FishAudioContextItem``
- ``FishAudioContextRole``
- ``FishAudioDiarization``
- ``FishAudioSpeakerCount``

### Language Hints

- ``AquaLanguage``
- ``CohereLanguage``
- ``GrokLanguage``
- ``MetaLanguage``
