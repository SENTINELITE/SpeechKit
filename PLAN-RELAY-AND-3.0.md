# SpeechKit 3.0 and SpeechKit Relay: implementation contract

Created 2026-10-30. Owner decisions:
- The release is **SpeechKit 3.0.0**. The unpushed 2.1.0 (Mistral and Fish Audio) is folded into it, so 2.0.1 is the last published version.
- The server piece is called **Relay**. The repo is `../speechkit-relay`, a Cloudflare Worker template people deploy themselves. App login can be App Attest, a login from any standard provider (Convex Auth, Clerk, Firebase, Supabase), or both; the developer picks in config.
- Nothing is pushed or tagged. Commits are local only.
- A Convex add-on and a hosted-proxy adapter (for example AIProxy) are **out of scope for now**. The SDK hook must not prevent them later.

The security plan this implements is `PLAN-SECURITY-HARDENING.md` (findings SK-01 to SK-25; items P1.x, P2.x, P3.x and K1 to K11). This file pins the decisions the SDK and the relay must agree on. When the two files conflict, this file wins for API shape and wire protocol, and the security plan wins for security requirements.

Goal for app developers: **as few lines as possible.** The target integration is:

```swift
let speech = SpeechService(relay: SpeechRelay(url: URL(string: "https://speech.example.workers.dev")!))
// or, with per-user limits from an existing login (Convex Auth, Clerk, ...):
let speech = SpeechService(relay: SpeechRelay(
    url: URL(string: "https://speech.example.workers.dev")!,
    authentication: .appAttestAndBearer(SpeechTokenResolver { _ in try await convex.authToken() })
))
try await speech.startListening(provider: .fishAudio)   // unchanged call sites
```

## 1. SDK 3.0 public API decisions

These are binding for the shape; details are up to the implementer, and any deviation must be documented in the CHANGELOG.

1. **Credentials are an opaque `SpeechCredential` struct**, no longer an enum with payloads. It has private storage and redacted `description`, `debugDescription` and `customMirror`. Static factories:
   - `.apiKey(String)`: a vendor key, placed the way each vendor expects for keys.
   - `.vendorToken(SpeechTokenResolver)`: a short-lived token the vendor issues. SpeechKit places it the way that provider and capability document. Combinations that aren't supported throw a clear error before any network I/O and never fall back to a key. The verified matrix in the hardening plan applies:
     - ElevenLabs file (`?token=`)
     - ElevenLabs realtime (`?token=`)
     - OpenAI realtime transcription (`Authorization: Bearer` on the transcription-intent route)
     - Gemini Live (`Authorization: Token` on `BidiGenerateContentConstrained`)
     - Mistral realtime (`Sec-WebSocket-Protocol: realtime, <token>`)
     - Every other combination is unsupported.
   - `.bearer(SpeechTokenResolver)`: an opaque bearer token for **your own proxy** at custom endpoints, sent as `Authorization: Bearer`. Gemini REST with a Google OAuth access token also uses this.
   - `SpeechCredential.kind` is public, non-secret metadata (`.apiKey`, `.vendorToken`, `.bearer`, `.relay`).
   - There is **no public way to read the secret back**.
2. **`SpeechTokenResolver`** (K1):
   - `init(id: UUID = UUID(), _ resolve: @escaping @Sendable (SpeechTokenContext) async throws -> SpeechAccessToken)`.
   - It also has a convenience init whose closure returns `String`.
   - `SpeechTokenContext` is non-secret and `Sendable`. It carries `provider`, `capability` (`.fileTranscription`, `.realtime`), `model`, `operationID` and `attempt`.
   - `SpeechAccessToken(value:expiresAt:isReusable:)` has redacted descriptions.
   - `SpeechTokenProvider` is removed, or kept as a deprecated typealias or shim; either way, note it in the CHANGELOG.
3. **Configurations stop exposing credentials.**
   - Remove the public `apiKey` get/set and the public `credential` getter on every `*Configuration` and realtime service.
   - Replace them with `init(credential:…)`, `mutating func setCredential(_:)` and the read-only `credentialKind` / `hasCredential`.
   - Provide a complete Gemini route type, or validation, so that a partial proxy configuration can't send anything to Google (SK-11).
4. **Relay** (K2):
   - `SpeechService(relay: SpeechRelay, …)`, plus optional per-provider configurations for model and option defaults.
   - When a relay is set, every provider the relay serves is reachable with **no per-provider credential**. A per-provider configuration that has its own credential **and** its own endpoints means a direct connection, and it wins for that provider. A configuration without a credential inherits the relay.
   - `SpeechRelay(url:authentication:providers:tokenStrategy:)`:
     - `authentication` defaults to `.appAttest`. The other options are `.bearer(resolver)`, `.appAttestAndBearer(resolver)` and `.none`. `.none` is for development only and is documented as such.
     - `providers` defaults to all.
     - `tokenStrategy` defaults to `.proxyAll`. The other option is `.vendorTokensWhenAvailable`, which uses `/tokens` (see §2.6) and then connects directly to the vendor.
   - It is HTTPS only. WSS is derived from the same host and port. A loopback-only HTTP/WS exception exists for development.
5. **App Attest support is built in** (K10). SpeechKit ships `SpeechRelay` App Attest support using Apple's `DeviceCheck` framework. This is an Apple system framework, so the package stays dependency-free.
   - It handles the key ID in the Keychain (`WhenUnlockedThisDeviceOnly`, not synced), attestation, and the assertion when getting a session.
   - Where `DCAppAttestService.isSupported == false` (Simulator, some Macs), it fails with a clear error. It never silently downgrades. The developer can choose `.bearer` or `.none` instead.
6. **Transport** (P1.3, K11):
   - SDK-owned ephemeral `URLSession`s with no cache, cookies or credential storage.
   - Validate the endpoint before resolving any credential.
   - Refuse cross-origin and downgrade redirects for HTTP and WebSocket.
   - Optional pinning of the relay's SPKI via `SpeechRelay(…, pinnedPublicKeyHashes:)`, with no trust-all fallback.
7. **Errors** (P1.2, P2.3): public errors carry safe categories and status only. Nothing raw from a server, a callback or a URL.
8. **Lifecycle** (P1.5, P1.8):
   - A generation guard covers every realtime start.
   - Setting a configuration to `nil` or replacing it invalidates pending work.
   - `resetSession()` / `clearCredentials()`.
   - `discardRecording()`.
9. **Policy** (K3): `SpeechService(…, credentialPolicy: .disallowStaticKeys)` rejects `.apiKey` before any I/O.
10. **Retry** (K4): no automatic retry after audio has been sent. The relay ticket is renewed proactively before expiry. A ticket rejected **before** any audio is sent gets one renewal and one retry.

Preserve unrelated public API (providers, options, results, `SpeechServiceExtensionKey`, which SpeechKit-Voz uses), so that Voz needs only a dependency-range bump.

## 2. Relay wire protocol v1

All paths sit under `{origin}/speechkit/v1`. All JSON is UTF-8.

### 2.1 Info

`GET /speechkit/v1/info` is public and contains no secrets. It returns:

```json
{"protocol":1,"auth":{"appAttest":true,"bearer":false},
 "providers":{"fishAudio":{"file":true,"realtime":true,"vendorTokens":[]},
              "elevenLabs":{"file":true,"realtime":true,"vendorTokens":["fileTranscription","realtime"]}}}
```

Provider keys use SpeechKit's identifiers: `elevenLabs`, `openAI`, `gemini`, `grok`, `meta`, `mistral`, `fishAudio`, `cohere`, `aqua`. A provider appears only if its vendor key secret is configured.

### 2.2 App Attest

1. `POST /attest/challenge` returns `{"challenge":"<b64url 32 bytes>","expiresAt":<unix s>}`. The challenge is single-use and lives about 5 minutes.
2. `POST /attest/register` takes the body `{"keyId":"<b64>","attestation":"<b64 CBOR>","challenge":"<b64url>"}` and returns `204`.
   - The relay verifies Apple's attestation in full: the certificate chain to the Apple App Attest root, the nonce `SHA256(authData || SHA256(challenge))`, the RP ID hash `SHA256("<TEAMID>.<bundleID>")`, the AAGUID (`appattestdevelop` or `appattest` per config), a counter of 0, and that the key ID matches the credential ID.
   - It stores the public key and the counter.

### 2.3 Session ticket

`POST /session` exchanges a login and/or an assertion for a relay ticket.

- **Headers:** `Authorization: Bearer <user JWT>` when bearer auth is enabled.
- **Body** (when App Attest is enabled): `{"keyId":"…","assertion":"<b64 CBOR>","challenge":"<b64url from /attest/challenge>"}`. The client data that gets signed is the exact bytes `speechkit-session:` + challenge.
- **The relay verifies:**
  - the assertion signature over `SHA256(authenticatorData || SHA256(clientData))`
  - the RP ID hash
  - that the counter is greater than the stored counter, then stores the new counter atomically
  - that the challenge is unused and not expired
  - for a JWT, the signature against the configured JWKS URL, plus `iss`, `aud`, `exp` and `nbf`
- **Response:** `{"ticket":"<opaque>","expiresAt":<unix s>}`, with a TTL of 300 s or less.
  - The ticket is an HMAC-signed compact token. Its claims are `sub` (the JWT `sub` if bearer auth is on, else `attest:<keyId hash>`), `kid`, `exp` and `jti`.
  - The quota subject is `sub`.

### 2.4 Proxied routes

Every proxied request carries `Authorization: Bearer <ticket>`. The relay:
- validates the ticket and checks the quota
- **strips** `Authorization`, `xi-api-key`, `x-goog-api-key`, `Cookie` and any other auth headers from the client, and injects the vendor key
- streams request and response bodies, and never logs bodies, transcripts or query strings

The route table is the hardening plan's "K2 complete relay route contract". Prefix every route there with `/speechkit/v1/{providerId}`, where the provider ID is the lowercase SpeechKit identifier: `elevenlabs`, `openai`, `gemini`, `grok`, `meta`, `mistral`, `fishaudio`, `cohere`, `aqua`.

Only the routes in that table are allowed. Anything else returns 404, and the relay has no generic forwarding.

Query parameters are passed through only if they're on each route's allowlist. Model and option values are validated against the configured allowlists.

WebSocket routes:
- The upgrade carries `Authorization: Bearer <ticket>`.
- The relay opens the upstream socket with the vendor key the way that vendor expects (Fish/Grok/OpenAI/Mistral Bearer, ElevenLabs `xi-api-key`, Gemini `x-goog-api-key` on the non-constrained `BidiGenerateContent` method).
- It pipes frames both ways, with backpressure, and enforces a maximum session duration.
- **Meta:** the SDK's first frame carries `authorization.accessToken = "Bearer <ticket>"`. The relay validates it, replaces it with the vendor key, and drops any later auth frame.

**Gemini Files:**
- The relay rewrites `X-Goog-Upload-URL` to `{origin}/speechkit/v1/gemini/upload-sessions/{opaqueId}`. It keeps the mapping, bound to `sub`, with a TTL in a Durable Object or KV.
- Upload-session requests need the ticket, and the relay forwards them to the stored Google URL.
- File and interaction IDs that the relay returns are registered per `sub`, and requests for IDs the user doesn't own are rejected.

### 2.5 Errors

Errors use the body `{"error":{"code":"<snake_case>","message":"<constant text>"}}`, with these statuses:
- 400 `invalid_request`
- 401 `unauthenticated` / `ticket_expired`
- 403 `forbidden` / `attestation_failed`
- 404 `not_found`
- 413 `too_large`
- 429 `quota_exceeded`, with `Retry-After`
- 502 `upstream_error`, with the upstream status code only, never the upstream body
- 503 `provider_not_configured`

### 2.6 Vendor tokens (optional, `tokenStrategy: .vendorTokensWhenAvailable`)

`POST /tokens/{providerId}/{capability}` takes a ticket and returns `{"token":"…","expiresAt":<unix s>,"singleUse":true|false}`. It is supported only for these combinations:
- ElevenLabs `fileTranscription` and `realtime`: `/v1/single-use-token/batch_scribe` and `realtime_scribe`
- OpenAI `realtime`: `/v1/realtime/client_secrets` with `session.type: "transcription"`, TTL 600 s or less
- Gemini `realtime`: `/v1beta/auth_tokens` with `uses: 1`, a short expiry and a locked model
- Mistral `realtime`: `/v1/client/sessions`

Every other combination returns 404. The SDK then uses the proxy route.

### 2.7 Quotas and limits (configurable through env vars, with sensible defaults)

Limits apply per `sub` per UTC day:
- the number of requests
- upload bytes
- realtime seconds
- the maximum file size per request
- the maximum realtime session length
- concurrent realtime sessions

Counters live in a Durable Object keyed by `sub`, which makes concurrent reservations atomic.

### 2.8 Relay configuration (`wrangler.toml` vars plus secrets)

- **Secrets:** `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `XAI_API_KEY`, `META_API_KEY`, `MISTRAL_API_KEY`, `FISH_AUDIO_API_KEY`, `COHERE_API_KEY`, `AQUA_API_KEY`, `TICKET_SIGNING_KEY`.
- **Vars:**
  - `AUTH_MODE` = `appattest` | `bearer` | `both` | `none-dev`
  - `APPLE_TEAM_ID`, `APPLE_BUNDLE_IDS` (comma-separated), `APP_ATTEST_ENV` (`production` | `development`)
  - `JWT_JWKS_URL`, `JWT_ISSUER`, `JWT_AUDIENCE`, with Convex Auth, Clerk, Firebase and Supabase examples in the README
  - the quota vars and model allowlists
- `none-dev` refuses to start unless `ALLOW_INSECURE_DEV=true`.

## 3. Addendum (2026-10-30): upload optimization and MP4/AAC pass-through

Owner request: cut import preparation time by passing compressed files through where possible, and expose a simple on/off flag.

### 3.1 SDK API (replaces `SpeechRelay.ImportNormalization`; 3.0 is unpublished, so rename freely)

Builder-style modifier, SwiftUI-like, with no init parameter: `SpeechRelay(url: url).optimizeUploads(false)`. Signature: `public func optimizeUploads(_ enabled: Bool = true) -> SpeechRelay`. It returns a modified copy, and `SpeechRelay` stays a value type. The default when the modifier isn't used is `true`. Expose a read-only `public var optimizesUploads: Bool`. Remove `ImportNormalization` and `importNormalization`. Update the demo, docs, DocC (`ShippingInProduction.md`, `MigratingTo3.md`), README, CHANGELOG and the CLI if it references the old name.

- **`true` (default): the fastest upload that gets there.**
  - **Send the original file unchanged** when Relay can meter it and the provider accepts it: MP3, Ogg, FLAC, and audio-only AAC M4A/MP4 with `moov` before `mdat`. Also WAV that is already 16 kHz or lower and mono.
  - **Repackage without re-encoding** (AVFoundation passthrough export, `shouldOptimizeForNetworkUse = true`, audio track only) when the AAC audio is fine but the layout isn't:
    - `moov` sits after `mdat`;
    - the file has video, or other non-audio tracks (MOV, MP4);
    - the extension or container is `.mov`.
  - **Convert to 16 kHz mono FLAC** (WAV for providers without FLAC) as today when:
    - Relay can't meter the format: ALAC, CAF, AIFF, WebM, etc.;
    - the provider doesn't accept it;
    - repackaging fails;
    - the file is PCM WAV above 16 kHz or with more than one channel.
  - **Check repackaged output locally** with the same metering rules before upload. If the check fails, fall back to conversion.
- **`false`: never touch the audio.** Upload the original bytes, or throw `SpeechFailure(.unsupportedMediaType)` before any network I/O. This applies when Relay can't meter the format or the provider won't accept it, including AAC with `moov` at the end and files with video. This is the old `.disabled` behavior.
- **Temporary files and cancellation:** temporary copies use the existing protected temp-directory and cleanup rules, and cancellation still works at every step.
- **The original file is never modified.**
- **Provider AAC/M4A acceptance:** check each provider against its current vendor docs. Where a provider isn't verified, convert. Leave a source comment per provider citing the docs URL. Meta stays WAV-only unless its docs say otherwise.
- **Upload naming:** send the multipart filename `audio.m4a` with MIME type `audio/mp4`, unless a provider documents a different one.

### 3.2 Relay: meter AAC in MP4 (`src/file-audio.ts`, Gemini path included)

- **What's accepted:**
  - ISO-BMFF with `ftyp`, then `moov` before the first `mdat`, a single track with handler `soun`, and sample entry `mp4a` whose `esds` AudioSpecificConfig object type is 2 (AAC-LC), 5 (SBR) or 29 (PS).
  - Optional boxes: `free`, `skip`, `udta`, `meta` and `wide` may appear.
- **Rejected with 415:**
  - fragmented MP4 (`mvex`/`moof`);
  - more than one track, or any video/text track;
  - other codecs (ALAC, Opus-in-MP4, etc.);
  - multiple `mdat` boxes;
  - `moov` after `mdat`;
  - `moov` larger than `MAX_MP4_HEADER_BYTES` (default 8 MiB).
- **Duration:**
  - **Primary count:** `sampleCount × 1024 / coreSampleRate`, where `sampleCount` comes from `stsz` and `coreSampleRate` from AudioSpecificConfig, not from `mdhd` and not the SBR output rate.
  - **Cross-check:** `sum(stts deltas) / mdhd.timescale`.
  - Charge the larger of the two.
  - Ignore `mvhd` and `mdhd` durations.
  - Require the `stts` total sample count to equal the `stsz` sample count.
- **Integrity (fail closed):**
  - Every `stco`/`co64` chunk offset plus its samples (`stsc`, `stsz`) must lie inside the one `mdat` payload.
  - Sample ranges must not overlap.
  - `mdat` payload length must be at most `sum(stsz)` + 64 bytes of slack.
  - The file must end at the `mdat` end, except for trailing `free`/`skip`/`udta` boxes totaling 64 KiB or less.
  - Any unreferenced audio byte must make the request fail rather than be forwarded.
  - Truncation is a parse failure.
- **Charging:** reserve the full computed duration before forwarding any `mdat` byte, so the quota is held up front. The existing hold and rollback rules apply unchanged.
- **Wire contract:** update the constant 415 message to `"Audio format cannot be metered. Use WAV, FLAC, Ogg, MP3, or AAC (M4A)."`, and update CONTRACT.md and the README. The `ALLOW_UNVERIFIED_FILE_AUDIO` byte-floor policy remains for other containers.
- **Fixtures:** generate real fixtures on macOS (`afconvert -f m4af -d aac`, `afconvert -f mp4f`, a faststart variant, an HE-AAC variant). Also hand-built adversarial ones: lying `mvhd`, extra unreferenced `mdat` bytes, overlapping offsets, a video track, fragmented, `moov`-last, truncated.
