# File Transcription

Transcribe audio files with ElevenLabs, Aqua, Cohere, Grok, OpenAI, or Apple local Speech.

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

Provider defaults come from ``ElevenLabsConfiguration``, ``AquaConfiguration``, ``CohereConfiguration``, ``GrokConfiguration``, ``OpenAIConfiguration``, and ``AppleSpeechConfiguration``. Override defaults for one request with ``SpeechFileTranscriptionOptions``.

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
print(openAIResponse.languages?.map(\.code) ?? [])
```

OpenAI defaults to ``OpenAIFileTranscriptionModelID/gptTranscribe`` for completed recordings. It accepts ``OpenAIFileTranscriptionOptions/prompt``, keyword hints, and multiple expected language codes:

```swift
let response = try await speech.transcribeOpenAIAudioFile(
    file: audioFileURL,
    options: OpenAIFileTranscriptionOptions(
        modelID: .gptTranscribe,
        languages: ["en", "fr"],
        keywords: ["SpeechKit", "AC-42"]
    )
)
```

Apple local Speech file transcription runs on device on iOS 26, macOS 26, and visionOS 26. It is not available on watchOS.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let appleResponse = try await speech.transcribeAppleAudioFile(
        file: audioFileURL,
        options: AppleSpeechFileTranscriptionOptions(
            locale: Locale(identifier: "en-US")
        )
    )

    print(appleResponse.text)
    print(appleResponse.entries)
}
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
- ``SpeechService/transcribeAppleAudioFile(file:options:)``
- ``AquaFileTranscriptionResponse``
- ``GrokFileTranscriptionResponse``
- ``OpenAIFileTranscriptionResponse``
- ``AppleSpeechFileTranscriptionResponse``
- ``AppleSpeechFileTranscriptionOptions``
- ``OpenAIDiarizationChunkingStrategy``
- ``OpenAIDiarizationVADOptions``
- ``OpenAIKnownSpeaker``

### Error Handling

- <doc:ErrorHandling>
- ``SpeechError``
