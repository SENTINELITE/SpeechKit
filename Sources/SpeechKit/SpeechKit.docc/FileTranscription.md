# File Transcription

Upload audio files to ElevenLabs, Aqua, Cohere, Grok, or OpenAI and receive transcript text.

## Overview

Use ``SpeechService/transcribeAudioFile(provider:file:options:)`` for the provider-neutral API. Configure the provider first, then choose a ``SpeechFileTranscriptionProvider``.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(apiKey: "<ELEVENLABS_API_KEY>")
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL
)
```

Provider defaults come from ``ElevenLabsConfiguration``, ``AquaConfiguration``, ``CohereConfiguration``, ``GrokConfiguration``, and ``OpenAIConfiguration``. Override defaults for one request with ``SpeechFileTranscriptionOptions``.

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

let openAIResponse = try await speech.transcribeOpenAIAudioFile(file: audioFileURL)
print(openAIResponse.text)
```

OpenAI diarization uses ``OpenAIFileTranscriptionModelID/gpt4oTranscribeDiarize``. SpeechKit requests `diarized_json`, defaults diarization chunking to ``OpenAIDiarizationChunkingStrategy/auto``, and decodes speaker-bearing `segments` into ``OpenAIFileTranscriptionResponse/diarizedSegments``.

```swift
let openAIDiarizedResponse = try await speech.transcribeOpenAIAudioFile(
    file: meetingURL,
    options: OpenAIFileTranscriptionOptions(
        modelID: .gpt4oTranscribeDiarize,
        knownSpeakers: [
            OpenAIKnownSpeaker(
                name: "agent",
                referenceDataURL: "data:audio/wav;base64,..."
            )
        ]
    )
)

print(openAIDiarizedResponse.diarizedSegments ?? [])
```

For provider-by-provider setup examples, see <doc:ProviderHowToGuides>.

## Provider Matching

The `options` value must match the selected provider. Passing `.elevenLabs(...)` options to `.grok`, for example, throws ``SpeechError/invalidOptionsForProvider(expected:received:)``.

## Topics

### Provider-Neutral API

- ``SpeechService/transcribeAudioFile(provider:file:options:)``
- ``SpeechFileTranscriptionProvider``
- ``SpeechFileTranscriptionOptions``

### Detailed Responses

- ``SpeechService/transcribeAquaAudioFile(file:options:)``
- ``SpeechService/transcribeGrokAudioFile(file:options:)``
- ``SpeechService/transcribeOpenAIAudioFile(file:options:)``
- ``AquaFileTranscriptionResponse``
- ``GrokFileTranscriptionResponse``
- ``OpenAIFileTranscriptionResponse``
- ``OpenAIDiarizationChunkingStrategy``
- ``OpenAIDiarizationVADOptions``
- ``OpenAIKnownSpeaker``

### Error Handling

- <doc:ErrorHandling>
- ``SpeechError``
