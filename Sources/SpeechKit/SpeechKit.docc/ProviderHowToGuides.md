# Provider How-To Guides

Choose a workflow first, then configure the provider that matches that workflow.

## File-Based Providers

File transcription uploads an audio file and returns text or provider-specific metadata.

### ElevenLabs Files

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        apiKey: "<ELEVENLABS_API_KEY>",
        fileTranscriptionModelID: .scribeV1
    )
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL
)
```

### Aqua Files

```swift
let speech = SpeechService(
    aqua: AquaConfiguration(
        apiKey: "<AQUA_API_KEY>",
        modelID: .avalonV15,
        language: .english
    )
)

let response = try await speech.transcribeAquaAudioFile(file: audioFileURL)
```

### Cohere Files

```swift
let speech = SpeechService(
    cohere: CohereConfiguration(
        apiKey: "<COHERE_API_KEY>",
        modelID: .transcribe032026,
        language: .english,
        temperature: 0.2
    )
)

let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL
)
```

### Grok Files

```swift
let speech = SpeechService(
    grok: GrokConfiguration(
        apiKey: "<XAI_API_KEY>",
        format: true,
        diarize: true,
        timestampGranularities: [.word]
    )
)

let response = try await speech.transcribeGrokAudioFile(file: audioFileURL)
```

### OpenAI Files

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        fileTranscriptionModelID: .gptTranscribe,
        languages: ["en", "fr"],
        keywords: ["SpeechKit", "AC-42"],
        prompt: "Use product names exactly."
    )
)

let response = try await speech.transcribeOpenAIAudioFile(file: audioFileURL)
```

For speaker labels, use the diarization model. SpeechKit sends `diarized_json`, uses automatic chunking by default, and supports optional VAD tuning plus known speaker references.

```swift
let diarized = try await speech.transcribeOpenAIAudioFile(
    file: meetingURL,
    options: OpenAIFileTranscriptionOptions(
        modelID: .gpt4oTranscribeDiarize,
        diarizationChunkingStrategy: .auto,
        knownSpeakers: [
            OpenAIKnownSpeaker(
                name: "host",
                referenceDataURL: "data:audio/wav;base64,..."
            )
        ]
    )
)

print(diarized.diarizedSegments ?? [])
```

### Apple Local Files

Apple local Speech runs on device and requires iOS 26, macOS 26, or visionOS 26. It is unavailable on watchOS and may need local speech assets for the selected locale.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(locale: .current)
    )

    let response = try await speech.transcribeAppleAudioFile(file: audioFileURL)
    print(response.text)
}
```

## Realtime Providers

Realtime transcription streams microphone audio and updates observable transcript state on ``SpeechService``.

### ElevenLabs Realtime

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        apiKey: "<ELEVENLABS_API_KEY>",
        realtimeModelID: .scribeV2Realtime
    )
)

await speech.startListening(provider: .elevenLabs)
```

### OpenAI Realtime

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        realtimeSessionModelID: .gptRealtime,
        realtimeTranscriptionModelID: .gptLiveTranscribe,
        languages: ["en", "fr"],
        keywords: ["SpeechKit", "AC-42"],
        realtimeDelay: .low,
        realtimeCommitInterval: 1
    )
)

await speech.startListening(provider: .openAI)
```

### Grok Realtime

```swift
let speech = SpeechService(
    grok: GrokConfiguration(
        apiKey: "<XAI_API_KEY>",
        realtimeOptions: GrokRealtimeOptions(
            language: .english,
            endpointingMilliseconds: 250,
            diarize: true,
            keyTerms: ["SpeechKit"]
        )
    )
)

await speech.startListening(provider: .grok)
```

### Apple Local Realtime

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            contextualStrings: ["SpeechKit"]
        )
    )

    try await speech.prepareAppleSpeechAssets()
    await speech.startListening(provider: .apple)
}
```

## Topics

### Provider Types

- ``ElevenLabsConfiguration``
- ``AquaConfiguration``
- ``CohereConfiguration``
- ``GrokConfiguration``
- ``OpenAIConfiguration``
- ``AppleSpeechConfiguration``
