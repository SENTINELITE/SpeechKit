# Migrating to 3.0

Move from SpeechKit 2.x to opaque credentials, explicit authentication modes, and bounded errors.

2.0.1 is the last published release. The unreleased 2.1.0 provider additions ship here, so 3.0.0 includes their exhaustive-switch changes as well as the credential and error breaks.

1. Replace `SpeechTokenProvider` with `SpeechTokenResolver`; it is removed, not a deprecated alias. Resolver closures now accept a `SpeechTokenContext`, so a closure that ignores it starts with `{ _ in ... }`. The result can be a `String` or `SpeechAccessToken`. `token()` is gone; call your own backend adapter when your application needs a token outside SpeechKit. Resolver equality still uses its UUID `id`.
2. Replace `.token(...)` with `.vendorToken(resolver)` for supported native tokens or `.bearer(resolver)` for your own proxy and separately authorized Gemini REST OAuth. No public `.relay(...)` factory exists; create `SpeechRelay` instead. Unsupported provider/capability combinations fail before token resolution or vendor I/O. In particular, OpenAI file transcription cannot use a Realtime secret, Fish/Grok STT cannot use agent/voice tokens, and Mistral native-token mode permits only `.voxtralMiniTranscribeRealtime2602`, not Voxtral 3.
3. `SpeechCredential` is now an opaque struct. Remove enum pattern matching, payload extraction, and secret readback. Use `kind` for nonsecret decisions. Configuration and realtime-service `apiKey` properties and public `credential` access are removed. Construct with `credential: .apiKey(...)` and update with `setCredential(_:)`; configuration values also offer `setCredential(_:for:)`, `credentialKind(for:)`, and `hasCredential(for:)`. The `apiKey:` initializer overloads remain supported. `setCredential(_:)` clears both capability overrides; inspect the capability-specific metadata when you use overrides.
4. For direct realtime services, use `await service.reconfigure(credential:realtimeEndpoint:)` when changing credential and endpoint together. The synchronous `setCredential(_:)` and endpoint setters remain, but invalidate active/pending work. For the facade, replace its provider configuration as one value. Setting a configuration to `nil` now cancels that provider's pending work. A credentialed direct override in a relay-backed service needs the explicit endpoint for the selected capability; credential-free configurations inherit the relay.
5. Replace partial Gemini proxy configuration with `GeminiRoute` and `setRoute(_:)`. Supply Interactions, Files upload, and Live endpoints from one origin by default, and keep returned upload URLs and file/interaction poll routes on approved origins. Use `.explicitMixedOrigins` only for a deliberate reviewed direct integration; relay tickets cannot use it. Endpoints must use HTTPS/WSS except loopback development; URL userinfo/fragments and redirects are refused. Custom proxies that depended on redirects must return the final approved URL directly.
6. Update error constructors and switches. `SpeechError.uploadFailed`, `.decodingFailed`, and `.providerFailure` take `SpeechFailureReason` instead of `String`. The same replacement applies to ElevenLabs `connectionFailed`, `decodingFailed`, `audioEngineError`, `uploadFailed`, and `unsupportedModel`; OpenAI `connectionFailed` and `invalidOptions`; Grok/Meta/Mistral `connectionFailed`; Gemini `connectionFailed` and `sessionEnding`; and `SpeechAudioCaptureError.audioEngineError`. Fish Audio `serverError(errorType:code:message:)` becomes `serverError(code:)`, and `sessionClosed(code:errorType:message:)` becomes `sessionClosed(code:)`. Handle the new `SpeechError.httpFailure(provider:statusCode:)` and `SpeechFailure` categories. Do not parse provider bodies, URL-bearing error strings, or arbitrary callback text from errors; they are no longer exposed. Keep cancellation handling separate from failure UI.
7. Add `.mistral` and `.fishAudio` to exhaustive switches on `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions`. `SpeechService` accepts `mistral:` after `gemini:`, then `fishAudio:`, with optional `credentialPolicy:` last. Its provider parameter order is `elevenLabs`, `cohere`, `grok`, `aqua`, `openAI`, `meta`, `gemini`, `mistral`, `fishAudio`. Preserve that order even when skipping arguments.
8. Remove tests or diagnostics that expect credential/configuration reflection to expose fields. `description`, `debugDescription`, and `customMirror` redact sensitive types. Own any secret persistence in your application; the SDK cannot recover the original secret for a settings form.
9. Update ElevenLabs call sites for Scribe v3. ``ElevenLabsConfiguration`` defaults moved to ``ElevenLabsModelID/scribeV3`` and ``ElevenLabsModelID/scribeV3Live``; pass ``ElevenLabsModelID/scribeV2`` or ``ElevenLabsModelID/scribeV2Realtime`` explicitly to keep the old models. The `.elevenLabs(...)` case of ``SpeechFileTranscriptionOptions`` gained eleven optional arguments, so a `case .elevenLabs(let modelID)` pattern match no longer compiles — match `.elevenLabs` and read ``ElevenLabsFileTranscriptionOptions`` instead. ``ElevenLabsWordTimestamp/start``, ``ElevenLabsWordTimestamp/end``, and ``ElevenLabsWordTimestamp/logprob`` are now optional, and ``ElevenLabsService`` gained ``ElevenLabsService/realtimeOptions`` and ``ElevenLabsService/commitRealtimeSegment()``. With realtime diarization on, committed entries are later split into speaker runs and relabeled by speaker merges, so index ``SpeechService/transcriptEntries`` by ``SpeechTranscriptEntry/id``, not by position or a copied snapshot.

Use `credentialPolicy: .disallowStaticKeys` to forbid static-key operations or `.relayOnly` to require proxy routes. The default stays `.allowStaticKeys`. `resetSession()` clears local session data and pending work by default; `clearCredentials()` additionally releases SDK credential/resolver references and the relay. Neither revokes remote authority. Recording retention defaults to `.retainUntilDiscarded`; opt into `.discardOnStop` or call `discardRecording()` explicitly.

## Replace credentials without reading them

```swift
var configuration = ElevenLabsConfiguration(credential: .apiKey("<USER_SUPPLIED_KEY>"))
configuration.setCredential(.apiKey("<REPLACEMENT_USER_KEY>"))
let kind = configuration.credentialKind
let hasRealtimeCredential = configuration.hasCredential(for: .realtime)
speech.elevenLabs = configuration
```

`apiKey:` initializers still compile, but the property getters/setters and credential enum patterns do not. Do not store UI copies of secrets merely to recreate the old getter behavior.

## Replace token providers by capability

```swift
@MainActor
func migratedOpenAIService(
    fetchToken: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken
) -> SpeechService {
    var configuration = OpenAIConfiguration()
    configuration.setCredential(
        .vendorToken(SpeechTokenResolver { context in try await fetchToken(context) }),
        for: .realtime
    )
    return SpeechService(openAI: configuration, credentialPolicy: .disallowStaticKeys)
}
```

The resolver now receives context. Use `.bearer` instead for custom proxies, and keep OpenAI files on a relay. See <doc:ShippingInProduction> for the complete dated matrix, native-token scope limits, and compiling relay/login/Gemini examples. No silent fallback turns an unsupported native token into an API key.

## Relay upload optimization

``SpeechRelay`` defaults to `optimizedUploads: .on`. It preserves supported compressed audio and mono WAV at 16 kHz or lower, repackages AAC M4A/MP4 without re-encoding when the header or tracks need changing, and converts unsupported imports or higher-rate/multichannel WAV to 16 kHz mono FLAC or PCM16 WAV. Originals and repackaged MP4 output use the same local structural checks as the Worker, including zero-only slack, box allowlists, and a bounded single-entry edit list. Both sides also require exactly one AAC access unit per MP4 sample, verified by AAC syntax validation before upload or forwarding; files that fail convert or are refused as described above. Provider upload-size limits apply after preparation, with separate local source and processing ceilings. Gemini accepts both `.m4a` and `.mp4` suffixes with relay MIME type `audio/m4a`. Provider M4A acceptance is verified against vendor documentation; unverified providers convert. Originals never change, and private temporary files are removed after success, failure or cancellation.

```swift
let relay = SpeechRelay(
    url: URL(string: "https://speech.example.workers.dev")!,
    optimizedUploads: .off
)
```

Use `.off` for original-byte uploads only. Unmeterable containers, AAC needing repackaging, video-bearing files, and formats rejected by the provider fail with `SpeechFailure(.unsupportedMediaType)` before credential resolution or network I/O. See <doc:ShippingInProduction> for format, duration, size, and cleanup rules. Direct provider uploads do not use this setting.

## Handle bounded errors

```swift
let uploadError = SpeechError.uploadFailed(provider: .grok, reason: .uploadFailed)
let serverError = FishAudioRealtimeError.serverError(code: 429)
let closeError = FishAudioRealtimeError.sessionClosed(code: 1008)
let authError = SpeechFailure(.unsupportedAuthentication)
```

Use categories and numeric status in application control flow; never reconstruct raw provider error text. Exhaustive `SpeechError` switches need the new `httpFailure` case. See <doc:ErrorHandling> for cancellation and privacy handling.
