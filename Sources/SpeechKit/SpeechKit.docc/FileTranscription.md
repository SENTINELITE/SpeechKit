# File Transcription

Upload audio files to ElevenLabs, Aqua, Cohere, or Grok and receive transcript text.

## Overview

Use ``SpeechService/transcribeAudioFile(provider:file:options:)`` for the provider-neutral API. Configure the provider first, then choose a ``SpeechFileProvider``.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfig(apiKey: "<ELEVENLABS_API_KEY>")
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL
)
```

Provider defaults come from ``ElevenLabsConfig``, ``AquaConfig``, ``CohereConfig``, and ``GrokConfig``. Override defaults for one request with ``SpeechFileTranscriptionOptions``.

```swift
let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL,
    options: .cohere(language: .english, temperature: 0.2)
)
```

Use provider-specific detailed helpers when the provider returns richer metadata.

```swift
let response = try await speech.transcribeGrokAudioFile(file: audioFileURL)
print(response.text)
print(response.words ?? [])
```

## Provider Matching

The `options` value must match the selected provider. Passing `.elevenLabs(...)` options to `.grok`, for example, throws ``SpeechError/invalidOptionsForProvider(expected:received:)``.

## Topics

### Provider-Neutral API

- ``SpeechService/transcribeAudioFile(provider:file:options:)``
- ``SpeechFileProvider``
- ``SpeechFileTranscriptionOptions``

### Detailed Responses

- ``SpeechService/transcribeAquaAudioFile(file:options:)``
- ``SpeechService/transcribeGrokAudioFile(file:options:)``
- ``AquaFileTranscriptionResponse``
- ``GrokFileTranscriptionResponse``

### Error Handling

- <doc:ErrorHandling>
- ``SpeechError``

