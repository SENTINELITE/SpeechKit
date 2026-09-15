# Provider How-To Guides

Choose a workflow first, then configure the provider that matches that workflow.

## File-Based Providers

File transcription uploads an audio file and returns text or provider-specific metadata.

### ElevenLabs Files

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        apiKey: "<ELEVENLABS_API_KEY>",
        fileTranscriptionModelID: .scribeV2
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

### Meta Files

Meta accepts WAV uploads up to 32 MB and 10 minutes. Use `.diarization` mode for speaker labels on each turn.

```swift
let speech = SpeechService(
    meta: MetaConfiguration(
        apiKey: "<META_API_KEY>",
        mode: .diarization,
        languageBias: [.english],
        keywords: ["SpeechKit"]
    )
)

let response = try await speech.transcribeMetaAudioFile(file: audioFileURL)
print(response.transcript)
print(response.turns ?? [])
```

### Gemini Files

Gemini accepts up to one hour of audio, or 30 minutes when diarization or word timestamps are on.

```swift
let speech = SpeechService(
    gemini: GeminiConfiguration(
        apiKey: "<GOOGLE_API_KEY>",
        languageCodes: ["en-US"],
        mode: .verbatim,
        diarize: true,
        timestampGranularities: [.word]
    )
)

let response = try await speech.transcribeGeminiAudioFile(file: audioFileURL)
print(response.text)
print(response.words)
```

Gemini rejects a custom vocabulary combined with diarization or word timestamps. For long recordings, poll a background interaction instead of waiting on one request.

```swift
let response = try await speech.transcribeGeminiAudioFile(
    file: longRecordingURL,
    options: GeminiFileTranscriptionOptions(
        customVocabulary: ["SpeechKit"],
        processingMode: .background(pollInterval: 5)
    )
)
```

SpeechKit sends audio inline below the 20 MB default threshold and uploads larger files with the Gemini Files API.

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

### Meta Realtime

Meta realtime sessions accept 24 kHz or 16 kHz mono PCM only.

```swift
let speech = SpeechService(
    meta: MetaConfiguration(
        apiKey: "<META_API_KEY>",
        realtimeOptions: MetaRealtimeOptions(
            mode: .diarization,
            audioEncoding: .pcm24kHz,
            partialMode: .cumulative,
            languageBias: [.english],
            keywords: ["SpeechKit"]
        )
    )
)

await speech.startListening(provider: .meta)
```

### Gemini Realtime

Gemini Live sessions stream 16 kHz mono PCM, last up to 10 minutes, and do not return speaker labels or word timestamps.

```swift
let speech = SpeechService(
    gemini: GeminiConfiguration(
        apiKey: "<GOOGLE_API_KEY>",
        realtimeOptions: GeminiRealtimeOptions(
            languageCodes: ["en-US"],
            customVocabulary: ["SpeechKit"],
            mode: .verbatim
        )
    )
)

await speech.startListening(provider: .gemini)
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
- ``MetaConfiguration``
- ``GeminiConfiguration``
- ``AppleSpeechConfiguration``
