# Provider Configuration

Configure only the transcription providers your app uses.

## Overview

``SpeechService`` accepts optional provider configuration values. Realtime transcription requires a configuration for the selected provider. File transcription requires configuration for the selected provider.

```swift
let speech = SpeechService(
    aqua: AquaConfiguration(apiKey: "<AQUA_API_KEY>"),
    cohere: CohereConfiguration(apiKey: "<COHERE_API_KEY>"),
    grok: GrokConfiguration(apiKey: "<XAI_API_KEY>"),
    openAI: OpenAIConfiguration(apiKey: "<OPENAI_API_KEY>")
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
        fileTranscriptionModelID: .scribeV1
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

## Topics

### Configurations

- ``ElevenLabsConfiguration``
- ``AquaConfiguration``
- ``CohereConfiguration``
- ``GrokConfiguration``
- ``OpenAIConfiguration``
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

### Request Options

- ``AppleSpeechFileTranscriptionOptions``
- ``GrokRealtimeOptions``
- ``GrokRealtimeAudioEncoding``
- ``OpenAIRealtimeSessionOptions``
- ``OpenAIRealtimeDelay``

### Language Hints

- ``AquaLanguage``
- ``CohereLanguage``
- ``GrokLanguage``
