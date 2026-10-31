# Fish Audio provider plan

Add Fish Audio to SpeechKit for both file transcription (`transcribe-1-pro`) and realtime transcription (`transcribe-stream-1`, preview), following the same structure as the Mistral provider. Then expose it in the demo app and the speechkit CLI.

Researched 2026-10-29 from docs.fish.audio. Sources are listed at the end.

## API facts

### File transcription: `POST https://api.fish.audio/v1/asr`

- Auth is `Authorization: Bearer <key>`.
- **The model is chosen by an HTTP header, `model: transcribe-1-pro`.** It must be lowercase and an exact match. If the header is missing or wrong, the request silently runs on and is billed as `transcribe-1`, with no error. A `model` field in the body is ignored.
- `transcribe-1` is retired on 2026-12-31, after which everything is served by Pro. We only send Pro.
- The body is `multipart/form-data` (or MessagePack). We use multipart. Fields:
  - `audio`: one file.
  - `language`: a lowercase ISO 639-1 hint. It doesn't force the language; it only helps auto-detection.
  - `ignore_timestamps`: **defaults to `true`**. Send `false` to get word `segments` and `speaker_turns`. Timestamps add processing time.
  - `tag_audio_events`: defaults to `true`. Keeps cues like `[laughter]` in the text.
  - `diarize`: `auto`, `true` or `false`; defaults to `auto`.
  - `num_speakers`, or `min_speakers` / `max_speakers`. These can't be combined with each other, or with `diarize=false`.
  - Booleans in multipart have to be the strings `true` or `false`. Anything else, even `1`, counts as `false`.
- The request is synchronous: the response arrives when the whole file is done. Long files take minutes, and the docs suggest a 15-minute client timeout.
- The response is JSON with these fields:
  - `text`: contains inline `<|speaker:N|>` markers and `[cue]` tags.
  - `duration`
  - `segments`: an array of `{text, start, end}` in seconds. These are words with **no punctuation and no speaker**, and the text may be normalised (for example `35` for `3.5`). The array is empty when timestamps are off, or occasionally when timing is unavailable.
  - `speaker_turns`: an array of `{speaker: "speaker:N", text, start, end}`. The text is punctuated.
  - `language` (an English name), `language_code` and `request_id`.
  - A field that isn't returned is absent from the JSON, never null.
- Limits:
  - 60 minutes of audio (400 `audio_too_long`).
  - Size is limited (413), so send compressed audio. An hour of 128 kbps MP3 is about 55 MiB.
  - Audio under about 0.08 s is rejected (`audio_too_short`).
- Formats:
  - Accepted: WAV, MP3, AAC/M4A/MP4, FLAC, Ogg Opus or Vorbis, WebM, MOV.
  - **Rejected: AIFF, CAF, WMA, AMR, AC-3, raw PCM.**
- Errors are JSON `{status, message, code?, request_id?}`. Branch on `code`:
  - 400 codes: `invalid_request`, `invalid_parameter`, `invalid_audio`, `audio_too_long`, `audio_too_short`.
  - 401 is a bad key and 402 is no credit.
  - 429 is the concurrency limit, sent with no `Retry-After`.
  - 5xx codes, which are retryable: `upstream_unavailable`, `upstream_timeout`, `excessive_repetition`, `diarization_failed`.
  - Errors from the network edge may have no JSON body.
- Price is $0.36 per audio hour.

### Realtime: `wss://api.fish.audio/v1/asr/realtime`

- The connection sends `Authorization: Bearer <key>` and, optionally, a `model: transcribe-stream-1` header. The model is in preview and is the only realtime model.
- **Every message, in both directions, is one MessagePack map in a binary frame.** JSON and text frames are rejected. Audio is MessagePack `bin`, not base64.
- Session flow:
  1. The client sends `config` within 10 s of connecting.
  2. The server replies `session_started` with `{session_id, request_id, config, limits}`.
  3. The client streams `audio {data: bin}`.
  4. For each turn, the server sends `speech_start`, then `draft*`, then `committed`.
  5. When finished, the client sends `audio_done`. The server commits the open turn, sends `session_done`, and closes with code 1000.
- `config` fields:
  - `audio {format: "pcm_s16le", sample_rate, channels: 1}`. The sample rate is one of 8000, 12000, 16000, 22050, 24000, 32000, 44100 or 48000 Hz; 16 kHz is used natively and anything else is resampled on the server.
  - `turn_detection {mode: auto|vad|manual, eager, silence_timeout_ms}`.
  - `results {drafts, ignore_timestamps (default true), diarize (default true), vad_events, eot_events}`.
  - `context {history: ≤32 × 2000 chars, terms: ≤100 × 32 chars}`.
  - `client_reference_id`.
  - **An unknown field is a fatal `invalid_config`** that closes the connection with 4400.
- Server messages:
  - `draft {turn_index, text, settled_text, language_code?}`. Each draft replaces the turn's previous draft, and drafts arrive at most every 250 ms.
  - `committed {turn_index, text, words?: [{text, start_ms, end_ms}], audio_start_ms, audio_end_ms, reason, degraded, user_turn, turn_kind}`.
  - Every server message carries `seq`. Clients must ignore unknown message types and fields.
- **`auto` mode marks other voices and noise as `user_turn: false`** (`turn_kind: "other"`). For a transcription app, as opposed to a voice agent, that could drop real speech from the other people in the room.
- Speakers appear as `<|speaker:N|>` tags inside the text. Sound tags look like `[laughs]`, and the regex `\[[^\[\]]*\]` strips them.
- Limits:
  - 60-minute sessions.
  - 60-second turns.
  - 1 MiB per frame; send 80–100 ms of audio per message.
  - The session closes after 30 s with no client message. Pings count as activity, or send `keepalive`.
- Close codes:
  - 4400: bad config or audio.
  - 4408: idle.
  - 4413: maximum duration reached.
  - 4500: internal error.
  - 1012: `server_restarting`. It's recoverable, but needs a new session.
- If the upgrade is refused, the server returns plain HTTP 401, 402, 429 or 503.
- Price is $0.36 per session hour, billed per second the socket is open, **including idle time**.

## Decisions

1. **Naming: `fishAudio`.** This gives `SpeechFileTranscriptionProvider.fishAudio`, `SpeechRealtimeProvider.fishAudio`, `FishAudioConfiguration`, a `Sources/SpeechKit/FishAudio/` folder and `transcribeFishAudioAudioFile`. It matches `elevenLabs`, and a bare `fish` reads oddly in API listings. If you'd prefer `.fish`, it's a cheap rename to make before any code exists.
2. **No new dependencies.** SpeechKit has none today. A small internal MessagePack codec of about 250 lines covers what realtime needs: maps, strings, bin, integers, floats, bools, nil and arrays. It's internal and tested with known byte vectors. File transcription uses multipart and doesn't need it.
3. **Always send `model: transcribe-1-pro`** on file requests. Using the wrong model fails silently, so a unit test checks the header.
4. **Map the response to SpeechKit's generic result:**
   - Text has the speaker markers removed.
   - Words come from `segments`, and each word's speaker is taken from the `speaker_turns` entry that contains its midpoint.
   - **Punctuation transfer.** Segments have no punctuation, but the CLI's sentence splitter relies on it. We walk the punctuated `speaker_turns` text and the segment list together, matching tokens case-insensitively, and attach any trailing punctuation to the matching segment. If a token doesn't match (because of normalisation such as `35` vs `3.5`), we leave that word as is and resync on the next match.
   - The detailed API (`FishAudioFileTranscriptionResponse`) keeps the raw text, segments, speaker turns, language and request ID untouched.
5. **Sound tags are kept by default**, matching Fish. `tagAudioEvents: false` sends `tag_audio_events=false`. The generic `text` keeps them too: they're useful, and they're easy to strip later.
6. **Timestamps default to on (`ignore_timestamps=false`)** for file transcription. Every other SpeechKit provider returns words, and the CLI's timestamped output and sentence lines need them. The extra latency is documented on the option.
7. **Unsupported formats:**
   - AIFF and CAF are rejected up front with a clear `SpeechError` before uploading.
   - Duration is checked with `SpeechFileUploadSupport.validateFileDuration(maxDuration: 3600)`.
   - Transcoding CAF or AIFF to M4A is a follow-up, not part of this plan.
8. **Realtime defaults suit transcription, not voice agents:**
   - `mode: auto`, `drafts: true`, `ignore_timestamps: false`, `diarize: true`, 16 kHz mono PCM, and 100 ms chunks.
   - **Every non-empty committed turn is emitted, including `user_turn: false`.** Each entry exposes `turnKind` so voice-agent code can filter. Turns that are empty or contain only tags are dropped.
   - Agent features are exposed as options (`eager`, `silenceTimeout`, `terms`, `history`). `agent_speaking` and `context_add` are methods on `FishAudioRealtimeService`. The generic `SpeechService` API doesn't need them.
9. **Realtime mapping onto `SpeechTranscriptEntry`:**
   - A `draft` becomes an entry with `isFinal: false`, keyed by `turn_index` so the UI replaces it.
   - A `committed` turn becomes `isFinal: true, isUtteranceFinal: true`. It gets `start = audio_start_ms/1000`, `duration` from the turn's start and end, words converted from ms to s, and a speaker from the first `<|speaker:N|>` tag. If a turn contains several speaker tags, it's split into one entry per tag.
   - A `degraded: true` commit is still emitted, with no words.
10. **Realtime lifecycle:**
    - Stopping sends `audio_done`, waits up to 5 s for `session_done`, then closes.
    - When the microphone is paused, the client sends `keepalive` every 15 s. That's needed because the session closes after 30 s idle and is billed while open.
    - On `server_restarting` (close 1012), the error is surfaced. Auto-reconnect is a follow-up.
11. **Credentials:** Fish has no short-lived tokens. Both `SpeechCredential.apiKey` and the fetch-based `.token` work, because either way the value is sent as the bearer. As with the other providers, the docs warn that shipping a raw key in an app exposes it.
12. **No automatic retries.** This matches the other providers. Error codes are mapped so callers can tell retryable errors (429, 5xx) from fatal ones.

## Phases

### Phase 0: prerequisites
- [ ] Commit the uncommitted Mistral work on main first, so Fish starts from a clean tree.
- [ ] Get a Fish API key for live smoke tests. It goes in `.env` as `FISH_API_KEY`, which is already gitignored.

### Phase 1: file transcription
- [ ] `Sources/SpeechKit/FishAudio/FishAudioFileTranscriptionClient.swift`. It builds the multipart request, sets the model header, decodes the response and maps errors from `code` and the HTTP status.
- [ ] Types:
  - `FishAudioFileTranscriptionModelID` (`transcribe1Pro`).
  - `FishAudioFileTranscriptionOptions`: `language`, `timestamps`, `diarize` (auto/on/off), `speakerCount` (exact or a range), `tagAudioEvents`, `timeoutInterval`, with a default of 900 s.
  - `FishAudioFileTranscriptionResponse`, plus segment and speaker-turn types.
- [ ] Validation:
  - Speaker hints can't be combined with each other, or with `diarize: off`.
  - The language must be two lowercase letters.
  - AIFF and CAF are rejected.
  - Audio over 60 minutes is rejected.
- [ ] Speaker assignment and punctuation transfer into the generic result (decision 4).
- [ ] `FishAudioConfiguration`: `credential`/`apiKey`, file defaults, `realtimeOptions`, `timeoutInterval`, `fileEndpoint`, `realtimeEndpoint`.
- [ ] Wiring:
  - `SpeechFileTranscriptionProvider.fishAudio` and its `allCases` list.
  - `SpeechFileTranscriptionOptions.fishAudio(...)` and its `provider` switch.
  - `SpeechService.fishAudio`, plus an `init` parameter after `mistral:`.
  - Add `.fishAudio` to the provider switch in `SpeechService+FileTranscription.swift`, and add a `resolvedFishAudioOptions` helper next to `resolvedMistralOptions`.
  - Public `transcribeFishAudioAudioFile(file:options:)` and its security-scoped twin.

### Phase 2: realtime
- [ ] `FishAudio/MessagePack.swift`: an internal encoder and decoder covering the subset above.
- [ ] `FishAudioRealtimeMessages.swift`:
  - Client messages: `config`, `audio`, `finalize`, `configure`, `context_add`, `keepalive`, `audio_done`, `agent_speaking`.
  - Server messages: `session_started`, `speech_start`, `user_turn_taken`, `draft`, `eager_end_of_turn`, `turn_resumed`, `user_backchannel`, `committed`, `progress`, `configured`, `error`, `session_done`, plus an `unknown` case.
- [ ] `FishAudioRealtimeWebSocket.swift`. It uses a `URLRequest` with the auth and model headers, binary frames only, and maps close codes and HTTP refusals to errors.
- [ ] `FishAudioRealtimeService.swift`. It follows `MistralRealtimeService`: `AudioCaptureManager` at 16 kHz, 100 ms chunks, the decision 9 mapping and the decision 10 lifecycle. It also exposes `agentSpeaking(_:)`, `addContext(_:)` and `finalizeTurn()`.
- [ ] `FishAudioRealtimeOptions`: `mode`, `eager`, `silenceTimeout`, `drafts`, `timestamps`, `diarize`, `terms`, `history`, `sampleRate`. Validate the ranges before connecting, because a bad config kills the session.
- [ ] Wiring:
  - `SpeechRealtimeProvider.fishAudio`, plus a case in the switch in `SpeechService+Realtime.swift`.
  - `fishAudioRealtimeService` and `applyFishAudioRealtimeConfig()` in `SpeechService.swift`.

### Phase 3: tests (`Tests/SpeechKitTests/FishAudioProviderTests.swift`)
- [ ] MessagePack round trips and fixed byte vectors (fixmap/map16, str8/16, bin8/16/32, int and uint sizes, float64, nil, bool, nested values).
- [ ] The file request: the method, URL, auth header, **exact `model: transcribe-1-pro` header**, multipart field names, and boolean strings.
- [ ] Response parsing: diarized and undiarized responses, empty segments, missing optional fields, marker stripping, speaker assignment, and punctuation transfer, including the normalisation-mismatch case.
- [ ] Error mapping for each documented `code`, a platform error with no code, and a 413 with no body.
- [ ] Option validation.
- [ ] Realtime with a fake socket: the order `config` → `session_started`, draft replacement, commit mapping, multi-speaker splitting, the degraded commit, a non-user turn being kept and tagged, an empty or tag-only turn being dropped, the `audio_done` → `session_done` shutdown, `server_restarting`, unknown message types being ignored, and config validation.
- [ ] Live smoke tests, gated on `FISH_API_KEY` and skipped otherwise: a short WAV file and a 10-second realtime stream.

### Phase 4: docs and release notes
- [ ] DocC: `ProviderConfiguration.md`, `FileTranscription.md`, `RealtimeTranscription.md`, `ProviderHowToGuides.md` (a Fish Audio section) and `SpeechKit.md`.
- [ ] README: the provider table, a configuration snippet, and notes on the format limits, the 60-minute limit and the preview status.
- [ ] CHANGELOG under Unreleased. The new enum cases count as a minor bump.

### Phase 5: demo app
- [ ] `DemoConfiguration` (key and options), `DemoProviderControls`, `ProviderSettingsView` (the API key field), and the file and recorded-upload views. These are the same touch points as the Mistral diff.

### Phase 6: speechkit CLI (`../speechkit-cli`)
- [ ] Add a provider `fish-audio` with an alias `fish`, read from the `FISH_API_KEY` environment variable or the keychain, like the other cloud providers.
- [ ] Capabilities: words, diarization and a language hint. It doesn't support vocabulary for file transcription; realtime `terms` only applies to realtime.
- [ ] Sentence cues: with punctuation transfer in place, use `sentences` as the default cue mode, as VOZ does. Otherwise fall back to `speaker_turns` as segments.
- [ ] Bench support, plus a version bump, README and CHANGELOG updates.

## Release

The Mistral work is still in Unreleased, planned for 2.1.0. My recommendation is to commit Mistral first, then add Fish Audio to the same Unreleased 2.1.0 section if 2.1.0 hasn't been tagged by then. Otherwise it ships as 2.2.0. Either way, it's a minor bump, nothing is pushed until you say so, and the work happens on local main.

## Risks

- **The realtime model is in preview.** Its message set may grow. The client already ignores unknown types and fields, but `config` rejects unknown fields, so we only send documented ones.
- **Punctuation transfer is best effort.** Heavy normalisation (numbers, symbols, CJK) will leave some words without punctuation. The CLI's pause and speaker rules still split those sentences.
- **Silent model fallback** if the header ever regresses. The header test guards against it.
- **Billing while idle.** Realtime is billed while the socket is open, so the demo should stop sessions promptly. Worth stating in the docs.
- **No browser-safe tokens.** This is the same situation as the other providers that use API keys.

## Sources

- [Speech to Text API reference](https://docs.fish.audio/api-reference/endpoint/openapi-v1/speech-to-text)
- [Realtime STT WebSocket reference](https://docs.fish.audio/api-reference/endpoint/websocket/asr-realtime.md)
- [Realtime Speech to Text guide](https://docs.fish.audio/features/speech-to-text/realtime)
- [Migrate from transcribe-1](https://docs.fish.audio/developer-guide/models-pricing/migrate-from-transcribe-1.md)
- [Pricing and rate limits](https://docs.fish.audio/developer-guide/models-pricing/pricing-and-rate-limits.md)
