# SpeechKit

[![CI](https://github.com/SENTINELITE/SpeechKit/actions/workflows/ci.yml/badge.svg)](https://github.com/SENTINELITE/SpeechKit/actions/workflows/ci.yml)
![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%20%7C%20macOS%2015%20%7C%20watchOS%2011%20%7C%20visionOS%202-lightgrey.svg)
![Status](https://img.shields.io/badge/status-3.0.0-blue.svg)

SpeechKit is a Swift package for adding speech-to-text to Swift and SwiftUI apps with a small async/await API.

It supports two workflows:

- Realtime microphone transcription with ElevenLabs, OpenAI, xAI Grok, Meta, Gemini, Mistral, Fish Audio, and Apple local Speech on supported OS versions.
- File transcription with ElevenLabs, Aqua, Cohere, Grok, OpenAI, Meta, Gemini, Mistral, Fish Audio, and Apple local Speech on supported OS versions.

## Highlights

- One `SpeechService` facade for SwiftUI apps.
- Provider-neutral realtime transcript state.
- Provider-neutral file transcription for simple text results.
- Provider-specific options and detailed responses when you need timestamps, diarization, usage metadata, or model-specific controls.
- ElevenLabs Scribe v3 for file uploads and Scribe v3 Live for realtime sessions, with speaker diarization, turn prediction, keyterms, and entity detection.
- Meta Muse Voice Transcribe and Gemini 3.5 Transcribe for both realtime sessions and file uploads.
- Mistral Voxtral Transcribe 3 for realtime sessions and file uploads, with speaker diarization you can turn on per request or per session.
- Fish Audio Transcribe 1 Pro for file uploads and Transcribe Stream 1 (in preview) for realtime sessions, with speaker labels and word timings.
- On-device Apple Speech support for apps running on iOS 26, macOS 26, or visionOS 26.
- Security-scoped file overloads for document picker workflows.
- A runnable iOS demo app for trying realtime transcription, recorded dictation uploads, and file transcription.

## Status

SpeechKit `3.0.0` is the release documented here. It includes the never-published 2.1.0 Mistral and Fish Audio work, opaque credentials, explicit auth modes, and the relay client. The previous release was 2.0.1. See [the changelog](CHANGELOG.md) for source breaks and migration steps.

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
4. Select version `3.0.0` or later within the 3.x line, then add the `SpeechKit` library to your app target.

For a package manifest:

```swift
.package(url: "https://github.com/SENTINELITE/SpeechKit.git", from: "3.0.0")
```

Then import it where you need speech features:

```swift
import SpeechKit
```

## Command-line tool

Use the [speechkit CLI](https://github.com/SENTINELITE/speechkit-cli) to
transcribe files from the terminal, compare providers, and export text, JSON,
SRT, or WebVTT. Download the Apple Silicon build for macOS 15 or later from
[GitHub Releases](https://github.com/SENTINELITE/speechkit-cli/releases).

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

Choose who owns the vendor account before choosing an auth mode:

- **Bring your own key:** the user supplies a key for their own vendor account. Use `.apiKey(...)`, keep it out of logs, and store it in Keychain if it must persist. Never bundle your app's vendor key.
- **Native vendor token:** your authenticated backend mints a short-lived token for a documented provider, capability, and model. Use `.vendorToken(SpeechTokenResolver { ... })` only for supported rows below.
- **SpeechKit Relay:** your app pays for transcription, or the provider has no suitable native token. Keep vendor keys on a relay you deploy and enforce authorization, quotas, model allowlists, and retention there. Fetching a permanent vendor key from a backend does not make shipping it to clients safe.

### Start with a relay

In a SwiftUI app, one modifier creates the service and places it in the environment:

```swift
import SpeechKit
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .speechKit(relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!))
        }
    }
}

struct ContentView: View {
    @Environment(\.speechTranscriber) private var speech

    var body: some View {
        Button("Listen") { Task { await speech.startListening(provider: .openAI) } }
    }
}
```

`.speechKit(...)` creates the service once and keeps it for the life of that view, like `@State`; later argument changes are ignored. It also accepts direct provider configurations, such as `.speechKit(openAI: OpenAIConfiguration(credential: .apiKey(savedKey)))`, or an existing service with `.speechKit(service)`. Settings screens can read `@Environment(\.speechService)` to change configuration. Outside SwiftUI, create the service directly:

```swift
let speech = SpeechService(relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!))
```

The sibling [speechkit-relay repository](https://github.com/SENTINELITE/speechkit-relay) is a self-hosted Cloudflare Worker template, **not yet published**. Until publication, use the local `../speechkit-relay` checkout. Its [README](../speechkit-relay/README.md) covers deployment and login configuration; its [contract](../speechkit-relay/docs/CONTRACT.md) defines routes and request proofs. This snippet does not deploy or validate a server.

App Attest and `.proxyAll` are the defaults. SpeechKit registers the device key, obtains a short-lived relay ticket, and adds fresh proofs to protected requests and WebSocket upgrades. Enable the entitlement and configure your app identity on the server. Unsupported devices fail closed; explicitly choose bearer authentication if your product allows that fallback. `.none` is for loopback development only, with the template's `none-dev` mode and explicit insecure-development setting. Do not expose it publicly.

Relay file uploads must contain PCM/IEEE-float WAV, FLAC, Ogg Opus/Vorbis, MP3, or the relay's restricted AAC M4A/MP4 subset, and the target provider must accept the format. SpeechKit detects containers from bytes. `SpeechRelay(url: relayURL, optimizedUploads: .on)` is the default. Supported compressed audio and mono WAV at 16 kHz or lower pass through unchanged. AAC requires one audio track and a `moov` header before `mdat`. Local MP4 checks mirror the Worker's structural rules, including box allowlists, aligned `ftyp`, codec descriptors, sample tables, nonoverlapping byte ranges, at most 64 all-zero unreferenced bytes, and an optional single nonnegative unit-rate edit contained within the media timeline. AAC needing layout or track changes is repackaged using AVFoundation passthrough, keeping only the first audio track and moving the header ahead of audio. Repackaged output must pass that validator or conversion takes over. Server-configured limits still apply independently.

Each MP4 sample must contain exactly one AAC-LC access unit (`raw_data_block`), checked by an AAC syntax walker before the sample is accepted locally or forwarded by the Worker. Duration is billed as 1,024 samples per access unit at the core rate. This is syntax validation, not full decoding: SBR/PS extension payloads are skipped by length, 960-sample configurations are rejected, and samples over 8,192 bytes are rejected. Files that fail convert on-device when optimization is on, or fail with `unsupportedMediaType` before any network request when it is off.

ALAC, CAF, AIFF, WebM and other unmeterable or unaccepted formats, failed AAC repackaging, and PCM WAV above 16 kHz or with multiple channels convert to 16 kHz mono FLAC when the provider and local encoder support it, otherwise PCM16 WAV. OpenAI, Meta, and explicit raw PCM imports use WAV for conversion. Provider upload-size limits apply to the prepared output, not a larger source that needs conversion. Local imports have a separate 512 MiB source-byte ceiling; conversion and repackaging are bounded to one hour and 128 MiB of output. Mislabeled supported audio receives a correctly named temporary copy only when optimization is on. Originals are never modified. Temporary files retain owner-only permissions, platform file protection, and cleanup after success, failure or cancellation.

AAC/M4A acceptance was checked against official documentation on October 30, 2026. Unverified providers convert rather than assuming support. Multipart uploads use `audio.m4a` and `audio/mp4`; Gemini uses its documented `audio/m4a` MIME type.

| Provider | AAC/M4A uploads | Official documentation |
| --- | --- | --- |
| OpenAI | Verified | [Speech to text](https://developers.openai.com/api/docs/guides/speech-to-text) |
| ElevenLabs | Verified | [Transcription formats](https://elevenlabs.io/docs/overview/capabilities/speech-to-text) |
| Grok | Verified | [Speech to text formats](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text) |
| Aqua | Verified | [Transcription API](https://aquavoice.com/docs/api) |
| Gemini | Verified, `audio/m4a` | [Audio understanding](https://ai.google.dev/gemini-api/docs/audio) |
| Fish Audio | Verified | [Input audio](https://docs.fish.audio/features/speech-to-text#input-audio) |
| Mistral | Not verified; converts | [Audio formats](https://docs.mistral.ai/studio/audio/specs-and-limits/audio-formats) |
| Cohere | Not verified; converts | [Transcription API](https://docs.cohere.com/reference/create-audio-transcription) |
| Meta | WAV-only | [Speech to text](https://dev.meta.ai/docs/speech-to-text/) |

Meta `PCM_16KHZ`/`PCM_24KHZ` and Grok mono 16-bit little-endian PCM imports become WAV, with raw-decoder request options removed. Grok mu-law, A-law, and multichannel raw modes are refused. Set `SpeechRelay(url: relayURL, optimizedUploads: .off)` to upload original bytes only, or reject unsupported content before credential resolution or network I/O with `SpeechFailure.Category.unsupportedMediaType`. This also refuses AAC requiring repackaging and video-bearing files. Meterable high-rate or stereo WAV remains unchanged with optimization off. A relay HTTP 415 with error code `unsupported_media_type` has the same category and is not retried. Direct provider uploads are unaffected.

Conversion runs off the main actor, supports cancellation, and removes protected temporary files after success or error. It never changes or removes the source file. WAV conversion writes a canonical 44-byte PCM16 header with only `fmt ` and `data` chunks, without Apple's `FLLR` padding. Generated and pass-through WAV files are checked against the relay's strict RIFF grammar locally before upload, not just reopened with AVFoundation.

Every relay import has an unconditional 57,600,000-output-frame ceiling at 16 kHz, equivalent to 60 minutes, and a 128 MiB output-file and decoded-PCM byte ceiling. Conversion checks actual input/output frames and output bytes incrementally; provider limits can be tighter. These checks run before whole-file upload reads. OpenAI retains its 25 MiB upload limit; Meta retains 32 MiB and ten minutes. Mistral now enforces 500,000,000 bytes and 60 minutes for direct and relay uploads, based on its published known limitations. `audioTooLarge`, `audioTooLong`, and `audioNormalizationFailed` are safe relay `SpeechFailure` categories. Only formats AVFoundation can decode locally can be normalized. Relay quotas, multipart/base64 overhead, and independent server validation can impose tighter limits. Other direct credentials, including native vendor-token uploads, keep their previous behavior.

Use an existing login with App Attest when you need per-user quotas. The closure is your adapter to a Convex Auth, Clerk, or other login client, not an API supplied by SpeechKit:

```swift
@MainActor
func makeAuthenticatedSpeechService(
    accountID: String,
    fetchLoginJWT: @escaping @Sendable () async throws -> String
) -> SpeechService {
    SpeechService(
        relay: SpeechRelay(
            url: URL(string: "https://speech.example.workers.dev")!,
            authentication: .appAttestAndBearer(SpeechTokenResolver { _ in
                try await fetchLoginJWT()
            }),
            appAttestAccountID: accountID
        ),
        credentialPolicy: .relayOnly
    )
}
```

For bearer-only login, use `.bearer(resolver)` on `SpeechRelay` and `AUTH_MODE=bearer` on the server. Combined login uses `AUTH_MODE=both`. Validate JWT signature, issuer, audience, expiry, and subject. Clerk may require a JWT template with an explicit audience; match Convex Auth's actual issuer and JWKS settings rather than copying placeholders blindly.

Use a stable, nonsecret account ID, scoped to your login issuer, and rebuild the service when switching accounts. The Keychain lookup hashes that ID together with the relay URL. The relay permanently binds each key to its first subject. `clearCredentials()` preserves local attestation identity so signing back into the same account can reuse it. With no account ID, stop operations and call `try await relay.resetAppAttestKey()` before switching accounts. Reset forgets the local identifier, waits for outstanding assertions, and registers a new key on next use. It does not revoke server keys, tickets, or active sessions. Apple invalid-key errors and explicit `/session` attestation rejections allow one automatic re-registration per operation. Uploaded audio and uncertain requests are never replayed for this recovery.

### Give views only transcription access

Keep the `SpeechService` and credential configuration at your composition root. New views can receive only `SpeechTranscription`:

```swift
import SwiftUI
import SpeechKit

@MainActor
struct TranscriptionView: View {
    @Environment(\.speechTranscriber) private var transcriber

    var body: some View {
        VStack {
            Text(transcriber.transcriptText)
            Text(transcriber.partialTranscriptText)
            Button("Listen") {
                Task { await transcriber.startListening(provider: .openAI) }
            }
            Button("Stop") {
                Task { await transcriber.stopListening() }
            }
        }
    }
}

@MainActor
func transcriptionContent(speech: SpeechService) -> some View {
    TranscriptionView().environment(\.speechTranscriber, speech.transcriber)
}
```

`SpeechTranscription` also exposes read-only `connectionState`, `transcriptEntries`, and `lastError`, plus `transcribeAudioFile(provider:file:options:)` and its `securityScopedURL:` overload, returning text. It exposes no service, credential, relay, or configuration setters. Observed reads still update SwiftUI. Existing `@Environment(\.speechService)` behavior is unchanged; without explicit narrow injection, `speechTranscriber` uses that service's capability.

### Verified auth matrix

Provider contracts reviewed on **2026-10-29**; SDK placement checked against the local 3.0 source on **2026-10-30**. This is documentation and request-builder evidence, not an authenticated vendor canary or proof of a deployed relay. "None documented" applies to the named STT route, not every product from that vendor.

| Provider / capability | Native token and lifetime | SpeechKit 3.0 placement |
| --- | --- | --- |
| ElevenLabs file | `POST /v1/single-use-token/batch_scribe`; 15 minutes, single use | `.vendorToken`, `?token=<token>` on `/v1/speech-to-text` |
| ElevenLabs realtime | `POST /v1/single-use-token/realtime_scribe`; 15 minutes, single use | `.vendorToken`, `?token=<token>` on `/v1/speech-to-text/realtime`; reconnect needs a fresh token |
| OpenAI file | None documented for `/v1/audio/transcriptions` | `.apiKey`, `Authorization: Bearer`; Realtime secrets do not authorize files |
| OpenAI realtime transcription | `POST /v1/realtime/client_secrets` with `session.type: "transcription"`; default 600 seconds, configurable 10–7200, reusable until expiry | `.vendorToken`, `Authorization: Bearer` on `/v1/realtime?intent=transcription`, without a model query |
| Gemini file / Files API | Live tokens are unsupported; Google OAuth is a separate IAM contract | `.apiKey`, `x-goog-api-key`; `.bearer` for separately authorized Google OAuth, `Authorization: Bearer` |
| Gemini Live | `POST /v1beta/auth_tokens`; default 60 seconds to start, 30 minutes for messages, one use; constraints can lock setup fields | `.vendorToken`, `Authorization: Token` on `v1beta/...GenerativeService.BidiGenerateContentConstrained` |
| Mistral file | None documented for `/v1/audio/transcriptions` | `.apiKey`, `Authorization: Bearer` |
| Mistral realtime | `POST /v1/client/sessions`, realtime purpose and model; about 900 seconds, reusable, model-scoped | `.vendorToken`, `Sec-WebSocket-Protocol: realtime, <token>`; SDK allows only `.voxtralMiniTranscribeRealtime2602`, not Voxtral 3 |
| Grok file / streaming STT | None documented for HTTP or WebSocket `/v1/stt`; voice `/v1/realtime` client secrets are a different contract | `.apiKey`, `Authorization: Bearer`; use a relay for app-owned authority |
| Fish Audio file / realtime | None documented for `/v1/asr` or `/v1/asr/realtime`; agent-session tokens are unrelated | `.apiKey`, `Authorization: Bearer`; use a relay for app-owned authority |
| Meta file | None documented for `/v1/asr/transcribe` | `.apiKey`, `Authorization: Bearer` |
| Meta realtime | None documented for `/v1/asr/realtime` | `.apiKey`, first JSON frame `authorization.accessToken = "Bearer <key>"`; relay replaces that field, HTTP auth alone is insufficient |
| Cohere file | None documented for `/v2/audio/transcriptions` | `.apiKey`, `Authorization: Bearer`; no realtime client |
| Aqua file | None documented for Avalon transcription | `.apiKey`, `Authorization: Bearer`; SDK and relay use `/v1/audio/transcriptions`; no realtime client |
| Apple local Speech | No credential | On-device transcription on supported OS versions |

ElevenLabs static keys use `xi-api-key`. Gemini Live static keys use the `key` query on the non-constrained method; a native token uses the header and constrained method instead. TLS protects query strings in transit, but request URLs can still reach client, proxy, or server logs. Never log credential-bearing URLs.

Mint native tokens on an authenticated backend with the vendor key held there. Check provider, capability, model, and permitted destinations before issuing a token. Expiry is not a session-duration limit: an established session may outlive the token. OpenAI session settings remain client-overridable; a token is not an immutable spend cap. Gemini's configurable timestamps must each be less than 20 hours ahead; `uses: 0` permits unlimited uses, and session resumption does not consume another use. Mistral's documented native-token contract covers the legacy 2602 model; keep Voxtral 3 on the relay until that contract is verified.

References for the dated review: [ElevenLabs tokens](https://elevenlabs.io/docs/api-reference/tokens/create), [OpenAI Realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription), [Gemini ephemeral tokens](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens), [Mistral realtime authentication](https://docs.mistral.ai/studio/audio/speech_to_text/realtime_transcription/client_auth), [xAI STT](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text), [Fish Audio STT](https://docs.fish.audio/api-reference/endpoint/openapi-v1/speech-to-text), [Meta STT](https://dev.meta.ai/docs/speech-to-text/), [Cohere transcription](https://docs.cohere.com/reference/create-audio-transcription), and [Aqua API](https://aquavoice.com/docs/api).

### Native tokens and credential replacement

Provide separate file and realtime credentials when only one capability accepts a native token. This example accepts an application-owned token-fetching function so it does not assume a particular backend SDK:

```swift
@MainActor
func makeOpenAIRealtimeService(
    fetchTranscriptionSecret: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken
) -> SpeechService {
    var configuration = OpenAIConfiguration()
    configuration.setCredential(
        .vendorToken(SpeechTokenResolver { context in
            try await fetchTranscriptionSecret(context)
        }),
        for: .realtime
    )
    return SpeechService(openAI: configuration, credentialPolicy: .disallowStaticKeys)
}
```

The file credential above is empty, so it cannot upload a file. Use a relay for OpenAI files. Resolvers receive provider, capability, model, operation ID, attempt, auth mode, and approved destinations. Return `SpeechAccessToken(value:expiresAt:isReusable:)` when you know expiry and reuse metadata, or return a `String`. Metadata does not enforce server-side reuse, and SpeechKit provides no public token readback or resolver invocation. Keep captured login/session objects alive only as long as needed; clearing the SDK's credentials cannot release copies held by your app.

For a configuration value, use `setCredential(_:)` to replace the base credential and clear both capability overrides. Use `setCredential(_:for:)` to replace only one capability. Inspect `credentialKind`, `hasCredential`, or their `for:` variants, never a secret getter.

### Custom proxy routes and local policy

Use `.bearer(SpeechTokenResolver { ... })` for your own proxy, not `.vendorToken` or `.apiKey` carrying a proxy ticket. Set every endpoint used by that capability. `GeminiRoute` validates the complete Interactions, Files API, and Live route:

```swift
@MainActor
func makeProxyService(
    fetchProxyToken: @escaping @Sendable () async throws -> String
) throws -> SpeechService {
    var gemini = GeminiConfiguration(
        credential: .bearer(SpeechTokenResolver { _ in try await fetchProxyToken() })
    )
    try gemini.setRoute(GeminiRoute(
        interactions: URL(string: "https://api.example.com/gemini/v1beta/interactions")!,
        files: URL(string: "https://api.example.com/gemini/upload/v1beta/files")!,
        realtime: URL(string: "wss://api.example.com/gemini/live")!
    ))
    return SpeechService(gemini: gemini, credentialPolicy: .disallowStaticKeys)
}
```

A custom proxy must also keep returned upload-session URLs, file polling, and interaction polling on approved destinations, bind resources to their user, and replace Meta's first-frame authorization. Partial Gemini overrides fail validation. `GeminiRoute.OriginPolicy.explicitMixedOrigins` is an explicit exception for reviewed direct integrations, not for relay tickets. SpeechKit validates HTTPS/WSS endpoints before resolving credentials and refuses redirects; only loopback HTTP/WS is allowed for development.

With a relay, an empty provider credential inherits the relay. A configured direct credential requires that capability's explicit endpoint and wins over the relay; a missing endpoint fails instead of sending the credential elsewhere. `.disallowStaticKeys` rejects static-key operations, while `.relayOnly` rejects direct credentials and keeps traffic on proxy routes even if native-token strategy was selected. These are local guardrails, not protection against a modified client. The default remains `.allowStaticKeys` for BYOK compatibility.

`tokenStrategy: .vendorTokensWhenAvailable` asks the relay to mint a native token for supported combinations; unsupported combinations or a 404 use the proxy. Other mint failures do not silently downgrade to a vendor key. Keep `.proxyAll` for central quota/retention control. No audio is automatically replayed after sending it or after an uncertain outcome.

### Reset, revocation, and privacy

```swift
speech.recordingRetention = .discardOnStop
await speech.resetSession()
speech.discardRecording()
await speech.clearCredentials()
```

`stopListening()` ends capture but can retain results. `resetSession()` cancels local work, clears cached relay tickets, and discards transcript and recording by default; it keeps configuration and resolver captures. `discardRecording()` drops SDK-owned audio, not caller-owned files. `clearCredentials()` also releases configured credentials and resolver captures and removes the relay. None revokes a vendor key, JWT, issued relay ticket, or App Attest registration, deletes vendor/relay data, or guarantees zeroing all copies in memory. Revoke and rotate on the server, sign out the login client, and delete application-owned files separately.

Keychain helps protect data at rest; it cannot hide a key from a process allowed to read it. App Attest gives the relay an app/device authenticity signal and request proofs, not user identity, consent, immunity to runtime hooks, or a hard spend limit. Configure server-side replay checks, quotas, concurrency/duration limits, redacted logging, and retention/deletion policy. Review device behavior and run authorized vendor canaries before release; compiling these examples does not prove either.

See [Shipping SpeechKit in production](Sources/SpeechKit/SpeechKit.docc/ShippingInProduction.md) and [Migrating to 3.0](Sources/SpeechKit/SpeechKit.docc/MigratingTo3.md) for deployment and source migration details. Provider-key examples below are for BYOK or local testing only.

## Chapter 1: Create a Speech Service

Create one `SpeechService` with the provider configurations your app needs. You do not need to configure every provider. `SpeechService` is the recommended integration point for apps; provider-specific realtime services are available for advanced direct integrations when you need to bypass the central facade.

```swift
import SpeechKit
import SwiftUI

@main
struct DemoApp: App {
    @State private var speech = SpeechService(
        elevenLabs: ElevenLabsConfiguration(credential: .apiKey("<ELEVENLABS_API_KEY>")),
        grok: GrokConfiguration(credential: .apiKey("<XAI_API_KEY>")),
        openAI: OpenAIConfiguration(credential: .apiKey("<OPENAI_API_KEY>"))
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
            preparesAssetsAutomatically: true,
            contextualStrings: ["SpeechKit"]
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

ElevenLabs defaults to Scribe v3 Live, which commits each segment with turn prediction. Call `startListening(provider: .elevenLabs)`; calling `startListening()` without a provider also starts ElevenLabs.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        credential: .apiKey("<ELEVENLABS_API_KEY>"),
        realtimeModelID: .scribeV3Live,
        realtimeOptions: ElevenLabsRealtimeOptions(
            diarize: true,
            keyterms: ["SpeechKit"]
        )
    )
)

await speech.startListening(provider: .elevenLabs)
```

With diarization on, each committed segment resolves into one entry per run of the same speaker, labeled `speaker_0`, `speaker_1`, and so on. Later speaker merges rewrite earlier labels in place while entry ids stay stable. `realtimeTurnProbability` reports the model's turn-end confidence on every partial. `ElevenLabsRealtimeOptions` also covers the commit strategy (`manual`, `vad`, `turnPrediction`, or the model-aware `automatic`), VAD tuning, language hints with multilingual mode, a session `keytermLibrary`, `previousText` context, `noVerbatim`, and entity detection — all validated before the socket opens.

### Realtime: OpenAI

OpenAI defaults to `gpt-live-transcribe` for low-latency microphone transcription. Use `gpt-transcribe` for committed Realtime turns when detected languages are required. Both models accept a prompt, keyword hints, and multiple expected input languages.

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        credential: .apiKey("<OPENAI_API_KEY>"),
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
        credential: .apiKey("<XAI_API_KEY>"),
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

### Realtime: Meta

Meta Muse Voice Transcribe streams raw PCM. `MetaRealtimeOptions` sets the mode, the partial delivery style, the language bias, and keyword hints.

```swift
let speech = SpeechService(
    meta: MetaConfiguration(
        credential: .apiKey("<META_API_KEY>"),
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

Meta realtime sessions accept 24 kHz or 16 kHz mono PCM only. Use `.cumulative` partials when each event should carry the full turn text, and `.delta` when you want only the new words.

### Realtime: Gemini

Gemini 3.5 Transcribe Live streams 16 kHz mono PCM through the Gemini Live API. `GeminiRealtimeOptions` sets the language hints, custom vocabulary, and transcription mode.

```swift
let speech = SpeechService(
    gemini: GeminiConfiguration(
        credential: .apiKey("<GOOGLE_API_KEY>"),
        realtimeOptions: GeminiRealtimeOptions(
            languageCodes: ["en-US"],
            customVocabulary: ["SpeechKit"],
            mode: .verbatim
        )
    )
)

await speech.startListening(provider: .gemini)
```

Gemini Live sessions last up to 10 minutes and do not return speaker labels or word timestamps. Use file transcription when you need either one.

### Realtime: Mistral

Mistral Voxtral Mini Transcribe Realtime 3 streams 16-bit mono PCM. `MistralRealtimeOptions` sets the streaming delay, language, context biasing, turn detection, and diarization.

```swift
let speech = SpeechService(
    mistral: MistralConfiguration(
        credential: .apiKey("<MISTRAL_API_KEY>"),
        realtimeOptions: MistralRealtimeOptions(
            targetStreamingDelayMilliseconds: 480,
            language: "en",
            contextBias: ["SpeechKit", "Northwind"]
        )
    )
)

await speech.startListening(provider: .mistral)
```

By default, Mistral detects the end of each turn and SpeechKit commits one transcript entry per turn. Set `diarize` to label each entry with its speaker:

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
speech.mistral?.realtimeOptions.diarize = true
await speech.startListening(provider: .mistral)

for entry in speech.transcriptEntries {
    print(entry.speaker ?? "?", entry.text)
}
```

Mistral cannot combine diarization with turn detection, so with `diarize` on SpeechKit leaves turn detection out and starts a new entry each time the speaker changes. Add `speakerReferences` (up to 8 clips of 3 to 15 seconds) to label known voices by name instead of `speaker_1`, `speaker_2`. Mistral locks the settings when the first audio chunk arrives, so a change applies to the next session.

### Realtime: Fish Audio

Fish Audio Transcribe Stream 1 streams 16-bit mono PCM, 16 kHz by default. The realtime model is in preview, so its behavior may change. `FishAudioRealtimeOptions` sets turn detection, live drafts, word timings, diarization, and recognition terms.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    fishAudio: FishAudioConfiguration(
        credential: .apiKey("<FISH_AUDIO_API_KEY>"),
        realtimeOptions: FishAudioRealtimeOptions(
            mode: .auto,
            terms: ["SpeechKit", "Northwind"]
        )
    )
)

await speech.startListening(provider: .fishAudio)

for entry in speech.transcriptEntries {
    print(entry.speaker ?? "?", entry.text)
}
```

Fish Audio transcribes turn by turn. The open turn's latest draft is the partial entry, and each committed turn becomes one final entry per speaker, labeled `speaker:0`, `speaker:1`, and so on. Diarization, drafts, and word timings are on by default.

In `.auto` mode Fish Audio marks other voices and noise as non-user turns. SpeechKit keeps them, so a transcript of a room still includes everyone. `SpeechService` does not report turn kinds. If you only want the user's turns, drive a `FishAudioRealtimeService` directly and read `kind` from `committedTurns` or `turn(for:)`. Use `.vad` to end turns after a silence, or `.manual` with `FishAudioRealtimeService.finalizeTurn()` for push-to-talk.

Fish Audio bills a realtime session for every second the socket is open, idle time included. Call `stopListening()` as soon as you are done. Sessions last up to 60 minutes.

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

    try await speech.prepareAppleSpeechAssets()
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

Use ElevenLabs Scribe v3 for file transcription, with speaker diarization, keyterms, audio-event tagging, number formatting, and entity detection.

```swift
let speech = SpeechService(
    elevenLabs: ElevenLabsConfiguration(
        credential: .apiKey("<ELEVENLABS_API_KEY>"),
        fileTranscriptionModelID: .scribeV3
    )
)

let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    file: audioFileURL,
    options: .elevenLabs(diarize: true, keyterms: ["SpeechKit"])
)
```

Call `transcribeElevenLabsAudioFile(file:options:)` instead when you need the detailed `ElevenLabsFileTranscriptionResponse`, which carries the detected `languageCode` and `languageProbability`, word-level timings with `speakerID` labels, audio events, and detected `entities`.

### File: Aqua

Use Aqua when you want Avalon file transcription with a typed language hint.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    aqua: AquaConfiguration(
        credential: .apiKey("<AQUA_API_KEY>"),
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
        credential: .apiKey("<COHERE_API_KEY>"),
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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    grok: GrokConfiguration(
        credential: .apiKey("<XAI_API_KEY>"),
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

OpenAI file transcription defaults to `gpt-transcribe`, which supports prompts, keyword hints, multiple expected input languages, and detected-language output. Whisper remains available for timestamps, and `gpt-4o-transcribe-diarize` remains available for speaker labels, but both are deprecated because OpenAI shuts them down on February 26, 2027.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    openAI: OpenAIConfiguration(
        credential: .apiKey("<OPENAI_API_KEY>"),
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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

### File: Meta

Meta Muse Voice Transcribe accepts WAV uploads up to 32 MB and 10 minutes. The provider-neutral API returns text:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .meta,
    file: audioFileURL,
    options: .meta(mode: .diarization, languageBias: [.english])
)
```

Use the detailed call when you want per-turn timings and speaker labels.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    meta: MetaConfiguration(
        credential: .apiKey("<META_API_KEY>"),
        mode: .diarization,
        languageBias: [.english],
        keywords: ["SpeechKit", "AC-42"]
    )
)

let response = try await speech.transcribeMetaAudioFile(file: audioFileURL)
print(response.transcript)
for turn in response.turns ?? [] {
    print(turn.speaker ?? "?", turn.startMs, turn.endMs, turn.transcript)
}
```

Meta biases transcription with language names such as `"English"` or `"Mandarin Chinese"` instead of BCP-47 codes.

### File: Gemini

Gemini 3.5 Transcribe accepts up to one hour of audio, or 30 minutes when diarization or word timestamps are on. The provider-neutral API returns text:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .gemini,
    file: audioFileURL,
    options: .gemini(languageCodes: ["en-US"])
)
```

Use the detailed call when you want speaker labels and word timestamps.

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    gemini: GeminiConfiguration(
        credential: .apiKey("<GOOGLE_API_KEY>"),
        languageCodes: ["en-US"],
        mode: .verbatim,
        diarize: true,
        timestampGranularities: [.word]
    )
)

let response = try await speech.transcribeGeminiAudioFile(file: audioFileURL)
print(response.text)
for word in response.words {
    print(word.text, word.speaker ?? "?", word.start ?? 0, word.end ?? 0)
}
```

Gemini rejects a custom vocabulary combined with diarization or word timestamps, so pick one or the other per request.

For long recordings, start a background interaction instead of waiting on one synchronous request. SpeechKit polls until the interaction completes.

```swift
let response = try await speech.transcribeGeminiAudioFile(
    file: longRecordingURL,
    options: GeminiFileTranscriptionOptions(
        languageCodes: ["en-US"],
        processingMode: .background(pollInterval: 5)
    )
)
```

SpeechKit sends audio inline below the 20 MB default threshold and uploads larger files with the Gemini Files API. Set `uploadStrategy` to `.inline` or `.filesAPI` to force one path.

### File: Mistral

Mistral offers two file models: Voxtral Mini Transcribe 3 (the default) and Voxtral Small Transcribe 3 for higher accuracy. The provider-neutral API returns text:

```swift
let text = try await speech.transcribeAudioFile(
    provider: .mistral,
    file: audioFileURL,
    options: .mistral(modelID: .voxtralSmallTranscribe3, language: "en")
)
```

Use the detailed call when you want speaker labels and segment timestamps. Diarization is off by default; set `diarize` on the configuration or per request:

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    mistral: MistralConfiguration(
        credential: .apiKey("<MISTRAL_API_KEY>"),
        contextBias: ["Northwind", "Alder Creek Design"],
        diarize: true
    )
)

let response = try await speech.transcribeMistralAudioFile(file: audioFileURL)
print(response.text)
for segment in response.segments {
    print(segment.speakerID ?? "?", segment.start ?? 0, segment.end ?? 0, segment.text)
}
```

Mistral returns timestamps per segment only. Diarization requires segment timestamps, so SpeechKit requests them whenever `diarize` is on. `contextBias` entries can be names, multi-word terms, or a sentence that describes the recording.

### File: Fish Audio

Fish Audio file transcription uses Transcribe 1 Pro. The provider-neutral API returns text without speaker markers. Sound cues such as `[laughter]` stay in the text unless you set `tagAudioEvents` to `false`.

```swift
let text = try await speech.transcribeAudioFile(
    provider: .fishAudio,
    file: audioFileURL,
    options: .fishAudio(language: "en", speakerCount: .exact(2))
)
```

Use the detailed call when you want speaker labels and word timings:

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

```swift
let speech = SpeechService(
    fishAudio: FishAudioConfiguration(
        credential: .apiKey("<FISH_AUDIO_API_KEY>"),
        diarize: .on,
        speakerCount: .range(min: 2, max: 4)
    )
)

let response = try await speech.transcribeFishAudioAudioFile(file: audioFileURL)
print(response.transcriptText)
for word in response.words {
    print(word.speaker ?? "?", word.start ?? 0, word.end ?? 0, word.text)
}
```

`words` comes from Fish Audio's word segments. SpeechKit labels each word with its speaker and copies punctuation from the punctuated speaker turns where the two match. The raw `text`, `segments`, and `speakerTurns` are also on the response. Timestamps are on by default; set `timestamps` to `false` for a faster request with no words.

Fish Audio limits:

- Audio can be up to 60 minutes long. SpeechKit checks the duration before uploading.
- AIFF and CAF files are rejected. SpeechKit throws before uploading them, so convert recordings to M4A, WAV, MP3, or FLAC first.
- The request returns only when the whole file is done, so long files take minutes. The default timeout is 15 minutes.
- `language` is a lowercase two-letter code such as `"en"`. It helps detection but does not force the language.

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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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

Privacy: this example prints transcript content or error details. Use synthetic or explicitly consented data only; omit these prints from production logs.

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
