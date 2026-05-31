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

### Model Identifiers

- ``ElevenLabsModelID``
- ``AquaModelID``
- ``CohereModelID``
- ``GrokModelID``
- ``OpenAIFileTranscriptionModelID``
- ``OpenAIRealtimeTranscriptionModelID``
- ``OpenAIRealtimeSessionModelID``

### Realtime Options

- ``GrokRealtimeOptions``
- ``GrokRealtimeAudioEncoding``
- ``OpenAIRealtimeSessionOptions``
- ``OpenAIRealtimeDelay``

### Language Hints

- ``AquaLanguage``
- ``CohereLanguage``
- ``GrokLanguage``
