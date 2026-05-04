# Provider Configuration

Configure only the transcription providers your app uses.

## Overview

``SpeechService`` accepts optional provider configuration values. Realtime transcription requires ``ElevenLabsConfig``. File transcription requires configuration for the selected provider.

```swift
let speech = SpeechService(
    aqua: AquaConfig(apiKey: "<AQUA_API_KEY>"),
    cohere: CohereConfig(apiKey: "<COHERE_API_KEY>"),
    grok: GrokConfig(apiKey: "<XAI_API_KEY>")
)
```

Each configuration type supplies provider defaults. Request-level options override those defaults for one upload.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfig(
        apiKey: "<ELEVENLABS_API_KEY>",
        realtimeModelID: .scribeV2Realtime,
        fileModelID: .scribeV1
    )
)
```

## Raw Language Codes

Provider configs also include throwing initializers that accept raw language codes when your app stores codes as strings.

```swift
let cohere = try CohereConfig(apiKey: "<COHERE_API_KEY>", languageCode: "de")
let grok = try GrokConfig(apiKey: "<XAI_API_KEY>", languageCode: "fil")
let aqua = try AquaConfig(apiKey: "<AQUA_API_KEY>", languageCode: "ja")
```

## Topics

### Configurations

- ``ElevenLabsConfig``
- ``AquaConfig``
- ``CohereConfig``
- ``GrokConfig``

### Model Identifiers

- ``ElevenLabsModelID``
- ``AquaModelID``
- ``CohereModelID``
- ``GrokModelID``

### Language Hints

- ``AquaLanguage``
- ``CohereLanguage``
- ``GrokLanguage``

