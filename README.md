# SpeechKit

[![CI](https://github.com/SENTINELITE/SpeechKit/actions/workflows/ci.yml/badge.svg)](https://github.com/SENTINELITE/SpeechKit/actions/workflows/ci.yml)
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20watchOS%2011%20%7C%20visionOS%202-lightgrey.svg)
![Status](https://img.shields.io/badge/status-1.0.0-blue.svg)

SpeechKit is a Swift package for adding speech-to-text to Swift and SwiftUI apps with a small async/await API.

It supports two workflows:

- Realtime microphone transcription with ElevenLabs, OpenAI, xAI Grok, and Apple local Speech on supported OS versions.
- File transcription with ElevenLabs, Aqua, Cohere, Grok, OpenAI, and Apple local Speech on supported OS versions.

## Highlights

- One `SpeechService` facade for SwiftUI apps.
- Provider-neutral realtime transcript state.
- Provider-neutral file transcription for simple text results.
- Provider-specific options and detailed responses when you need timestamps, diarization, usage metadata, or model-specific controls.
- On-device Apple Speech support for apps running on iOS 26, macOS 26, or visionOS 26.
- Security-scoped file overloads for document picker workflows.
- A runnable iOS demo app for trying realtime transcription, recorded dictation uploads, and file transcription.

## Status

SpeechKit `1.0.0` is the first stable release of the package API for production integration. Future source-breaking API changes will ship in a new major version.

## Sponsor the project
> <img width="1500" height="500" alt="SpeechKit" src="https://github.com/user-attachments/assets/3f3b68e7-37fb-46c7-a139-2b513b2e184c" />
> <br>
> SpeechKit is independently built and maintained. Sponsorship helps fund provider integrations, realtime transcription support, documentation, examples, and long-term maintenance.

If SpeechKit is useful to you, [sponsor the project on GitHub](https://github.com/sponsors/SENTINELITE).

## Requirements

- Swift 6.2+
- iOS 18+
- macOS 15+
- watchOS 11+
- visionOS 2+

Apps that use realtime microphone transcription must include the platform's microphone permission usage description in their app target.

Apple local Speech support requires iOS 26, macOS 26, or visionOS 26, and is unavailable on watchOS. SpeechKit keeps the package's lower deployment targets by omitting Apple from provider discovery until the current OS can run `SpeechAnalyzer`.

## Platform Support

| Platform | Minimum version | Validation |
| --- | ---: | --- |
| iOS | 18.0 | CI generic device build |
| macOS | 15.0 | SwiftPM build/test, DocC build, CI build |
| watchOS | 11.0 | CI generic device build |
| visionOS | 2.0 | CI generic device build |

SpeechKit requires the Swift 6.2 toolchain family. CI pins Xcode 26.2 and builds all declared platforms with warnings treated as errors.

Apple local Speech is an additional runtime capability on iOS 26+, macOS 26+, and visionOS 26+. It may require downloading Apple speech assets for the selected locale before transcription starts.

## Installation

Add SpeechKit as a Swift Package dependency in Xcode:

1. Open your app project.
2. Select `File > Add Package Dependencies...`.
3. Enter `https://github.com/SENTINELITE/SpeechKit.git`.
4. Add the `SpeechKit` library to your app target.

Then import it where you need speech features:

```swift
import SpeechKit
```

## Try the Demo App

This repository includes `SpeechKitDemo`, a SwiftUI iOS app that exercises the package in a real app target. Use it to try realtime transcription, record-and-upload dictation, standalone file transcription, provider selection, and API-key settings.

To run it on your device:

1. Clone this repository and open `Examples/SpeechKitDemo/SpeechKitDemo.xcodeproj` in Xcode.
2. Select the `SpeechKitDemo` scheme.
3. Select your connected iPhone or iPad as the run destination.
4. If Xcode asks for signing changes, select your development team in the `SpeechKitDemo` target's Signing & Capabilities settings. You may also need to change the bundle identifier to one that is unique to your team.
5. Build and run with `Product > Run`.
6. In the app, open Settings, add the provider API keys you want to test, then choose Realtime or Dictation from the controls menu.

The demo project references the local package at the repository root, so edits under `Sources/SpeechKit` are picked up by the demo while you develop. The demo keeps its app-only code and dependencies under `Examples/SpeechKitDemo` so package consumers only receive the `SpeechKit` library product.

## Built with SpeechKit

These apps use SpeechKit in real workflows:

- SpeechKit Demo: the included sample app for realtime transcription, recorded dictation uploads, and file transcription.
- Marker: a session marker and chaptering app that uses SpeechKit for speech-driven marker and transcript workflows.

If your app uses SpeechKit, open a pull request adding it here with a short description and a link.

## API Key Safety

The examples below use placeholder API keys so the setup is easy to follow. Do not ship provider API keys directly in a client app, especially for apps distributed through the App Store or outside your team. Use your own backend proxy, a short-lived token service when the provider supports it, or another server-side credential boundary.

Provider references:

- xAI warns not to expose API keys in client-side code in its [Speech to Text documentation](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text).
- OpenAI documents speech-to-text authentication and request patterns in its [Speech to text guide](https://platform.openai.com/docs/guides/speech-to-text).

## Chapter 1: Create a Speech Service

Create one `SpeechService` with the provider configurations your app needs. You do not need to configure every provider. `SpeechService` is the recommended integration point for apps; provider-specific realtime services are available for advanced direct integrations when you need to bypass the central facade.

```swift
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        elevenLabs: ElevenLabsConfiguration(apiKey: "<ELEVENLABS_API_KEY>"),
        openAI: OpenAIConfiguration(apiKey: "<OPENAI_API_KEY>"),
        grok: GrokConfiguration(apiKey: "<XAI_API_KEY>")
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
        }
    }
}
```

Apple local Speech does not require an API key. Add it only on OS versions that support Apple's `SpeechAnalyzer` APIs:

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            contextualStrings: ["SpeechKit"],
            preparesAssetsAutomatically: true
        )
    )
}
```

## Chapter 2: Realtime Transcription

Realtime transcription streams microphone audio and exposes provider-neutral transcript state.

```swift
struct RealtimeTranscriptView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(speech.transcriptText)

            if let partial = speech.partialTranscriptEntry {
                Text(partial.text)
                    .foregroundStyle(.secondary)
            }

            Button(speech.realtimeConnectionState.isListening ? "Stop" : "Start") {
                Task {
                    if speech.realtimeConnectionState.isActive {
                        await speech.stopListening()
                    } else {
                        await speech.startListening(provider: .openAI)
                    }
                }
            }
        }
    }
}
```

Realtime state lives on `SpeechService`:

- `realtimeConnectionState`
- `partialTranscriptEntry`
- `partialTranscriptText`
- `transcriptEntries`
- `transcriptText`
- `lastError`

### Realtime: ElevenLabs

Configure ElevenLabs and call `startListening(provider: .elevenLabs)`. Calling `startListening()` without a provider also starts ElevenLabs.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        apiKey: "<ELEVENLABS_API_KEY>",
        realtimeModelID: .scribeV2Realtime
    )
)

await speech.startListening(provider: .elevenLabs)
```

### Realtime: OpenAI

OpenAI defaults to `gpt-live-transcribe` for low-latency microphone transcription. Use `gpt-transcribe` for committed Realtime turns when detected languages are required. Both models accept a prompt, keyword hints, and multiple expected input languages.

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        realtimeSessionModelID: .gptRealtime,
        realtimeTranscriptionModelID: .gptLiveTranscribe,
        languages: ["en", "fr"],
        prompt: "A customer support call.",
        keywords: ["SpeechKit", "AC-42"],
        realtimeDelay: .low,
        realtimeCommitInterval: 1
    )
)

await speech.startListening(provider: .openAI)
```

### Realtime: Grok

Grok realtime options live in `GrokRealtimeOptions`. Use them for language hints, sample rate, endpointing, diarization, and key terms.

```swift
let speech = SpeechService(
    grok: GrokConfiguration(
        apiKey: "<XAI_API_KEY>",
        realtimeOptions: GrokRealtimeOptions(
            language: .english,
            sampleRate: 16000,
            endpointingMilliseconds: 250,
            diarize: true,
            keyTerms: ["SpeechKit", "product names"]
        )
    )
)

await speech.startListening(provider: .grok)
```

### Realtime: Apple Local Speech

Apple local Speech runs on device through Apple's Speech framework. It is available on iOS 26, macOS 26, and visionOS 26, and is not available on watchOS.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            contextualStrings: ["SpeechKit"]
        )
    )

    await speech.prepareAppleSpeechAssets()
    await speech.startListening(provider: .apple)
}
```

SpeechKit maps Apple's volatile results to `partialTranscriptEntry` and upserts final results by audio time range, so revised Apple segments do not duplicate text in `transcriptEntries`.

## Chapter 3: File Transcription

File transcription uploads an audio file and returns transcript text. Use the provider-neutral API when you only need text:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL
)
```

Use provider-specific options for one request:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .cohere,
    file: audioFileURL,
    options: .cohere(language: .english, temperature: 0.2)
)
```

### File: ElevenLabs

Use ElevenLabs Scribe for straightforward file transcription.

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

### File: Aqua

Use Aqua when you want Avalon file transcription with a typed language hint.

```swift
let speech = SpeechService(
    aqua: AquaConfiguration(
        apiKey: "<AQUA_API_KEY>",
        modelID: .avalonV15,
        language: .english
    )
)

let response = try await speech.transcribeAquaAudioFile(file: audioFileURL)
print(response.text)
```

### File: Cohere

Cohere file transcription keeps its own model, language, and temperature defaults.

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

### File: Grok

Use Grok for file transcription when you want formatting, diarization, timestamps, or detailed response metadata.

```swift
let speech = SpeechService(
    grok: GrokConfiguration(
        apiKey: "<XAI_API_KEY>",
        language: .english,
        format: true,
        diarize: true,
        timestampGranularities: [.word]
    )
)

let response = try await speech.transcribeGrokAudioFile(file: audioFileURL)
print(response.text)
print(response.words ?? [])
```

### File: OpenAI

OpenAI file transcription defaults to `gpt-transcribe`, which supports prompts, keyword hints, multiple expected input languages, and detected-language output. Whisper remains available for timestamps, and `gpt-4o-transcribe-diarize` remains available for speaker labels.

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        apiKey: "<OPENAI_API_KEY>",
        fileTranscriptionModelID: .gptTranscribe,
        languages: ["en", "fr"],
        prompt: "Use product names exactly.",
        keywords: ["SpeechKit", "AC-42"]
    )
)

let response = try await speech.transcribeOpenAIAudioFile(file: audioFileURL)
print(response.text)
print(response.languages?.map(\.code) ?? [])
print(response.usage?.seconds ?? 0)
```

For diarization, use the diarize model. SpeechKit requests `diarized_json` and defaults chunking to `.auto`; you can also provide server VAD settings and up to four known speaker reference data URLs.

```swift
let response = try await speech.transcribeOpenAIAudioFile(
    file: meetingURL,
    options: OpenAIFileTranscriptionOptions(
        modelID: .gpt4oTranscribeDiarize,
        diarizationChunkingStrategy: .serverVAD(
            OpenAIDiarizationVADOptions(
                threshold: 0.4,
                prefixPaddingMilliseconds: 250,
                silenceDurationMilliseconds: 600
            )
        ),
        knownSpeakers: [
            OpenAIKnownSpeaker(
                name: "agent",
                referenceDataURL: "data:audio/wav;base64,..."
            )
        ]
    )
)

print(response.diarizedSegments ?? [])
```

### File: Apple Local Speech

Use Apple local Speech for on-device file transcription on supported OS versions. The provider-neutral API returns text:

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(locale: .current)
    )

    let text = try await speech.transcribeAudioFile(
        provider: .apple,
        file: audioFileURL
    )
}
```

Use the Apple-specific helper when you need normalized entries and timing metadata:

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(locale: .current)
    )

    let response = try await speech.transcribeAppleAudioFile(
        file: audioFileURL,
        options: AppleSpeechFileTranscriptionOptions(
            locale: Locale(identifier: "en-US")
        )
    )

    print(response.text)
    print(response.entries)
}
```

## Chapter 4: Security-Scoped Files

If your app receives a security-scoped file URL from a document picker, use the matching `securityScopedURL` overload:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .openAI,
    securityScopedURL: pickedURL
)
```

## Chapter 5: Errors and Provider Matching

File transcription throws `SpeechError`. Realtime failures are exposed through `realtimeConnectionState` and `lastError`.

```swift
do {
    let text = try await speech.transcribeAudioFile(
        provider: .grok,
        file: audioFileURL
    )
    print(text)
} catch let error as SpeechError {
    print(error.localizedDescription)
}
```

The `options` value must match the selected file provider. Passing `.cohere(...)` options to `.openAI` throws `SpeechError.invalidOptionsForProvider`.

Apple local Speech can also throw `SpeechError.appleSpeechUnavailable`, `SpeechError.appleSpeechUnsupportedLocale`, and `SpeechError.appleSpeechAssetsUnavailable` when the OS, locale, or local model assets are not ready.

## Documentation

Open the package in Xcode and choose `Product > Build Documentation` to view the DocC reference and provider how-to guides.

## License

SpeechKit is available under the Apache License 2.0. See [LICENSE](LICENSE) for details.
