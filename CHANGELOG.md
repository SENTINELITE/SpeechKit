# Changelog

All notable changes to SpeechKit will be documented in this file.

SpeechKit follows semantic versioning. Source-breaking changes ship in a new major version.

## [Unreleased]

## [3.0.0] - 2026-10-30

This release includes the never-published 2.1.0 Mistral and Fish Audio work. The last published version is 2.0.1. Credential access and error payloads change in 3.0.

### Added

- Relay upload optimization passes supported compressed audio and mono WAV at 16 kHz or lower unchanged. Verified providers also accept audio-only AAC M4A/MP4 with a leading `moov` header. AAC with a trailing header, video/extra tracks, or a MOV container uses audio-only AVFoundation passthrough with network optimization, then local MP4 sample-table and byte-range validation. Invalid output falls back to conversion. ALAC and other unsupported imports, plus higher-rate or multichannel PCM WAV, convert to 16 kHz mono FLAC when supported, otherwise canonical PCM16 WAV. OpenAI, Meta, and explicit raw PCM imports use WAV. Protected temporary audio is removed after success, failure, or cancellation; originals never change. Existing 57,600,000 normalized-frame and 128 MiB work limits and tighter provider limits remain. Mistral direct and relay uploads enforce 500,000,000 bytes and 60 minutes.
- `SpeechRelay(optimizedUploads: .on)` enables optimization by default; `.off` uploads original bytes or refuses unsupported imports before network I/O. Vendor M4A acceptance is documented per provider; unverified providers convert. AAC multipart uploads use `audio.m4a` and `audio/mp4`, with Gemini's documented `audio/m4a` exception. The demo persists an Optimize uploads toggle, default on. Relay HTTP 415 `unsupported_media_type` maps to `SpeechFailure.Category.unsupportedMediaType` without retrying audio. Local failures distinguish `audioTooLarge`, `audioTooLong`, and `audioNormalizationFailed`. Direct uploads retain their behavior apart from Mistral's explicit preflight limits.
- SwiftUI `.speechKit(relay:)`, `.speechKit(openAI:…)` and `.speechKit(_:)` view modifiers create a `SpeechService` once, or take an existing one, and place it in the environment for `speechService` and `speechTranscriber`.
- `SpeechRelay` and `SpeechService(relay:)` with built-in App Attest, bearer login, or combined authentication, optional relay SPKI pins, and proxy-first routing. The self-hosted sibling relay template is not yet published.
- `SpeechRelay.appAttestAccountID` namespaces persisted App Attest keys by relay and account. `resetAppAttestKey() async throws` forgets that identity for registration on the next operation, serializing against outstanding assertions. Invalid Apple keys and explicit session attestation rejections get at most one automatic re-registration per operation, without replaying audio or uncertain requests.
- `SpeechService.transcriber` returns `SpeechTranscription`, a transcription-only capability with read-only state/results, listening controls, and file transcription. SwiftUI's new `speechTranscriber` environment value defaults to the existing `speechService` capability. Both existing service access and its environment value remain unchanged.
- `SpeechTokenResolver`, `SpeechTokenContext`, `SpeechAccessToken`, explicit `.vendorToken` and `.bearer` auth modes, and per-capability credential replacement and metadata.
- `SpeechCredentialPolicy`, `GeminiRoute`, bounded `SpeechFailure` and `SpeechFailureReason`, and numeric HTTP failures.
- `resetSession()`, `clearCredentials()`, `discardRecording()`, and `SpeechRecordingRetention` for explicit local cleanup.
- Mistral Voxtral Mini Transcribe 3 and Voxtral Small Transcribe 3 support for file transcription, including speaker diarization, segment timestamps, language pinning, and context biasing.
- Mistral Voxtral Mini Transcribe Realtime 3 support for realtime transcription, including a configurable streaming delay, end-of-turn detection, context biasing, and speaker diarization with optional named speaker references.
- `MistralConfiguration`, `SpeechService.mistral`, and `SpeechService.transcribeMistralAudioFile(file:options:)` with its security-scoped twin, returning `MistralFileTranscriptionResponse` with speaker-labeled segments.
- `MistralRealtimeService` for apps that drive Mistral realtime transcription directly.
- Fish Audio Transcribe 1 Pro support for file transcription, including speaker diarization with speaker count hints, word timestamps, a language hint, and sound cue tags. SpeechKit labels each word with its speaker and copies punctuation from Fish Audio's speaker turns. AIFF and CAF files and audio over 60 minutes are rejected before upload.
- Fish Audio Transcribe Stream 1 support for realtime transcription, in preview, including live drafts, auto, VAD, and manual turn detection, speaker labels, word timestamps, recognition terms, and conversation history.
- `FishAudioConfiguration`, `SpeechService.fishAudio`, and `SpeechService.transcribeFishAudioAudioFile(file:options:)` with its security-scoped twin, returning `FishAudioFileTranscriptionResponse` with the raw segments and speaker turns plus speaker-labeled words.
- `FishAudioRealtimeService` for apps that drive Fish Audio realtime transcription directly, with committed turn metadata, `agentSpeaking(_:)`, `addContext(_:resetHistory:)`, and `finalizeTurn()`.
- ElevenLabs Scribe v3 for file transcription and Scribe v3 Live for realtime transcription, now the defaults. `scribe_v2`, `scribe_v2_medical`, and `scribe_v2_realtime` remain selectable; `scribe_v1` is deprecated because ElevenLabs removes it on July 9, 2026.
- `ElevenLabsFileTranscriptionOptions`, held in `ElevenLabsConfiguration.fileOptions` and overridable per request through the extended `SpeechFileTranscriptionOptions.elevenLabs(...)` case: language and secondary languages, numbers format, diarization with speaker count and threshold, keyterms, audio-event tagging, `noVerbatim`, entity detection, and timeout. Options are validated before upload.
- `ElevenLabsRealtimeOptions`, held in `ElevenLabsConfiguration.realtimeOptions`: language and secondary languages, multilingual mode, a model-aware `commitStrategy` that resolves to turn prediction on Scribe v3 Live and VAD on Scribe v2 Realtime, VAD tuning, realtime diarization, keyterms and the first-chunk keyterm library, `previousText` context, timestamps, language detection, `noVerbatim`, and entity detection. Options are validated before connecting.
- Realtime speaker diarization for Scribe v3 Live: committed segments resolve into one entry per run of the same speaker, and speaker merges rewrite earlier labels in place while entry ids stay stable. `ElevenLabsService.turnProbability` and `SpeechService.realtimeTurnProbability` expose the model's turn-end confidence, `ElevenLabsService.entityDetections` collects detected entities, and `ElevenLabsService.commitRealtimeSegment()` performs a manual commit under the `manual` strategy.
- `ElevenLabsFileTranscriptionResponse` gains `languageProbability`, `audioDurationSeconds`, `transcriptionID`, and `entities`; `ElevenLabsWordTimestamp` gains `speakerID` and `characters`.

### Changed

- `ElevenLabsConfiguration` defaults moved to `scribeV3` and `scribeV3Live`, and gained `fileOptions` and `realtimeOptions`. `transcribeElevenLabsAudioFile` gained an `options:` overload that takes `ElevenLabsFileTranscriptionOptions`; the `modelID:` overloads remain as conveniences.
- `ElevenLabsWordTimestamp.start`, `.end`, and `.logprob` are now optional because audio events and unaligned partial words omit them.
- ElevenLabs realtime server error messages now end the session with `ElevenLabsError.serverError(type:)` instead of being ignored; the vendor's free-text error stays out of `lastError`.
- ElevenLabs file upload limits are raised to 5 GB and 15 hours to match the current service.
- `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions` gained `mistral` and `fishAudio` cases, so exhaustive switches over these types in adopting code need updating. The `.elevenLabs(...)` case gained eleven optional arguments, so pattern matches on its associated values no longer compile.
- `SpeechService.init` gained a `mistral:` parameter after `gemini:`, and a `fishAudio:` parameter after `mistral:`.
- Credentials are opaque values; configurations and realtime services expose metadata and replacement methods instead of credential readback.
- Native auth uses provider-specific placement: ElevenLabs file/realtime query tokens, OpenAI transcription-intent routing, Gemini constrained Live tokens, and Mistral legacy-model subprotocol tokens. Unsupported combinations fail closed.
- Error payloads carry bounded reasons and numeric codes instead of provider-controlled strings. Replacing configuration invalidates pending work; direct realtime services provide async credential/endpoint reconfiguration.

### Removed

- `SpeechTokenProvider`, `.token(...)`, public resolver invocation, credential enum payload matching, and public `apiKey` / `credential` getters and setters. `apiKey:` initializer overloads remain available.
- Arbitrary error text and Fish Audio server-error type/message and session-close type/message fields.

### Security

- SDK-owned ephemeral transports disable caches, cookies, and credential storage; endpoints are validated before credential resolution and redirects are refused. HTTPS/WSS is required except loopback development.
- Credential-bearing diagnostics and reflection are redacted. Response/callback text is not propagated as error detail.
- Relay tickets stay on relay routes. App Attest proofs bind protected requests; native tokens are allocated per operation. Renewal is bounded before side effects, with no automatic audio replay after sending or an uncertain outcome.
- Complete Gemini routes and resource validation prevent partial proxy fallthrough. Meta relay handshakes carry relay authority for server-side replacement, not vendor keys.
- Local policy and lifecycle controls are guardrails, not remote revocation, secure-memory erasure, a device-owner boundary, or proof of production deployment safety.

### Migrating from 2.x

2.0.1 is the last published release. The unreleased 2.1.0 provider additions ship here, so 3.0.0 includes their exhaustive-switch changes as well as the credential and error breaks.

1. Replace `SpeechTokenProvider` with `SpeechTokenResolver`; it is removed, not a deprecated alias. Resolver closures now accept a `SpeechTokenContext`, so a closure that ignores it starts with `{ _ in ... }`. The result can be a `String` or `SpeechAccessToken`. `token()` is gone; call your own backend adapter when your application needs a token outside SpeechKit. Resolver equality still uses its UUID `id`.
2. Replace `.token(...)` with `.vendorToken(resolver)` for supported native tokens or `.bearer(resolver)` for your own proxy and separately authorized Gemini REST OAuth. No public `.relay(...)` factory exists; create `SpeechRelay` instead. Unsupported provider/capability combinations fail before token resolution or vendor I/O. In particular, OpenAI file transcription cannot use a Realtime secret, Fish/Grok STT cannot use agent/voice tokens, and Mistral native-token mode permits only `.voxtralMiniTranscribeRealtime2602`, not Voxtral 3.
3. `SpeechCredential` is now an opaque struct. Remove enum pattern matching, payload extraction, and secret readback. Use `kind` for nonsecret decisions. Configuration and realtime-service `apiKey` properties and public `credential` access are removed. Construct with `credential: .apiKey(...)` and update with `setCredential(_:)`; configuration values also offer `setCredential(_:for:)`, `credentialKind(for:)`, and `hasCredential(for:)`. The `apiKey:` initializer overloads remain supported. `setCredential(_:)` clears both capability overrides; inspect the capability-specific metadata when you use overrides.
4. For direct realtime services, use `await service.reconfigure(credential:realtimeEndpoint:)` when changing credential and endpoint together. The synchronous `setCredential(_:)` and endpoint setters remain, but invalidate active/pending work. For the facade, replace its provider configuration as one value. Setting a configuration to `nil` now cancels that provider's pending work. A credentialed direct override in a relay-backed service needs the explicit endpoint for the selected capability; credential-free configurations inherit the relay.
5. Replace partial Gemini proxy configuration with `GeminiRoute` and `setRoute(_:)`. Supply Interactions, Files upload, and Live endpoints from one origin by default, and keep returned upload URLs and file/interaction poll routes on approved origins. Use `.explicitMixedOrigins` only for a deliberate reviewed direct integration; relay tickets cannot use it. Endpoints must use HTTPS/WSS except loopback development; URL userinfo/fragments and redirects are refused. Custom proxies that depended on redirects must return the final approved URL directly.
6. Update error constructors and switches. `SpeechError.uploadFailed`, `.decodingFailed`, and `.providerFailure` take `SpeechFailureReason` instead of `String`. The same replacement applies to ElevenLabs `connectionFailed`, `decodingFailed`, `audioEngineError`, `uploadFailed`, and `unsupportedModel`; OpenAI `connectionFailed` and `invalidOptions`; Grok/Meta/Mistral `connectionFailed`; Gemini `connectionFailed` and `sessionEnding`; and `SpeechAudioCaptureError.audioEngineError`. Fish Audio `serverError(errorType:code:message:)` becomes `serverError(code:)`, and `sessionClosed(code:errorType:message:)` becomes `sessionClosed(code:)`. Handle the new `SpeechError.httpFailure(provider:statusCode:)` and `SpeechFailure` categories. Do not parse provider bodies, URL-bearing error strings, or arbitrary callback text from errors; they are no longer exposed. Keep cancellation handling separate from failure UI.
7. Add `.mistral` and `.fishAudio` to exhaustive switches on `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions`. `SpeechService` accepts `mistral:` after `gemini:`, then `fishAudio:`, with optional `credentialPolicy:` last. Its provider parameter order is `elevenLabs`, `cohere`, `grok`, `aqua`, `openAI`, `meta`, `gemini`, `mistral`, `fishAudio`. Preserve that order even when skipping arguments.
8. Remove tests or diagnostics that expect credential/configuration reflection to expose fields. `description`, `debugDescription`, and `customMirror` redact sensitive types. Own any secret persistence in your application; the SDK cannot recover the original secret for a settings form.
9. For signed-in App Attest, pass a stable account ID through `SpeechRelay(..., appAttestAccountID:)` and create a service/resolver for each account. `clearCredentials()` preserves persisted attestation identity. If you omit the namespace, stop operations and call `try await relay.resetAppAttestKey()` before changing accounts. Neither method revokes server keys or tickets. Prefer injecting `.environment(\.speechTranscriber, speech.transcriber)` into new views; existing `.speechService` injection still works.

Use `credentialPolicy: .disallowStaticKeys` to forbid static-key operations or `.relayOnly` to require proxy routes. The default stays `.allowStaticKeys`. `resetSession()` clears local session data and pending work by default; `clearCredentials()` additionally releases SDK credential/resolver references and the relay. Neither revokes remote authority. Recording retention defaults to `.retainUntilDiscarded`; opt into `.discardOnStop` or call `discardRecording()` explicitly.

See [Migrating to 3.0](Sources/SpeechKit/SpeechKit.docc/MigratingTo3.md) and [Shipping SpeechKit in production](Sources/SpeechKit/SpeechKit.docc/ShippingInProduction.md) for compiling examples and the dated auth matrix.

## [2.0.1] - 2026-09-15

### Fixed

- ElevenLabs file uploads no longer fail with `metadataReadFailed` when AVFoundation cannot read a file's duration; the duration limit is enforced when the duration is readable, matching the other providers.

## [2.0.0] - 2026-09-15

This is a major release because `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions` gained cases. Every other change is additive.

### Added

- OpenAI `gpt-transcribe` support for file transcription and committed Realtime turns, including plural language hints, keyword hints, and detected-language decoding.
- OpenAI `gpt-live-transcribe` support for low-latency Realtime transcription, including named latency/accuracy delay tiers.
- Demo controls for OpenAI language lists, keywords, and live transcription delay selection.
- Meta Muse Voice Transcribe support for file transcription and realtime transcription, including push-to-talk, endpointing, and diarization modes, language-name biasing, keyword hints, and cumulative or delta partials.
- Gemini 3.5 Transcribe support for file transcription, including speaker labels, word timestamps, Gemini Files API upload for large recordings, and background processing with polling for long recordings.
- Gemini 3.5 Transcribe Live support for realtime transcription.
- Demo controls for Meta and Gemini provider selection, API keys, modes, language hints, keywords, and Gemini diarization, word timestamp, and background processing toggles.
- `SpeechService` extension storage (`SpeechServiceExtensionKey` and the `extension:` subscript) so separate packages such as SpeechKit-Voz can attach state to a service.
- `SpeechCredential` and `SpeechTokenProvider` for short-lived provider tokens, with `init(credential:)` on every keyed configuration and realtime service. SpeechKit resolves a token provider once per file request and once per realtime session.
- `SpeechService.transcribeElevenLabsAudioFile(file:modelID:)` and its security-scoped twin, returning the now-public `ElevenLabsFileTranscriptionResponse` with word-level timings.
- Per-provider endpoint overrides: `fileEndpoint` on every keyed configuration, `realtimeEndpoint` for ElevenLabs, OpenAI, Grok, Meta, and Gemini, and `filesEndpoint` for the Gemini Files API upload URL, so apps can route provider traffic through their own proxy.

### Changed

- OpenAI configuration defaults now use `gpt-transcribe` for files and `gpt-live-transcribe` for Realtime transcription.
- ElevenLabs configuration now defaults file transcription to `scribe_v2`.
- Gemini Live token connections now send the credential in an `Authorization: Token` header instead of the socket URL. API-key connections still use the `key` query parameter.
- `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions` gained `meta` and `gemini` cases, so exhaustive switches over these types in adopting code need updating.
- `apiKey` on every provider configuration and realtime service is now a computed projection of the new `credential` property: reading it returns the key of an `.apiKey` credential and an empty string for a `.token` credential, and writing it replaces `credential` with `.apiKey`.
- Token-backed configurations compare equal by `SpeechTokenProvider.id`.

### Deprecated

- OpenAI `whisper-1`, `gpt-4o-transcribe`, `gpt-4o-mini-transcribe` (including the `2025-12-15` snapshot), and `gpt-4o-transcribe-diarize` model IDs, which OpenAI shuts down on February 26, 2027. Use `gpt-transcribe` or `gpt-live-transcribe`.
- OpenAI `gpt-4o-transcribe-latest` Realtime model ID, which OpenAI no longer documents.
- ElevenLabs `scribe_v1`, which ElevenLabs scheduled for removal on July 9, 2026. Use `scribe_v2`.

### Fixed

- Realtime services now ignore duplicate session-established messages instead of restarting audio capture, which previously left two consumers reading one audio stream.
- Meta keyword validation now rejects CRLF line breaks.
- `GeminiConfiguration.realtimeModelID` was ignored; `SpeechService` now applies it over `GeminiRealtimeOptions.modelID` when configuring or starting a Gemini Live session.
- Gemini realtime transcripts no longer collapse two identical consecutive utterances into one entry, and a repeated `setupComplete` acknowledgement no longer orphans the first audio task.
- Gemini realtime errors are redacted before publication so an API key carried in the Live socket URL cannot reach `lastError`.
- Cancelling a Gemini background transcription or Files API upload now rethrows `CancellationError` instead of a provider failure.
- Meta raw PCM uploads are duration-checked from their byte count before upload, since AVFoundation cannot measure headerless audio.
- Grok, Meta, and Gemini realtime services compile under Xcode 26.2 again: the graceful-stop wait no longer captures the service in a nonisolated child task, which that compiler reported as a data race.

## [1.0.0] - 2026-05-31

### Added

- Provider-neutral `SpeechService` facade for realtime microphone transcription and audio file transcription.
- Realtime transcription support for ElevenLabs, OpenAI, and xAI Grok.
- File transcription support for ElevenLabs, Aqua, Cohere, Grok, and OpenAI.
- OpenAI diarization options for `gpt-4o-transcribe-diarize`, including automatic chunking, server VAD tuning, known speaker references, and diarized segment decoding.
- DocC documentation for getting started, provider configuration, realtime transcription, file transcription, error handling, and security-scoped files.
- SpeechKit Demo app for trying realtime transcription, recorded dictation uploads, file transcription, provider selection, and API-key settings on device.
- GitHub Actions CI for SwiftPM build/test and generic platform builds across macOS, iOS, watchOS, and visionOS.

### Changed

- Hardened realtime start/stop behavior so duplicate starts, stops, provider switches, and stale async callbacks are handled safely.
- Removed underscored Foundation re-exports from the public module surface.

### Security

- Documented that provider API keys should not be shipped directly in distributed client apps.
