# Provider Configuration

Configure only the transcription providers your app uses.

## Overview

``SpeechService`` accepts optional provider configuration values. A relay supplies credentials for its configured providers; without a relay, supply a credential for the selected capability. See <doc:ShippingInProduction> before choosing app-owned credentials.

```swift
let speech = SpeechService(
    cohere: CohereConfiguration(credential: .apiKey("<COHERE_API_KEY>")),
    grok: GrokConfiguration(credential: .apiKey("<XAI_API_KEY>")),
    aqua: AquaConfiguration(credential: .apiKey("<AQUA_API_KEY>")),
    openAI: OpenAIConfiguration(credential: .apiKey("<OPENAI_API_KEY>")),
    meta: MetaConfiguration(credential: .apiKey("<META_API_KEY>")),
    gemini: GeminiConfiguration(credential: .apiKey("<GOOGLE_API_KEY>")),
    mistral: MistralConfiguration(credential: .apiKey("<MISTRAL_API_KEY>")),
    fishAudio: FishAudioConfiguration(credential: .apiKey("<FISH_AUDIO_API_KEY>"))
)
```

Apple local Speech is configured only on iOS 26, macOS 26, and visionOS 26. It does not require an API key and is unavailable on watchOS.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            preparesAssetsAutomatically: true,
            contextualStrings: ["SpeechKit"]
        )
    )
}
```

Each configuration type supplies provider defaults. Request-level options override those defaults for one upload.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        credential: .apiKey("<ELEVENLABS_API_KEY>"),
        realtimeModelID: .scribeV2Realtime,
        fileTranscriptionModelID: .scribeV2
    ),
    grok: GrokConfiguration(
        credential: .apiKey("<XAI_API_KEY>"),
        realtimeOptions: GrokRealtimeOptions(
            language: .english,
            keyTerms: ["SpeechKit"]
        )
    ),
    openAI: OpenAIConfiguration(
        credential: .apiKey("<OPENAI_API_KEY>"),
        realtimeTranscriptionModelID: .gptLiveTranscribe,
        languages: ["en", "fr"],
        keywords: ["SpeechKit", "AC-42"],
        realtimeDelay: .low,
        realtimeCommitInterval: 1
    ),
    meta: MetaConfiguration(
        credential: .apiKey("<META_API_KEY>"),
        mode: .diarization,
        languageBias: [.english],
        keywords: ["SpeechKit"]
    ),
    gemini: GeminiConfiguration(
        credential: .apiKey("<GOOGLE_API_KEY>"),
        languageCodes: ["en-US"],
        mode: .verbatim,
        diarize: true,
        timestampGranularities: [.word]
    ),
    mistral: MistralConfiguration(
        credential: .apiKey("<MISTRAL_API_KEY>"),
        fileTranscriptionModelID: .voxtralSmallTranscribe3,
        contextBias: ["SpeechKit"],
        diarize: true,
        realtimeOptions: MistralRealtimeOptions(
            targetStreamingDelayMilliseconds: 480,
            diarize: true
        )
    ),
    fishAudio: FishAudioConfiguration(
        credential: .apiKey("<FISH_AUDIO_API_KEY>"),
        language: "en",
        diarize: .on,
        speakerCount: .range(min: 2, max: 4),
        realtimeOptions: FishAudioRealtimeOptions(
            mode: .vad,
            terms: ["SpeechKit"]
        )
    )
)
```

## Raw Language Codes

When your app stores language codes as strings, validate them before constructing a credential-backed configuration. The legacy throwing `languageCode:` initializers accept only `apiKey:`, not `credential:`.

```swift
guard let cohereLanguage = CohereLanguage(rawValue: "de") else {
    throw SpeechError.providerFailure(provider: .cohere, reason: .invalidOptions)
}
guard let grokLanguage = GrokLanguage(rawValue: "fil") else {
    throw SpeechError.providerFailure(provider: .grok, reason: .invalidOptions)
}
guard let aquaLanguage = AquaLanguage(rawValue: "ja") else {
    throw SpeechError.providerFailure(provider: .aqua, reason: .invalidOptions)
}
let cohere = CohereConfiguration(credential: .apiKey("<COHERE_API_KEY>"), language: cohereLanguage)
let grok = GrokConfiguration(credential: .apiKey("<XAI_API_KEY>"), language: grokLanguage)
let aqua = AquaConfiguration(credential: .apiKey("<AQUA_API_KEY>"), language: aquaLanguage)
```

Meta biases transcription with language names instead of codes. Use typed ``MetaLanguage`` values with the credential initializer. Its legacy throwing `languageNames:` initializer also accepts only `apiKey:`. Gemini takes free-form BCP-47 codes in ``GeminiConfiguration/languageCodes``, so it needs no typed language enum; an empty array lets Gemini detect the language. Mistral takes a two-letter ISO 639-1 code such as `"en"` in ``MistralConfiguration/language``, or `nil` to detect the language. Fish Audio takes a lowercase two-letter code in ``FishAudioConfiguration/language`` and throws at request time for anything else. The code is a hint for file transcription only; it does not force the language.

```swift
let meta = MetaConfiguration(credential: .apiKey("<META_API_KEY>"), languageBias: [.english, .spanish])
let gemini = GeminiConfiguration(credential: .apiKey("<GOOGLE_API_KEY>"), languageCodes: ["en-US", "es-US"])
```

## Credentials and endpoints

``SpeechCredential`` is opaque. `.apiKey` is for a user's own key or local testing, `.vendorToken` for documented native tokens, and `.bearer` for a custom proxy or separately authorized Gemini REST OAuth. SpeechKit creates relay credentials internally. Never fetch a permanent app-owned vendor key as a substitute for a relay.

```swift
@MainActor
func nativeOpenAIConfiguration(
    fetchToken: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken
) -> OpenAIConfiguration {
    var configuration = OpenAIConfiguration()
    configuration.setCredential(
        .vendorToken(SpeechTokenResolver { context in try await fetchToken(context) }),
        for: .realtime
    )
    return configuration
}
```

This leaves file authorization empty because OpenAI Realtime secrets do not authorize files. Configurations expose `credentialKind`, `hasCredential`, and capability-specific variants, not `apiKey` or `credential` properties. `setCredential(_:)` replaces the base credential and clears capability overrides; `setCredential(_:for:)` changes one capability. Assign the updated configuration back to the service to invalidate pending work. Direct realtime services also provide `reconfigure(credential:realtimeEndpoint:)` for an awaited paired replacement.

```swift
var configuration = ElevenLabsConfiguration(credential: .apiKey("<USER_SUPPLIED_KEY>"))
configuration.setCredential(.apiKey("<REPLACEMENT_USER_KEY>"))
let mode = configuration.credentialKind
let isConfigured = configuration.hasCredential(for: .realtime)
speech.elevenLabs = configuration
```

Resolver closures accept ``SpeechTokenContext`` and return a string or ``SpeechAccessToken``. They can run again for a new operation or bounded pre-send renewal; do not rely on a process-wide "called exactly once" promise or share a single-use token across operations. A resolver's UUID defines equality. Capture your login/backend client deliberately, and release application-owned references separately at sign-out.

Use ``SpeechRelay`` for app-owned authority. It supplies complete routes without per-provider credentials:

```swift
let speech = SpeechService(
    relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!),
    fishAudio: FishAudioConfiguration(language: "en"),
    credentialPolicy: .relayOnly
)
```

A configuration with no credential inherits the relay; one with a credential uses its explicit endpoint for that capability instead. Missing direct endpoints fail closed. `.relayOnly` rejects such direct overrides and forces proxy traffic; `.disallowStaticKeys` rejects static keys but permits native tokens and custom proxy bearer tokens. Defaults remain `.allowStaticKeys` and relay `.proxyAll`.

For a custom proxy, use `.bearer`, supply both file and realtime endpoints as needed, and implement all provider-specific routes. Gemini requires a complete ``GeminiRoute`` with Interactions, Files upload, and Live endpoints; file and interaction polling and returned upload-session URLs must remain on approved origins. Meta requires first-frame auth replacement. `nil` endpoints mean vendor defaults in direct mode, not automatic protection. Endpoints require HTTPS/WSS except loopback development; redirects are refused.

See <doc:ShippingInProduction> for the dated provider/capability/auth-placement matrix, complete Gemini route and login examples, and limits of server and client controls. See <doc:MigratingTo3> for removed APIs.

## Topics

### Credentials

- ``SpeechCredential``
- ``SpeechTokenResolver``
- ``SpeechTokenContext``
- ``SpeechAccessToken``
- ``SpeechCapability``
- ``SpeechCredentialPolicy``
- ``SpeechRelay``
- ``GeminiRoute``

### Configurations

- ``ElevenLabsConfiguration``
- ``AquaConfiguration``
- ``CohereConfiguration``
- ``GrokConfiguration``
- ``OpenAIConfiguration``
- ``MetaConfiguration``
- ``GeminiConfiguration``
- ``MistralConfiguration``
- ``FishAudioConfiguration``
- ``AppleSpeechConfiguration``
- ``AppleSpeechModelRetention``

### Model Identifiers

- ``ElevenLabsModelID``
- ``AquaModelID``
- ``CohereModelID``
- ``GrokModelID``
- ``OpenAIFileTranscriptionModelID``
- ``OpenAIRealtimeTranscriptionModelID``
- ``OpenAIRealtimeSessionModelID``
- ``MetaModelID``
- ``GeminiFileTranscriptionModelID``
- ``GeminiRealtimeModelID``
- ``MistralFileTranscriptionModelID``
- ``MistralRealtimeModelID``
- ``FishAudioFileTranscriptionModelID``

### Request Options

- ``AppleSpeechFileTranscriptionOptions``
- ``GrokRealtimeOptions``
- ``GrokRealtimeAudioEncoding``
- ``OpenAIRealtimeSessionOptions``
- ``OpenAIRealtimeDelay``
- ``MetaRealtimeOptions``
- ``MetaTranscriptionMode``
- ``MetaAudioEncoding``
- ``MetaPartialMode``
- ``GeminiRealtimeOptions``
- ``GeminiTranscriptionMode``
- ``GeminiTimestampGranularity``
- ``GeminiFileUploadStrategy``
- ``GeminiProcessingMode``
- ``MistralRealtimeOptions``
- ``MistralTurnDetection``
- ``MistralSpeakerReference``
- ``MistralTimestampGranularity``
- ``FishAudioRealtimeOptions``
- ``FishAudioTurnDetectionMode``
- ``FishAudioContextItem``
- ``FishAudioContextRole``
- ``FishAudioDiarization``
- ``FishAudioSpeakerCount``

### Language Hints

- ``AquaLanguage``
- ``CohereLanguage``
- ``GrokLanguage``
- ``MetaLanguage``
