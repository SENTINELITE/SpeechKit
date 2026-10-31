# Shipping SpeechKit in production

Choose a credential boundary for each provider and capability before distributing your app.

## Threat model and decision rule

Assume a user can inspect their installed app, hook its process, and obtain anything it sends as an ordinary bearer credential. An opaque Swift value or Keychain entry does not turn a vendor key into a server secret. Avoid app-owned vendor keys in app bundles, preferences, remotely fetched configuration, logs, analytics, request URLs, and crash reports.

- If users pay with their own vendor accounts, use BYOK with ``SpeechCredential/apiKey(_:)``. Store persistent user keys in Keychain and explain their use and revocation.
- If the exact provider/capability/model has a documented native token, mint one on an authenticated backend and use ``SpeechCredential/vendorToken(_:)``. A token for voice conversations, agents, or Live sessions does not authorize unrelated file STT.
- If the app owns the vendor account, needs central limits, or lacks suitable native tokens, use ``SpeechRelay``. The vendor key stays on your server. A backend that returns permanent vendor keys is not a relay.

Apple local Speech uses no vendor credentials but still needs microphone permission, appropriate UI privacy, and local model assets. It is available on iOS 26, macOS 26, and visionOS 26, not watchOS.

## Minimal relay setup

```swift
import Foundation
import SpeechKit

let speech = SpeechService(relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!))
```

The sibling [speechkit-relay repository](https://github.com/SENTINELITE/speechkit-relay) contains a self-hosted Cloudflare Worker template and is **not yet published**. Until publication use `../speechkit-relay`, its README, and `docs/CONTRACT.md`. This article describes the local SDK/template contract on 2026-10-30, not a verified public deployment.

The default is `.appAttest` authentication and `.proxyAll` token strategy. Enable Apple's App Attest entitlement for your app and configure server team ID, bundle IDs, App Attest environment, accepted distribution/version policy, and `AUTH_MODE=appattest`. TestFlight uses Apple's production environment. The SDK keeps the device key identifier in nonsynced `WhenUnlockedThisDeviceOnly` Keychain storage and serializes assertions.

The SDK obtains a challenge, registers the Apple key, and exchanges a fresh assertion for a ticket through `/speechkit/v1/session`. App Attest modes also bind fresh operation proofs to protected HTTP requests, token minting, and WebSocket upgrades. The server must check challenge expiry and one-time use, assertion counters, app identity, and the request/ticket/body binding. A session assertion alone does not implement per-operation replay protection.

A device where `DCAppAttestService.isSupported` is false, including unsupported simulators or Macs, fails closed. Decide explicitly whether to deny access or offer a server-configured bearer-login mode. SpeechKit does not silently weaken authentication. `.none` requires an explicitly configured development server; restrict it to local development and never expose a public relay without authentication.

## Relay audio imports

The relay derives a metering duration from supported audio containers. It supports PCM/IEEE-float WAV, FLAC, Ogg Opus/Vorbis, MP3, and nonfragmented AAC-LC/HE-AAC in M4A/MP4 with one audio track and `moov` before `mdat`, intersected with verified provider acceptance. Local MP4 validation mirrors the Worker's structural checks: child-box allowlists, aligned `ftyp`, codec descriptors, sample tables, duration, nonoverlapping chunk ranges, and no more than 64 all-zero unreferenced payload bytes. An optional edit list may contain at most one entry, with rate 1.0, nonnegative media time, and an end no later than the `stts` media duration after conservative timescale conversion. Server-configured limits remain independent. MIME types and filenames alone do not establish the container.

Each MP4 sample must contain exactly one AAC-LC access unit (`raw_data_block`), checked by an AAC syntax walker before the sample is accepted locally or forwarded by the Worker. Duration is billed as 1,024 samples per access unit at the core rate. This is syntax validation, not full decoding: SBR/PS extension payloads are skipped by length, 960-sample configurations are rejected, and samples over 8,192 bytes are rejected. Files that fail convert on-device when optimization is on, or fail with `unsupportedMediaType` before any network request when it is off.

``SpeechRelay`` defaults to `optimizedUploads: .on`. Supported compressed files and mono WAV at 16 kHz or lower pass through unchanged. AAC with a trailing header, video/extra tracks, or a MOV container is repackaged without re-encoding using AVFoundation passthrough, network optimization, and only the first audio track. Output must pass local metering validation. ALAC, CAF, AIFF, WebM and other unsupported imports, failed repackaging, and high-rate or multichannel PCM WAV convert to 16 kHz mono FLAC when supported by the provider and local encoder, otherwise PCM16 WAV. OpenAI and Meta use WAV for conversion. Verified M4A providers are OpenAI, ElevenLabs, Grok, Aqua, Gemini, and Fish Audio; unverified Mistral and Cohere convert. Meta stays WAV-only. Source comments link to the official format documentation checked October 30, 2026. Multipart AAC uses `audio.m4a` and `audio/mp4`; Gemini uses its documented `audio/m4a`. Incorrectly named supported files receive a correctly named temporary copy only when optimization is on.

Meta's explicit 16/24 kHz PCM modes and Grok's mono 16-bit little-endian PCM mode become 16 kHz mono PCM16 WAV. The upload declares WAV/container audio instead of raw decoding. Grok mu-law, A-law, and multichannel raw modes fail with `SpeechFailure.Category.unsupportedMediaType`.

```swift
let relay = SpeechRelay(
    url: URL(string: "https://speech.example.workers.dev")!,
    optimizedUploads: .off
)
```

Use `.off` when the app must upload original bytes without repackaging or conversion. Files that the relay cannot meter or the provider does not accept fail before credential resolution or network I/O with `SpeechFailure.Category.unsupportedMediaType`. This includes moov-last AAC and video-bearing files. Valid high-rate or stereo WAV remains unchanged with optimization off. HTTP 415 `unsupported_media_type` maps to that category too, preserving the numeric status without exposing the server body. Neither failure retries audio. Conversion failures use `audioNormalizationFailed`; size and duration failures use `audioTooLarge` and `audioTooLong`. Direct provider uploads are unaffected.

Provider upload-size limits apply to the prepared file. A larger source may convert into an upload below that limit, such as 160 seconds of 48 kHz stereo PCM16 WAV becoming a 5,120,044-byte 16 kHz mono WAV. Local imports have a separate 512 MiB source-byte ceiling. Conversion and repackaging are bounded to one hour and 128 MiB of output, with provider duration limits applied when available.

Normalization runs off the main actor with bounded audio buffers and cancellation checks. It writes private temporary files with complete file protection on iOS, watchOS, and visionOS, and owner-only file/directory permissions. Cleanup runs after upload success, failure, and cancellation. The caller's file is never modified or deleted. Keep security-scoped file access open for the entire transcription operation.

The clients check provider limits before upload and during conversion. OpenAI remains limited to 25 MiB; Fish Audio remains limited to 60 minutes. A compressed import may exceed its provider's size limit after WAV conversion. AVFoundation must be able to decode an import locally; this is not a universal WebM/MKV decoder. The server still independently verifies format and duration. Operator quotas, multipart/base64 overhead, and conservative codec duration accounting may reject audio that passes SDK preflight. Normalization does not relax relay metering policy. Direct provider credentials and native vendor-token uploads remain unchanged.

## Login JWTs with Convex Auth or Clerk

Supply a closure that obtains an API JWT from your existing login client. SpeechKit does not depend on Convex Auth or Clerk or prescribe their Swift client methods. Do not supply a refresh token, a permanent vendor key, or a relay ticket as the login JWT.

```swift
@MainActor
func speechWithLogin(
    accountID: String,
    fetchLoginJWT: @escaping @Sendable () async throws -> String
) -> SpeechService {
    let resolver = SpeechTokenResolver { _ in try await fetchLoginJWT() }
    return SpeechService(
        relay: SpeechRelay(
            url: URL(string: "https://speech.example.workers.dev")!,
            authentication: .appAttestAndBearer(resolver),
            appAttestAccountID: accountID
        ),
        credentialPolicy: .relayOnly
    )
}
```

Combined authentication uses `AUTH_MODE=both`. The template binds a registered App Attest key to its first authenticated subject. For an intentionally bearer-only policy, use the following with `AUTH_MODE=bearer`:

```swift
@MainActor
func speechWithBearerLogin(
    fetchLoginJWT: @escaping @Sendable () async throws -> String
) -> SpeechService {
    SpeechService(
        relay: SpeechRelay(
            url: URL(string: "https://speech.example.workers.dev")!,
            authentication: .bearer(SpeechTokenResolver { _ in try await fetchLoginJWT() })
        ),
        credentialPolicy: .relayOnly
    )
}
```

On the template, configure an HTTPS JWKS URL, exact issuer and audience, and require subject and expiry. Convex Auth commonly uses its deployment's `convex.site/.well-known/jwks.json`, issuer at that `convex.site` origin, and audience `convex`; verify your actual signed claims. For Clerk, configure the instance's JWKS/issuer and a JWT template with an explicit audience such as `speechkit`. Ordinary Clerk session JWTs may lack that audience. Do not disable audience verification to make a sample token work. The template accepts RS256/ES256, validates a present `nbf`, and does not permit token-selected JWKS locations.

Login authenticity is separate from authorization. Enforce entitlement to transcribe, account status, provider/model access, and user/device/global limits on the server. Bearer-only authentication cannot provide App Attest request proofs. Neither mode proves user consent to record.

## Account-scoped App Attest identity

Pass a stable, nonsecret `appAttestAccountID`, including issuer identity if multiple issuers can produce the same subject. The SDK hashes the relay URL and account namespace into its Keychain lookup. Build a new service and resolver for a different account; never make a resolver return another subject under an existing namespace. Signing back into the same account reuses its registered key. Omitting the namespace preserves the legacy relay-only lookup for compatibility.

`clearCredentials()` preserves these persisted identifiers. To intentionally replace a key, first stop operations with `resetSession()`, then call the following on the original relay value:

```swift
@MainActor
func forgetLocalAttestation(speech: SpeechService, relay: SpeechRelay) async throws {
    await speech.resetSession()
    try await relay.resetAppAttestKey()
}
```

Reset waits for assertion submission and registration to finish, then deletes only this relay/account's identifier. Repeated concurrent resets are safe. The next operation generates and registers a new key, and existing SDK sessions stop reusing tickets issued under the old identity. Other account namespaces remain intact. This is local reset, not Apple key destruction, remote key revocation, subject rebinding, or termination of active sockets. Server-side revocation remains your responsibility.

An Apple `DCError.invalidKey`, or a relay `attestation_failed`/unknown-key rejection at `/session`, permits at most one automatic key re-registration per logical operation. The same recovery budget covers ticket creation and operation proofs. A replacement registration failure or another invalid key ends the operation. Only successful registrations persist. The SDK never retries uploaded audio, accepted sockets, or uncertain billable requests for attestation recovery, and generic auth/transport errors do not trigger key rotation.

## Limit view capabilities

Obtain ``SpeechTranscription`` through ``SpeechService/transcriber`` and inject `.environment(\.speechTranscriber, speech.transcriber)`. Views read `@Environment(\.speechTranscriber)` for `startListening()`, `startListening(provider:)`, `stopListening()`, read-only `connectionState`, `transcriptText`, `partialTranscriptText`, `transcriptEntries`, and `lastError`. File transcription uses `transcribeAudioFile(provider:file:options:)` or its `securityScopedURL:` overload and returns text.

The capability has no configuration setters, credential management, resolver, relay, or owning-service getter. Its computed reads preserve the owning service's Swift Observation updates. Configure providers and manage account transitions only at the composition root. The existing `speechService` environment value remains unchanged. Unless explicitly injected, `speechTranscriber` derives from that service; inject only the narrow value when views should not receive the configured service.

## Native vendor tokens

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

## Resolving native tokens

Use a backend adapter that authenticates the caller and checks the resolver context before minting. This example deliberately makes no assumptions about your backend SDK:

```swift
@MainActor
func speechWithNativeOpenAIToken(
    mintToken: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken
) -> SpeechService {
    var openAI = OpenAIConfiguration()
    openAI.setCredential(
        .vendorToken(SpeechTokenResolver { context in try await mintToken(context) }),
        for: .realtime
    )
    return SpeechService(openAI: openAI, credentialPolicy: .disallowStaticKeys)
}
```

Here file authorization stays empty; use a relay for OpenAI files. ``SpeechTokenContext`` contains provider, capability, model, operation ID, attempt, auth mode, and approved destinations. ``SpeechAccessToken`` exposes expiry/reuse metadata, not its value. The resolver's UUID defines equality. A string-returning closure is available when your backend adapter has no metadata. Allocate fresh single-use tokens per logical operation; do not cache them across concurrent starts.

Do not conflate expiry, reuse, scope, and budget. The accepting server enforces each. `expiresAt` lets the SDK reject an expired token; `isReusable` does not enforce usage counts or a session cap. A successfully opened session may outlive a token. A backend mint response with an unknown outcome must not trigger blind mint/audio retries. SpeechKit renews relay tickets before operations and permits only bounded pre-send renewal; it does not replay already-sent audio.

`SpeechRelay.TokenStrategy.vendorTokensWhenAvailable` asks the relay for supported native tokens and then connects directly to the vendor. Unsupported combinations and 404 responses use the proxy; other mint failures remain errors. The SDK restricts Mistral native tokens to the legacy 2602 model. `.proxyAll` keeps the relay on every request, which is necessary when you rely on relay session limits or content-handling policy. Native token handoff bypasses those relay traffic limits after issuance.

## Credential policy and complete routing

The default `.allowStaticKeys` permits BYOK. Set `.disallowStaticKeys` when your app must reject static-key operations before network activity. Set `.relayOnly` to reject direct credentials and force proxy routes, even with native-token strategy selected. Policy belongs to each service, not global process state, and cannot constrain a modified client.

A relay-backed configuration without a credential inherits the relay. A credentialed configuration must provide the selected capability's explicit endpoint and wins as a direct override unless policy rejects it. A credential with no matching direct endpoint fails rather than silently falling back. For per-capability overrides, inspect `credentialKind(for:)` and `hasCredential(for:)`; the properties without `for:` describe only the base credential.

A custom proxy uses ``SpeechCredential/bearer(_:)`` and must handle all protocol routes, not just the first transcription request. Gemini's complete route includes Interactions, Files upload initiation, returned upload-session URLs, file polling, interaction polling, and Live. Prefer ``GeminiRoute``:

```swift
@MainActor
func geminiViaProxy(
    fetchProxyToken: @escaping @Sendable () async throws -> String
) throws -> SpeechService {
    var configuration = GeminiConfiguration(
        credential: .bearer(SpeechTokenResolver { _ in try await fetchProxyToken() })
    )
    try configuration.setRoute(GeminiRoute(
        interactions: URL(string: "https://api.example.com/gemini/v1beta/interactions")!,
        files: URL(string: "https://api.example.com/gemini/upload/v1beta/files")!,
        realtime: URL(string: "wss://api.example.com/gemini/live")!
    ))
    return SpeechService(gemini: configuration, credentialPolicy: .disallowStaticKeys)
}
```

Same-origin validation is the default. `.explicitMixedOrigins` is an explicit reviewed exception for direct integrations, not relay tickets. The template rewrites Google upload/resource identifiers to relay-owned identifiers and binds them to the caller; it must reject foreign resources and caller-selected upstream URLs. The Meta relay must replace `authorization.accessToken` in the first JSON frame with the server's vendor key and reject later auth frames. Adding an HTTP header alone does not adapt Meta's protocol.

SpeechKit uses SDK-owned ephemeral sessions without cache, cookies, or credential storage. It validates endpoints before resolving credentials and refuses redirects. Use HTTPS/WSS; loopback HTTP/WS is only for development. Optional `pinnedPublicKeyHashes` on `SpeechRelay` accepts SHA-256 SPKI hashes. If you pin, plan backup pins and certificate rotation; pinning does not replace system trust or protect a hooked client. It does not pin direct native-token connections to vendors.

## Reset is not revocation

```swift
speech.recordingRetention = .discardOnStop
await speech.resetSession()
speech.discardRecording()
await speech.clearCredentials()
```

- `stopListening()` ends capture. Transcript and recording can remain.
- `resetSession()` cancels pending operations, invalidates stale callbacks, clears cached relay tickets, and discards transcripts/SDK recordings by default. Optional flags retain local results, and configured credentials/resolver captures remain.
- `discardRecording()` drops the SDK's in-memory recording. It does not delete caller-owned files or transcript copies.
- `clearCredentials()` resets and removes SDK-held credentials, resolver captures, and relay configuration. It preserves persisted App Attest identifiers. It does not clear your app's login client's cache, persistent keys, or other copies. Use the original relay value's `resetAppAttestKey()` for explicit local attestation reset.

Recording retention defaults to `.retainUntilDiscarded`. Revocation, rotation, sign-out, denial of future server requests, deletion of server/vendor recordings, and deletion of application-owned files are separate responsibilities. Local clearing does not revoke already-issued JWTs/vendor tokens/relay tickets or deregister the App Attest key. Coordinate account switching with server authorization and explicit SDK reset/clear; do not assume a local reset changes remote identity bindings. Swift strings and external copies cannot be guaranteed erased from memory.

## Limits and deployment checks

Keychain protects data at rest according to its access controls. A process with permission to use the item can still read or use it. App Attest gives the server an authenticity signal, not user identity, consent, proof of benign runtime behavior, immunity to device farms, or guaranteed budget enforcement. JWTs and native tokens are bearer authority unless the receiving server enforces stronger binding.

Configure server replay protection, ownership checks, SSRF restrictions, allowlisted models, byte/request/session/concurrency limits, atomic quotas, and aggregate account limits. Bound session duration independently of ticket expiry. Keep a kill switch and revocation/rotation procedure. Review what the vendor stores and how users request deletion. A trusted relay and the vendor see audio/transcripts; TLS does not hide content from them.

Do not log transcript text, recording bytes, secrets, request URLs, provider response bodies, arbitrary callbacks, or WebSocket close reasons. The template avoids storing/logging audio and transcripts by design, but this does not establish zero vendor retention or the behavior of your hosting/telemetry setup. SDK error boundaries use ``SpeechFailure``, ``SpeechFailureReason``, and numeric HTTP status. App code can still leak data outside those boundaries.

Before shipping, run SDK/relay synthetic contract tests, device-level entitlement/Keychain/attestation checks, and separately authorized native-token canaries for the exact route and model. Verify complete Gemini routing and Meta auth replacement against your deployed server. A successful build or DocC conversion proves none of those live properties.
