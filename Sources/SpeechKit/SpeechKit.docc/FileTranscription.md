# File Transcription

Transcribe audio files with ElevenLabs, Aqua, Cohere, Grok, OpenAI, Meta, Gemini, or Apple local Speech.

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

Provider defaults come from ``ElevenLabsConfiguration``, ``AquaConfiguration``, ``CohereConfiguration``, ``GrokConfiguration``, ``OpenAIConfiguration``, ``MetaConfiguration``, ``GeminiConfiguration``, and ``AppleSpeechConfiguration``. Override defaults for one request with ``SpeechFileTranscriptionOptions``.

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

let elevenLabsResponse = try await speech.transcribeElevenLabsAudioFile(file: audioFileURL)
print(elevenLabsResponse.languageCode ?? "")
print(elevenLabsResponse.words ?? [])
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

Meta returns one turn per detected speech segment, with speaker labels in ``MetaTranscriptionMode/diarization`` mode. It accepts WAV uploads only.

```swift
let metaResponse = try await speech.transcribeMetaAudioFile(
    file: audioFileURL,
    options: MetaFileTranscriptionOptions(
        mode: .diarization,
        languageBias: [.english],
        keywords: ["SpeechKit"]
    )
)

print(metaResponse.transcript)
print(metaResponse.turns ?? [])
```

Gemini returns speaker labels and word timestamps as ``GeminiWordInfo`` annotations in ``GeminiTranscriptionMode/verbatim`` mode. A custom vocabulary cannot be combined with either one.

```swift
let geminiResponse = try await speech.transcribeGeminiAudioFile(
    file: audioFileURL,
    options: GeminiFileTranscriptionOptions(
        languageCodes: ["en-US"],
        diarize: true,
        timestampGranularities: [.word]
    )
)

print(geminiResponse.text)
print(geminiResponse.words)
```

Long recordings can outlast a synchronous request. Use ``GeminiProcessingMode/background(pollInterval:)`` to start a background interaction that SpeechKit polls until it completes. SpeechKit sends audio inline below ``GeminiFileTranscriptionOptions/inlineUploadThresholdBytes``, which defaults to 20 MB, and uploads larger files with the Gemini Files API.

```swift
let longResponse = try await speech.transcribeGeminiAudioFile(
    file: longRecordingURL,
    options: GeminiFileTranscriptionOptions(
        uploadStrategy: .filesAPI,
        processingMode: .background(pollInterval: 5)
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

## Upload Limits

SpeechKit validates uploads before sending them: unsupported file types and files over the provider size limit throw ``SpeechError/uploadFailed(provider:reason:)`` without a network round trip. Duration limits are enforced the same way whenever SpeechKit can read the file's duration, which covers every container format and raw PCM; a file whose duration cannot be determined is sent to the provider, which rejects it.

| Provider | Formats | Size limit | Duration limit |
| --- | --- | --- | --- |
| Meta | WAV | 32 MB | 10 minutes |
| Gemini | WAV, MP3, AIFF, AAC, OGG, Opus, FLAC, M4A, WebM | 20 MB inline, then the Files API | 1 hour, or 30 minutes with diarization or word timestamps |

For provider-by-provider setup examples, see <doc:ProviderHowToGuides>.

## Provider Matching

The `options` value must match the selected provider. Passing `.elevenLabs(...)` options to `.grok`, for example, throws ``SpeechError/invalidOptionsForProvider(expected:received:)``.

## Topics

### Provider-Neutral API

- ``SpeechService/transcribeAudioFile(provider:file:options:)``
- ``SpeechFileTranscriptionProvider``
- ``SpeechFileTranscriptionOptions``

### Detailed Responses

- ``SpeechService/transcribeElevenLabsAudioFile(file:modelID:)``
- ``SpeechService/transcribeAquaAudioFile(file:options:)``
- ``SpeechService/transcribeGrokAudioFile(file:options:)``
- ``SpeechService/transcribeOpenAIAudioFile(file:options:)``
- ``SpeechService/transcribeMetaAudioFile(file:options:)``
- ``SpeechService/transcribeGeminiAudioFile(file:options:)``
- ``SpeechService/transcribeAppleAudioFile(file:options:)``
- ``ElevenLabsFileTranscriptionResponse``
- ``ElevenLabsWordTimestamp``
- ``AquaFileTranscriptionResponse``
- ``GrokFileTranscriptionResponse``
- ``OpenAIFileTranscriptionResponse``
- ``MetaFileTranscriptionOptions``
- ``MetaFileTranscriptionResponse``
- ``MetaTranscriptionTurn``
- ``GeminiFileTranscriptionOptions``
- ``GeminiFileTranscriptionResponse``
- ``GeminiWordInfo``
- ``AppleSpeechFileTranscriptionResponse``
- ``AppleSpeechFileTranscriptionOptions``
- ``OpenAIDiarizationChunkingStrategy``
- ``OpenAIDiarizationVADOptions``
- ``OpenAIKnownSpeaker``

### Error Handling

- <doc:ErrorHandling>
- ``SpeechError``
