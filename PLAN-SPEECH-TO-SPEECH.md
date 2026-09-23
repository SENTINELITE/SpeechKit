# Plan: Speech-to-Speech Conversation Layer (OpenAI GPT-Live-1)

Branch: `feature/gpt-live-speech-to-speech` (cut from `main` at 2.0.1, 2026-09-15)
Target release: SpeechKit 2.1.0 (additive; no source-breaking changes)

## 1. Goal

Add a third capability layer to SpeechKit next to realtime transcription and file
transcription: a full-duplex **speech-to-speech conversation**. The first provider is
OpenAI `gpt-live-1` over WebSocket. The layer is provider-neutral in its public vocabulary
so Gemini Live audio output or other vendors can slot in later without another rename.

Nothing in the existing speech-to-text layers changes. `startListening` stays transcription.

## 2. What the GPT-Live API actually is (verified 2026-09-15)

GPT-Live is a **separate API from Realtime**, not a rename. Key facts pulled from
developers.openai.com (guides: `live`, `voice-websockets?api=live`, `live-conversations`,
`live-delegation`, `live-migration`, `voice-latency-cost?api=live`,
`voice-server-controls?api=live`, `models/gpt-live-1`, `pricing`):

| Topic | Fact |
|---|---|
| Model | `gpt-live-1` (only snapshot). Audio+text in, audio+text out. Function calling via delegation only. |
| WebSocket URL | `wss://api.openai.com/v1/live/sessions` (no `model` query param; model goes in `session.start`) |
| Auth | `Authorization: Bearer <key>`. No ephemeral client-secret endpoint is documented for Live. |
| Sideband | `wss://api.openai.com/v1/live/sessions/{session_id}/attach` (server-side observer; out of scope) |
| WebRTC | `POST /v1/live/sessions` with `transport: { type: "webrtc", sdp }` (out of scope for v1) |
| Billing | $0.05 / minute, billed per second. Backend (delegation) tokens billed separately. Session creation via the HTTP endpoint pre-bills 15 s. |
| Rate limit | Concurrent sessions per tier: 25 / 50 / 200 / 300 / 500. No free tier. |
| Audio in/out | Base64 raw PCM16 LE, no container. `audio/pcm` at 24 kHz (default) or 16 kHz; `audio/pcmu` / `audio/pcma` at 8 kHz. Chunk byte length must be even. |
| Turn-taking | Server-managed. Stream mic audio continuously. No commit, no VAD config, no `response.create` for speech. User and assistant can overlap. |
| Response end | There is **no** output-audio-done or turn-done event. Transcripts arrive as fragments with `start_ms` / `end_ms` on the session timeline (`[start, end)`, can overlap between speakers). |

### Client events

| Event | Fields | Notes |
|---|---|---|
| `session.start` | `event_id`, `session { model, instructions, audio { format { type, rate }, output { voice } }, delegation, history? }` | Must be the first message. Wait for `session.started` before sending audio. |
| `session.input_audio.append` | `audio` (base64) | No acknowledgement. |
| `session.input_audio.mute` / `.unmute` | | Acked by `session.input_audio.muted` / `.unmuted`. Mute does not stop generated speech. |
| `session.update` | `session { delegation.responses… }` | Only `delegation.responses` settings are mutable after start. Acked by `session.updated`. |
| `session.instructions.append` | `event_id`, `delegation_id` (`null` = session-wide), `content` (≤ 500 tokens) | Trusted app directives. Acked by `session.instructions.appended`. |
| `session.thinking.append` | same | Quiet factual context, never spoken. Acked by `session.thinking.appended`. |
| `session.commentary.append` | same | Content the model may paraphrase aloud. Acked by `session.commentary.appended`. |
| `response.item.create` / `response.create` | Responses-API shapes | Only meaningful with Responses delegation. |
| `session.close` | | Graceful close. Keep receiving until `session.closed`. |

### Server events

| Event | Fields |
|---|---|
| `session.started` | `session { id, …resolved config }` |
| `session.updated` | `session` |
| `session.output_audio.delta` | `delta` (base64 PCM16 at configured rate) |
| `session.input_transcript.delta` | `delta`, `start_ms`, `end_ms` |
| `session.output_transcript.delta` | `delta`, `start_ms`, `end_ms` |
| `session.input_audio.muted` / `.unmuted` | |
| `session.instructions.appended` / `session.thinking.appended` / `session.commentary.appended` | `client_event_id`, `start_ms`, `end_ms` |
| `session.delegation.created` | `delegation { id, target }` (client delegation) |
| `response.event` | `delegation_id`, `event { …nested Responses stream event }` (Responses delegation) |
| `session.usage.updated` | `usage.seconds` (cumulative snapshot), `context_window.usage_ratio` |
| `session.closed` | `usage.seconds`, `reason` (`close_requested`, `expired`, `content`, `remote_hangup`, `connection_lost`), `session` |
| `error` | `error { type, code, message, param, client_event_id? }` — moderation may cut speech without closing |

### Delegation modes

- `delegation: { type: "responses", responses: { model, instructions, tools, tool_choice, parallel_tool_calls, max_output_tokens, service_tier, reasoning, text } }` — OpenAI runs the backend; results stream back as `response.event`.
- `delegation: { type: "client" }` — the app receives `session.delegation.created` and answers with the three `*.append` events carrying that `delegation_id`.
- Unknown: whether `delegation` may be omitted entirely. Phase 0 verifies.

### Open questions to settle in Phase 0 (needs a real key)

1. Is `delegation` optional? If not, what is the cheapest sane default backend model?
2. Full voice list for `audio.output.voice` (docs show only `marin`).
3. Does the server send anything on barge-in that lets the client flush buffered playback, or is buffer depth the only lever?
4. Does `session.start` fail on a `SpeechCredential.token` secret minted for Realtime, or is there any short-lived credential path at all? (Docs say keep the key on a trusted server.)
5. Idle timeout / max session duration (undocumented; drives `expired` handling).
6. Does the WebSocket path also pre-bill 15 s like the HTTP session endpoint?

## 3. Design decisions

### 3.1 Lives in the core package, not an extension package

OpenAI already lives in core, the feature needs no third-party dependency, and the
`SpeechService` facade already owns the OpenAI credential. The `SpeechServiceExtensionKey`
seam stays reserved for heavy, optional dependencies like VOZ.

### 3.2 Vocabulary: "Conversation"

"Realtime" already means realtime *transcription* in this package and its README, and
OpenAI itself uses "Realtime" for the older API. The new layer uses **conversation**:

| Existing (speech-to-text) | New (speech-to-speech) |
|---|---|
| `SpeechRealtimeProvider` | `SpeechConversationProvider` (`.openAI` only for now) |
| `SpeechRealtimeConnectionState` | `SpeechConversationState` |
| `SpeechTranscriptEntry` | `SpeechConversationTranscriptEntry` (adds `role`) |
| `startListening(provider:)` / `stopListening()` | `startConversation(provider:)` / `endConversation()` |
| `OpenAIRealtimeService` | `OpenAILiveService` |
| `OpenAIRealtimeWebSocket` | `OpenAILiveWebSocket` |
| `OpenAIRealtimeMessages.swift` | `OpenAILiveMessages.swift` |
| `OpenAIRealtimeSessionOptions` | `OpenAILiveSessionOptions` |
| `SpeechError.realtimeProviderNotConfigured` | `SpeechConversationError.providerNotConfigured` (new enum, so `SpeechError` stays exhaustive-switch safe) |

Provider-specific type names use OpenAI's own product name, **Live**, so the file layout
mirrors the existing `OpenAI/OpenAIRealtime*` trio: `OpenAI/OpenAILiveService.swift`,
`OpenAI/OpenAILiveWebSocket.swift`, `OpenAI/OpenAILiveMessages.swift`.

### 3.3 Credentials: reuse the OpenAI key by default, allow a dedicated one

`OpenAIConfiguration` gains:

```swift
/// Options for OpenAI GPT-Live speech-to-speech sessions.
public var live: OpenAILiveSessionOptions
/// A credential used only for GPT-Live sessions, or `nil` to reuse `credential`.
public var liveCredential: SpeechCredential?
/// An override for the GPT-Live WebSocket endpoint, or `nil` to use the vendor default.
public var liveEndpoint: URL?
```

Resolution rule, in one place (`SpeechService.resolvedOpenAILiveCredential(from:)`):
`liveCredential ?? credential`. A separate project key on the OpenAI dashboard then
shows conversation spend apart from transcription spend, which is the user's stated reason.

`liveEndpoint` follows the existing `realtimeEndpoint` / `fileEndpoint` proxy pattern and
is the answer to "no ephemeral secret": route through your own server and hand SpeechKit
a `SpeechCredential.token` for whatever bearer that proxy expects. README says this plainly.

All three fields get defaults so every existing `OpenAIConfiguration` call site compiles.

### 3.4 Full-duplex audio needs its own engine

The existing `AudioCaptureManager` sets the iOS session to `.record` / `.measurement`.
Full duplex needs `.playAndRecord` with `.voiceChat` mode so the OS applies echo
cancellation; otherwise the assistant hears itself and talks over its own playback.

New file `Sources/SpeechKit/Conversation/SpeechDuplexAudioEngine.swift`:

- One `AVAudioEngine`. Input tap on `inputNode` (100 ms buffers, converted to Int16 mono
  at the session rate, same conversion code path as `AudioCaptureManager`), one
  `AVAudioPlayerNode` on `mainMixerNode` for output.
- Playback queue: decode each `session.output_audio.delta` to an `AVAudioPCMBuffer`
  and `scheduleBuffer` in order. Track scheduled-but-unplayed bytes so the service can
  expose `assistantIsSpeaking` and `flushAssistantAudio()`.
- Output level metering from a tap on the player node, same RMS + smoothing as the input
  meter, exposed as `assistantAudioLevel`.
- Input meter and recorded WAV of the user side, same as the transcription managers, so the
  demo's voice stage works unchanged.
- macOS: no `AVAudioSession`; rely on the engine's default voice-processing IO
  (`inputNode.setVoiceProcessingEnabled(true)` on both platforms, guarded by availability).
- watchOS: compile, but treat playback as best-effort. Not a v1 support target.

Reuse, not duplication: pull the Int16 conversion, RMS meter, and WAV writer out of
`AudioCaptureManager` into a small internal `SpeechPCMAudioSupport` helper used by both.

### 3.5 Transcript model

GPT-Live sends fragments, not turns. SpeechKit groups them client-side:

```swift
public struct SpeechConversationTranscriptEntry: Identifiable, Equatable, Sendable {
    public enum Role: Sendable { case user, assistant }
    public let id: UUID
    public let provider: SpeechConversationProvider
    public let role: Role
    public private(set) var text: String
    public let startMilliseconds: Int
    public private(set) var endMilliseconds: Int
    public let timestamp: Date
}
```

Grouping rule (`SpeechConversationTranscriptAssembler`, pure value type, unit tested):
a fragment appends to the newest entry of the same role when its `start_ms` is within
`turnGapMilliseconds` (default 1200) of that entry's `end_ms`; otherwise it starts a new
entry. Entries interleave by role, so an interruption shows both rows growing, matching
OpenAI's guidance to keep earlier assistant text visible.

Convenience on the service: `conversationTranscript: [SpeechConversationTranscriptEntry]`,
`userTranscriptText`, `assistantTranscriptText`.

### 3.6 State

```swift
public enum SpeechConversationState: Equatable, Sendable {
    case idle
    case connecting
    case active(sessionID: String)
    case ending
    case ended(reason: SpeechConversationEndReason, seconds: Double?)
    case error(String)
}

public enum SpeechConversationEndReason: String, Sendable {
    case closeRequested = "close_requested", expired, content, remoteHangup = "remote_hangup", connectionLost = "connection_lost", unknown
}
```

`ended` carries the final `usage.seconds` so apps can show cost without parsing events.
Live usage snapshots surface as `conversationUsageSeconds: Double` and
`conversationContextUsageRatio: Double?`.

### 3.7 Session options

```swift
public struct OpenAILiveSessionOptions: Sendable, Equatable {
    public var modelID: OpenAILiveModelID            // .gptLive1 = "gpt-live-1"
    public var instructions: String?
    public var voice: OpenAILiveVoice                // string-backed struct, .marin static, custom init
    public var audioFormat: OpenAILiveAudioFormat    // .pcm24k (default), .pcm16k, .pcmu8k, .pcma8k
    public var delegation: OpenAILiveDelegation      // .none / .responses(OpenAILiveResponsesDelegation) / .client
    public var closeTimeout: TimeInterval            // 15 s wait for session.closed
    public var turnGapMilliseconds: Int              // transcript grouping
}
```

`OpenAILiveResponsesDelegation` holds `model`, `instructions`, `tools` (encoded as raw
JSON via a small `OpenAIJSONValue` enum so function schemas pass through untouched),
`toolChoice`, `parallelToolCalls`, `maxOutputTokens`, `serviceTier`. `validate()`
rejects empty voice, odd audio settings, and `maxOutputTokens < 16`, in the style of
`OpenAIRealtimeSessionOptions.validate()`.

`OpenAILiveVoice` is a struct, not an enum, so a new voice never requires a package release.

### 3.8 Public surface on `SpeechService` (facade)

New file `Sources/SpeechKit/SpeechService+Conversation.swift`:

```swift
public var activeConversationProvider: SpeechConversationProvider
public var conversationState: SpeechConversationState
public var conversationTranscript: [SpeechConversationTranscriptEntry]
public var partialUserTranscriptText: String        // newest open user entry
public var partialAssistantTranscriptText: String   // newest open assistant entry
public var conversationInputLevel: Double
public var conversationOutputLevel: Double
public var isConversationInputMuted: Bool
public var assistantIsSpeaking: Bool
public var conversationUsageSeconds: Double
public var conversationLastError: Error?

public func startConversation(provider: SpeechConversationProvider = .openAI) async
public func endConversation() async
public func muteConversationInput() async
public func unmuteConversationInput() async
public func flushAssistantAudio()
public func clearConversationTranscript()

// Context injection (session-wide; delegationID nil)
public func appendConversationInstructions(_ content: String, delegationID: String? = nil) async throws
public func appendConversationThinking(_ content: String, delegationID: String? = nil) async throws
public func appendConversationCommentary(_ content: String, delegationID: String? = nil) async throws
```

Client delegation is exposed as an `AsyncStream<OpenAILiveDelegationRequest>` on
`OpenAILiveService` (`delegationRequests`) rather than on the facade, since it is
OpenAI-specific. Responses-delegation `response.event` payloads are exposed the same way
as `AsyncStream<OpenAILiveResponseEvent>` carrying the nested JSON, decoded only as far as
`type` plus raw value.

Realtime transcription and conversation are independent state machines on the service.
Starting a conversation does **not** stop a transcription session; both would fight for the
microphone, so `startConversation` refuses with `SpeechConversationError.microphoneBusy`
when `realtimeConnectionState.isLifecycleActive`, and vice versa. Documented in README.

### 3.9 Lifecycle inside `OpenAILiveService`

Mirrors `OpenAIRealtimeService` (lifecycle run IDs, single `listeningTask`, duplicate
`session.started` ignored), with these differences:

1. Resolve credential → request mic permission → connect socket → send `session.start`
   → wait for `session.started` → start duplex engine → state `.active(sessionID:)`.
2. Audio send task streams every input chunk; no commit timer, no commit gate.
3. Receive loop routes `session.output_audio.delta` straight to the engine's playback
   queue off the main actor (decode base64 on the socket actor, hop to main only for
   state changes).
4. `endConversation()` sends `session.close`, keeps reading until `session.closed` or
   `closeTimeout`, then tears down. `session.closed` sets `.ended(reason:seconds:)`.
5. `error` events with `client_event_id` are surfaced through the throwing append
   methods; session-level errors set `.error` only if the socket also closes, otherwise
   land in `conversationLastError` and the session stays active (moderation cut-off case).
6. All published errors pass through `SpeechRealtimeErrorRedaction.redacted`.

## 4. Work breakdown

### Phase 0: API spike (0.5 day)

- Tiny throwaway script (Node or `websocat`) against `wss://api.openai.com/v1/live/sessions`
  with a real key. Answer the six open questions in section 2. Record answers at the
  bottom of this file under "Phase 0 findings" and adjust defaults before Phase 1.
- Capture one real `session.started`, `session.output_audio.delta`, both transcript deltas,
  `session.usage.updated`, `session.closed`, and an `error` as JSON fixtures for tests.

### Phase 1: Wire protocol + core types (1 day)

- `Sources/SpeechKit/Conversation/SpeechConversationTypes.swift`: provider enum, state,
  end reason, transcript entry, `SpeechConversationError`, `SpeechConversationTranscriptAssembler`.
- `Sources/SpeechKit/OpenAI/OpenAILiveMessages.swift`: options, validation, all client
  event encoders, `OpenAILiveMessage` decoder with `.unknown(type)` fallback, `OpenAILiveError`.
- `Sources/SpeechKit/OpenAI/OpenAILiveWebSocket.swift`: actor. `makeConnectRequest` is
  `nonisolated static` and tested (bearer header, no query items, endpoint override).
  `connect` sends `session.start` and returns the message stream. `send` helpers for every
  client event. `close()` awaits `session.closed` with timeout.
- Tests: `OpenAILiveMessageTests` (fixture decode round trips, encode snapshots for
  `session.start` with each delegation mode), `SpeechConversationTranscriptAssemblerTests`.

### Phase 2: Duplex audio (1 day)

- Extract shared PCM helpers from `AudioCaptureManager` into `SpeechPCMAudioSupport`
  (behaviour-preserving; existing tests still pass).
- `SpeechDuplexAudioEngine` per section 3.4. Manual test on iPhone with speaker output:
  assistant audio must not re-enter the transcript.
- Tests: playback queue accounting (bytes scheduled vs played) as a pure type;
  WAV writer parity with the existing manager.

### Phase 3: Service + facade + configuration (1 day)

- `OpenAILiveService` per section 3.9, with `setLifecycleStateForTesting` and
  `handleMessageForTesting` like the other services.
- `OpenAIConfiguration` additions per section 3.3; `SpeechService` holds
  `openAILiveService`, applies config in `applyOpenAILiveConfig()`, and exposes the
  facade in `SpeechService+Conversation.swift`.
- `SpeechConversationProvider.allCases` lists `.openAI`.
- Tests: `SpeechServiceTests` additions (not configured → error state; `liveCredential`
  overrides `credential`; transcription active → `microphoneBusy`), `OpenAILiveServiceTests`
  (session.started transitions, duplicate ignored, `session.closed` → `.ended`, usage
  snapshot not summed, transcript grouping through the service), `PublicAPISmokeTests`
  constructibility for every new public type.

### Phase 4: Delegation and context injection (0.5 day)

- Append APIs with acknowledgement matching on `client_event_id` (pending map keyed by
  `event_id`, resolved by the `*.appended` event or rejected by `error.client_event_id`).
- `delegationRequests` and `responseEvents` streams.
- `session.update` for `delegation.responses` via `updateConversationDelegation(_:)`.
- Tests for ack matching and rejection.

### Phase 5: Demo, docs, release (1 day)

- Demo: third mode "Conversation" in the toolbar Mode picker; new
  `Features/Conversation/ConversationView.swift` with interleaved user/assistant rows,
  mute toggle, end button, live usage seconds, voice and instructions in `SettingsSheet`,
  "Use separate GPT-Live key" toggle in `DemoConfiguration`. Reuse `DemoVoiceStage` with
  the output level driving a second ring.
- README: new "Chapter 2b: Speech-to-Speech Conversation" between realtime and file
  chapters, plus a note in "API Key Safety" about `liveEndpoint` proxies and the absence
  of a Live ephemeral-secret endpoint. Update Highlights and Platform Support tables.
- CHANGELOG `[2.1.0]` Added / Changed sections; bump any version literals.
- Run `swift build` for iOS + macOS, `swift test`, and the demo on device.

## 5. Out of scope for this branch (tracked follow-ups)

- WebRTC transport and `POST /v1/live/sessions` (needs a server or a WebRTC dependency).
- Sideband `/attach` and session forks.
- SIP / telephony.
- G.711 formats beyond the option plumbing (no local encoder; leave as opt-in with a note).
- `speechkit-cli` conversation command (separate repo; add after 2.1.0 ships).
- Additional conversation providers (Gemini Live with audio output is the natural second).
- Persisting conversation audio (assistant side) to WAV.

## 6. Risks

- **Echo**: if voice processing IO misbehaves on a device, the model hears itself. Mitigation
  is the `.voiceChat` session mode plus `setVoiceProcessingEnabled`, verified on hardware in
  Phase 2 before anything else lands.
- **No end-of-turn event**: UI must tolerate open-ended entries. The assembler's gap rule
  is a heuristic; expose `turnGapMilliseconds` so apps can tune it.
- **Cost**: sessions bill per second while idle. `endConversation()` must be reliable, and
  the demo should end the session when the view disappears or the app backgrounds.
- **Undocumented voice list and delegation defaults**: Phase 0 exists to de-risk these
  before public types are shaped.

## Status (2026-09-15)

All five phases are implemented on this branch, uncommitted. `swift test` passes
(289 tests, including 2 key-gated integration tests that ran green against the real
API), and the package and demo build for iOS; the package also builds for watchOS.

On-device findings (iPhone, speaker):

- First run reached `session.started` and the engine ran, but the microphone tap never
  fired and zero chunks were sent. Cause: enabling voice processing reconfigures the IO
  unit right after `engine.start()`, which posts `AVAudioEngineConfigurationChange`, and
  an engine that receives it stops silently. Fix: the duplex engine observes that
  notification and restarts itself. After this, the conversation worked end to end.
- An intermediate attempt routed the input node through a muted mixer into the main
  mixer. That was not the fix and it played the microphone back through the speaker
  (own voice, agent heard twice, reverb tail). Removed. The input node stays
  unconnected; a tap alone is enough.
- `os.Logger` diagnostics (subsystem `SpeechKit`, categories `DuplexAudio` and
  `OpenAILive`) stay in for now; consider downgrading the chatty ones to `.debug`.

Still to do before tagging 2.1.0:

- On-device check of echo cancellation and playback latency with the demo's Conversation
  mode (plan §6). Nothing here has been heard through a speaker yet.
- Barge-in behaviour with real overlapping speech (Phase 0 question 3 remains open).
- Decide whether `Scripts/live-spike.mjs` stays in the repo or moves to CONTRIBUTING
  only.
- Fold `AppleSpeechAudioCaptureManager`'s duplicate WAV writer and meter into
  `SpeechPCMAudioSupport` (deferred; behaviour unchanged).
- Set the 2.1.0 date in CHANGELOG and tag.

## Phase 0 findings (2026-09-15, real key, `Scripts/live-spike.mjs`)

Fixtures captured under `Scripts/live-fixtures/{none,responses,client,badvoice}/` (gitignored).

1. **Delegation is optional.** Omitting `delegation` works; the resolved session reports
   `delegation: { type: "client" }`. The model still answers simple questions itself.
   `OpenAILiveDelegation.none` therefore means "omit the field".
2. **Voices:** `marin`, `cedar`, `alloy` all start. An unknown voice is rejected before
   `session.started` with `error { type: "invalid_request_error", code: "forbidden",
   message: "Voice session access denied." }` and the socket closes (1006). The message does
   not enumerate voices, so `OpenAILiveVoice` stays string-backed with those three statics.
3. **Barge-in:** untested (needs interactive audio). Observed that the model can start
   answering before the user transcript finishes (`model [2600-2800) "Paris."` arrived before
   `user [2800-3000) " France?"`), so overlapping entries are real and the assembler must
   keep both rows open.
4. **No short-lived credential path.** `POST /v1/live/client_secrets` → 404. A Realtime
   client secret from `POST /v1/realtime/client_secrets` is rejected by the Live socket
   (non-101). Proxy via `liveEndpoint` is the only key-hiding option.
5. **Session expiry:** `session.started.session.expires_at` is a Unix timestamp two hours
   after start. Expose it as `conversationExpiresAt: Date?`. Idle-timeout probe: see
   `--idle` run notes below.
6. **Billing:** `usage.seconds` was 7 for a session open about 17 s wall-clock; no 15 s
   pre-bill observed on the WebSocket path. `session.usage.updated` arrived once, about
   15 s in, then `session.closed` repeated the same cumulative value.

Other protocol observations that shape the code:

- `session.started.session` also carries `status: "active"` and `input: []`.
- Transcript deltas arrive in 200 ms windows (`start_ms`/`end_ms` multiples of 200) and
  include their own leading spaces or punctuation (`" there"`, `". What is"`). The
  assembler concatenates raw deltas and trims only for display.
- `session.close` is acknowledged by `session.closed` within about a second, then the server
  drops the socket with close code 1006 about two seconds later. Treat 1006 after
  `session.closed` as a normal close, not an error.
- `session.closed` echoes the full `session` snapshot plus `usage.seconds` and `reason`.
- Every server event carries an `event_id`.

Idle probe (`--idle 180`, no audio sent at all):

- The server did not close the session in three minutes; the only known limit is the
  two-hour `expires_at`.
- `session.usage.updated` fires every 15 s. With no audio sent, `usage.seconds` stayed `0`
  for the whole three minutes and `session.closed` reported `0`. So usage counts audio
  streamed, not wall-clock time; an open but silent socket appears to cost nothing.
- Without audio the `context_window` field is absent from `session.usage.updated`, so
  `contextWindowUsageRatio` must be optional.

Command probe (`--probe-commands`, Responses delegation, no audio; fixtures under
`Scripts/live-fixtures/commands*/`):

- **Context appends are not acknowledged until the session timeline advances.** Three
  appends sent into a silent session received no `*.appended` event in 20 s. On
  `session.close` the server emitted one `error` per append with
  `code: "context_injection_incomplete"`, `type: "server_error"`, and the matching
  `client_event_id`, then `session.closed`. So the append API must be fire-and-forget:
  return the client event ID after the socket write and publish acknowledgements and
  rejections through a stream. A timeout that rejects the call would report success as
  failure. `context_injection_incomplete` while ending is benign, not a session error.
- `session.input_audio.muted` / `unmuted` and `session.updated` arrive within about 50 ms
  and carry a top-level `client_event_id`. `session.updated` echoes the full session
  snapshot including `expires_at`.
- `error.client_event_id` is top-level inside the `error` object, alongside `type`,
  `code` (may be JSON `null`), `message`, `param`. An unknown event type lists every
  supported client event: `session.start`, `session.update`, `session.input_audio.append`,
  `session.input_audio.mute`, `session.input_audio.unmute`, `session.instructions.append`,
  `session.thinking.append`, `session.commentary.append`, `response.item.create`,
  `response.create`, `session.close`.
- `response.item.create` requires `item` in Responses input-item shape
  (`{ type: "message", role: "user", content: [{ type: "input_text", text }] }`).
- `response.create` accepts **no** parameters beyond `type`, `event_id`, and
  `delegation_id`; `response`, `instructions`, and any other key are rejected with
  `unknown_parameter`. It runs the backend over the pending items and yields
  `session.delegation.created` followed by nested `response.event`s ending in
  `response.completed`.
- `session.delegation.created` shape: `{ offset_ms, client_event_id, delegation: { id,
  type: "delegation", response_id, target: "responses" | "client" } }`.
