# File Transcription

Transcribe audio files with ElevenLabs, Aqua, Cohere, Grok, OpenAI, Meta, Gemini, Mistral, Fish Audio, or Apple local Speech.

## Overview

Use ``SpeechService/transcribeAudioFile(provider:file:options:)`` for the provider-neutral API. Configure a relay or a credential for the provider, then choose a ``SpeechFileTranscriptionProvider``. Keys below are for BYOK or local testing; see <doc:ShippingInProduction> for app-owned accounts.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(credential: .apiKey("<ELEVENLABS_API_KEY>"))
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL
)
```

Provider defaults come from ``ElevenLabsConfiguration``, ``AquaConfiguration``, ``CohereConfiguration``, ``GrokConfiguration``, ``OpenAIConfiguration``, ``MetaConfiguration``, ``GeminiConfiguration``, ``MistralConfiguration``, ``FishAudioConfiguration``, and ``AppleSpeechConfiguration``. Override defaults for one request with ``SpeechFileTranscriptionOptions``.

```swift
let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL,
    options: .cohere(language: .english, temperature: 0.2)
)
```

Use provider-specific detailed helpers when the provider returns richer metadata.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

ElevenLabs defaults to ``ElevenLabsModelID/scribeV3``. ``ElevenLabsFileTranscriptionOptions/diarize`` labels each word with a speaker (`speaker_0`, `speaker_1`, …) in ``ElevenLabsFileTranscriptionResponse/words``; ``ElevenLabsFileTranscriptionOptions/speakerCount`` caps the speaker count, and ``ElevenLabsFileTranscriptionOptions/diarizationThreshold`` tunes how eagerly speakers split — the two cannot be combined. ``ElevenLabsFileTranscriptionOptions/keyterms`` bias spelling toward the right terms, ``ElevenLabsFileTranscriptionOptions/tagAudioEvents`` marks sounds such as laughter as `audio_event` words, and ``ElevenLabsFileTranscriptionOptions/entityDetection`` returns ``ElevenLabsEntity`` spans.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let scribeResponse = try await speech.transcribeElevenLabsAudioFile(
    file: audioFileURL,
    options: ElevenLabsFileTranscriptionOptions(
        diarize: true,
        speakerCount: 4,
        keyterms: ["SpeechKit"],
        tagAudioEvents: true
    )
)

print(scribeResponse.text)
for word in scribeResponse.words ?? [] {
    print("\(word.speakerID ?? "-"): \(word.text)")
}
```

Scribe v3 adds ``ElevenLabsFileTranscriptionOptions/secondaryLanguages`` and ``ElevenLabsFileTranscriptionOptions/numbersFormat``; both are rejected with ``SpeechError/providerFailure(provider:reason:)`` on `scribe_v2` and `scribe_v2_medical`. ``ElevenLabsFileTranscriptionOptions/noVerbatim`` removes filler words and false starts on every Scribe model.

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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

Mistral returns segment timestamps, and a speaker label on each segment when ``MistralFileTranscriptionOptions/diarize`` is `true`. Diarization is off by default. SpeechKit requests segment timestamps whenever diarization is on, because Mistral requires them.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let mistralResponse = try await speech.transcribeMistralAudioFile(
    file: audioFileURL,
    options: MistralFileTranscriptionOptions(
        modelID: .voxtralSmallTranscribe3,
        contextBias: ["Northwind"],
        diarize: true
    )
)

print(mistralResponse.text)
print(mistralResponse.segments)
```

Fish Audio returns word segments and punctuated speaker turns when ``FishAudioFileTranscriptionOptions/timestamps`` is `true`, the default. SpeechKit always sends the `transcribe-1-pro` model header. The response keeps Fish Audio's raw fields, and adds ``FishAudioFileTranscriptionResponse/transcriptText`` without speaker markers and ``FishAudioFileTranscriptionResponse/words``, where each word carries its speaker and, where SpeechKit can match it, punctuation from the speaker turns.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let fishAudioResponse = try await speech.transcribeFishAudioAudioFile(
    file: audioFileURL,
    options: FishAudioFileTranscriptionOptions(
        language: "en",
        diarize: .on,
        speakerCount: .exact(2)
    )
)

print(fishAudioResponse.transcriptText)
print(fishAudioResponse.words)
```

Fish Audio responds only after the whole file is transcribed, so ``FishAudioFileTranscriptionOptions/timeoutInterval`` defaults to 15 minutes. A ``FishAudioSpeakerCount`` cannot be combined with ``FishAudioDiarization/off``.

Apple local Speech file transcription runs on device on iOS 26, macOS 26, and visionOS 26. It is not available on watchOS.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

OpenAI diarization uses ``OpenAIFileTranscriptionModelID/gpt4oTranscribeDiarize``. SpeechKit requests `diarized_json`, defaults diarization chunking to ``OpenAIDiarizationChunkingStrategy/auto``, and decodes speaker-bearing `segments` into ``OpenAIFileTranscriptionResponse/diarizedSegments``. The diarize model is deprecated because OpenAI shuts it down on February 26, 2027.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

Relay normalization writes canonical PCM16 WAV with a 44-byte header and only `fmt ` and `data` chunks, or native FLAC where supported. It validates generated and pass-through WAV against the relay's RIFF grammar before upload. Every relay import has a 57,600,000-frame ceiling at 16 kHz, equivalent to 60 minutes, and a 128 MiB output-file and decoded-PCM byte ceiling. Actual conversion input/output frames and bytes are checked incrementally, and output size is checked before whole-file reads. Provider limits can be tighter. Exceeding a relay import bound throws `SpeechFailure` with category `audioTooLong` or `audioTooLarge`, and partial temporary files are removed. Direct Mistral uploads also enforce its 60-minute and 500,000,000-byte limits; other direct-provider behavior is unchanged.

| Provider | Formats | Size limit | Duration limit |
| --- | --- | --- | --- |
| ElevenLabs | Provider-supported audio | 5 GB | 15 hours |
| Meta | WAV | 32 MB | 10 minutes |
| Gemini | WAV, MP3, AIFF, AAC, OGG, Opus, FLAC, M4A, WebM | 20 MB inline, then the Files API | 1 hour, or 30 minutes with diarization or word timestamps |
| Fish Audio | WAV, MP3, AAC, M4A, MP4, FLAC, Ogg Opus or Vorbis, WebM, MOV; not AIFF or CAF | Not published; send compressed audio | 60 minutes |
| Mistral | Provider-supported audio; relay imports normalize unsupported local containers to FLAC or WAV | 500 MB, or 500,000,000 bytes | 60 minutes |

Mistral limits follow its [known-limitations page](https://docs.mistral.ai/resources/known-limitations), checked October 30, 2026. Its newer limits table leaves upload size unspecified, so SpeechKit retains the explicit conservative 500 MB preflight cap.

For provider-by-provider setup examples, see <doc:ProviderHowToGuides>.

## Provider Matching

The `options` value must match the selected provider. Passing `.elevenLabs(...)` options to `.grok`, for example, throws ``SpeechError/invalidOptionsForProvider(expected:received:)``.

## Topics

### Provider-Neutral API

- ``SpeechService/transcribeAudioFile(provider:file:options:)``
- ``SpeechFileTranscriptionProvider``
- ``SpeechFileTranscriptionOptions``

### Detailed Responses

- ``SpeechService/transcribeElevenLabsAudioFile(file:options:)``
- ``SpeechService/transcribeElevenLabsAudioFile(file:modelID:)``
- ``SpeechService/transcribeAquaAudioFile(file:options:)``
- ``SpeechService/transcribeGrokAudioFile(file:options:)``
- ``SpeechService/transcribeOpenAIAudioFile(file:options:)``
- ``SpeechService/transcribeMetaAudioFile(file:options:)``
- ``SpeechService/transcribeGeminiAudioFile(file:options:)``
- ``SpeechService/transcribeMistralAudioFile(file:options:)``
- ``SpeechService/transcribeFishAudioAudioFile(file:options:)``
- ``SpeechService/transcribeAppleAudioFile(file:options:)``
- ``ElevenLabsFileTranscriptionOptions``
- ``ElevenLabsFileTranscriptionResponse``
- ``ElevenLabsWordTimestamp``
- ``ElevenLabsEntity``
- ``ElevenLabsEntityDetection``
- ``ElevenLabsEntityCategory``
- ``ElevenLabsNumbersFormat``
- ``AquaFileTranscriptionResponse``
- ``GrokFileTranscriptionResponse``
- ``OpenAIFileTranscriptionResponse``
- ``MetaFileTranscriptionOptions``
- ``MetaFileTranscriptionResponse``
- ``MetaTranscriptionTurn``
- ``GeminiFileTranscriptionOptions``
- ``GeminiFileTranscriptionResponse``
- ``GeminiWordInfo``
- ``MistralFileTranscriptionOptions``
- ``MistralFileTranscriptionResponse``
- ``MistralTranscriptionSegment``
- ``MistralTranscriptionUsage``
- ``FishAudioFileTranscriptionOptions``
- ``FishAudioFileTranscriptionResponse``
- ``FishAudioTranscriptionSegment``
- ``FishAudioSpeakerTurn``
- ``FishAudioTranscriptWord``
- ``AppleSpeechFileTranscriptionResponse``
- ``AppleSpeechFileTranscriptionOptions``
- ``OpenAIDiarizationChunkingStrategy``
- ``OpenAIDiarizationVADOptions``
- ``OpenAIKnownSpeaker``

### Error Handling

- <doc:ErrorHandling>
- ``SpeechError``
