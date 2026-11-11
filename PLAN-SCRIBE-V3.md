# ElevenLabs Scribe v3 plan

Add ElevenLabs Scribe v3 (`scribe_v3`, file) and Scribe v3 Live (`scribe_v3_live`, realtime) to SpeechKit. Make them the defaults, use turn prediction for realtime, and expose diarization (file and realtime) plus the other new request options. Then update the relay, the demo app and the speechkit CLI.

Researched 2026-11-10 from elevenlabs.io/docs. Sources are listed at the end.

## Status of the user's decisions

Decided by the user on 2026-11-10:

- **Defaults move to v3.** File transcription defaults to `scribe_v3` and realtime defaults to `scribe_v3_live`.
- **Realtime commits with turn prediction.** `commit_strategy=turn_prediction` is the default on v3 Live.

Decided by the user on 2026-11-10, after the first draft:

- **A. Scope:** core set plus `no_verbatim` and entity detection. Leave out transcript editing, speaker roles, the speaker library, multichannel, webhooks, `source_url` and zero retention for now. (Recommendation, not objected to.)
- **B. Same pass:** relay, CLI and demo all change in this pass. (Recommendation, not objected to.)
- **C. Paid add-ons: deferred.** Don't add cost notes or a separate API for them in this pass.
- **D. Version: fold into the unpublished 3.0.0.** No 3.1.0. The CLI's 0.12.0 is also unpublished (no remote), so its changes fold into 0.12.0 too.
- **Keyterm library cap: 10,000 terms** for now.

## API facts

### File transcription: `POST https://api.elevenlabs.io/v1/speech-to-text`

- Auth uses the `xi-api-key` header, or a `token` query parameter (single-use, from `/v1/single-use-token/batch_scribe`). This is unchanged.
- The body is `multipart/form-data`. `model_id` is required. Provide exactly one of `file` or `source_url`.
- Model IDs: `scribe_v3` (new), `scribe_v2`, `scribe_v2_medical` (same request shape and price as v2), and `scribe_v1` (deprecated; removed 2026-07-09).
- Limits: up to 5 GB and 15 hours of audio per request, and at least 100 ms of audio. SpeechKit currently enforces 3 GB and 10 hours.
- Fields this plan uses. Booleans are the strings `true` or `false`.
  - `language_code`: ISO-639-1 or 639-3. Omitted means the language is detected automatically.
  - **`secondary_language_codes`** (v3 only): other languages expected in the audio. **Repeat the form field once per code**; a JSON array sent as one string is rejected. Unknown codes are skipped silently.
  - **`numbers_format`** (v3 only): `digits` or `words`. Omitted means the model chooses.
  - `diarize`: labels each word with a speaker.
  - `num_speakers`: the maximum number of speakers, 1–32. Omitted means the model maximum.
  - `diarization_threshold`: a double, usually 0.22 by default. **Only valid when `diarize=true` and `num_speakers` is not set.** Higher values predict fewer speakers.
  - `keyterms`: a repeated field. Limits: ≤1000 terms, each ≤50 characters and ≤5 words, and none of `< > { } [ ] \`. Costs 20% extra, and more than 100 terms adds a 20-second billing minimum.
  - `tag_audio_events`: marks sounds such as laughter. They come back as words with `type: "audio_event"`.
  - `no_verbatim`: removes filler words and false starts.
  - `timestamps_granularity`: `none`, `word` or `character`.
  - `entity_detection`: `all`, a category (`pii`, `phi`, `pci`, `other`, `offensive_language`), or specific types. Results return as `entities[]`.
  - Sending a v3-only field with another model returns `invalid_parameters`.
- Response fields (`SpeechToTextChunkResponseModel`):
  - Always present: `text`, `language_code`, `language_probability` and `words[]`.
  - Optional: `transcription_id`, `audio_duration_secs`, `entities[]`, `additional_formats`, `channel_index` and `edited_transcript`.
- Word fields:
  - Always present: `text`, `type` (`word`, `spacing` or `audio_event`) and `logprob`.
  - Optional: `start`, `end`, **`speaker_id`** (`speaker_0`, `speaker_1`, …) and `characters`.
- Entity fields: `text`, `entity_type`, `start_char` and `end_char`.

### Realtime: `wss://api.elevenlabs.io/v1/speech-to-text/realtime`

- Every option is a query parameter, set on the URL when connecting.
- Model IDs: `scribe_v3_live` (new) and `scribe_v2_realtime`.
- **`commit_strategy`**: `manual`, `vad` or `turn_prediction`. **The default is `manual` for every model**, so today SpeechKit never commits. Segments become final only at the server's automatic commit after about 36 s, or at `end_of_stream`.
  - `turn_prediction` works only on v3 Live; other models return `invalid_request` and the connection closes. The server commits when `turn_probability` reaches 0.9 or more. VAD stays active as a fallback, and the VAD parameters apply.
  - VAD parameters: `vad_silence_threshold_secs` (0.192–3.0), `vad_threshold`, `min_speech_duration_ms` and `min_silence_duration_ms`.
- v3 Live adds **`turn_probability`** to every `partial_transcript`, whatever the commit strategy.
- **`diarize=true`** works only on v3 Live, and can't be combined with `filter_background_audio`. Either mistake returns `invalid_request` and closes the connection. With diarization on:
  - `partial_transcript` carries provisional `words[]`. Each word's `speaker_id` is `null` until the speaker is resolved, and its timestamps may be missing.
  - `committed_transcript` gains an integer `segment_index`. Diarization doesn't delay it.
  - Each commit is followed by a **`diarized_transcript {segment_index, text, words}`**, sent in commit order. It is always sent, even if every speaker stays `null`. **Match it by `segment_index`, not by order or text.**
  - **`speakers_merged {from_speaker_id, to_speaker_id}`** means every earlier `from` label must be rewritten as `to`, in all stored words. Merges chain, so apply them in the order received. IDs are never reused.
- `language_code` and **`secondary_languages`** (repeated) limit language detection to the listed languages.
- **`multilang_mode=true`** (v3 Live only) follows language switches mid-sentence. It can pick up background speech, and short phrases are more often wrong.
- `keyterms`: repeated query parameters. The overview gives limits of 50 terms of 20 characters each for realtime.
- **`keyterm_library`** (v3 Live only):
  - It's an array sent in the **first** `input_audio_chunk` only.
  - Limits: ≤10,000 terms (one overview line says 100,000, so we use 10,000), ≤50 characters each, and ≤2 MB in total.
  - Sending it later, or over the limits, returns `input_error` and the connection closes.
  - It's billed once, together with `keyterms`.
- Other parameters this plan uses: `include_timestamps`, `include_language_detection`, `no_verbatim` and `entity_detection` (results arrive as `committed_transcript_entities`).
- Parameters that exist but aren't in scope: `filter_background_audio` (can't be combined with `include_timestamps` or `diarize`), `keepalive_interval_ms`, `transcript_edit`, `entity_redaction` and `enable_logging`.
- Server errors arrive as messages whose `message_type` is one of `error`, `auth_error`, `quota_exceeded`, `commit_throttled`, `rate_limited`, `queue_overflow`, `resource_exhausted`, `session_time_limit_exceeded`, `input_error`, `invalid_request`, `chunk_size_exceeded`, `insufficient_audio_activity` or `transcriber_error`, each with an `error` string. **SpeechKit currently ignores all of these as `.unknown`.**
- Client messages:
  - `input_audio_chunk {audio_base_64, commit, sample_rate, previous_text?, keyterm_library?}`. `previous_text` and `keyterm_library` are allowed in the first chunk only.
  - `end_of_stream`.

## What SpeechKit has today

- **File client** (`ElevenLabsFileTranscriptionClient.makeRequest`): sends only `model_id` and `file`. The response decodes only `text`, `language_code` and `words`, and `ElevenLabsWordTimestamp` has no `speaker_id`. The 3 GB and 10 h limits are older than the current 5 GB and 15 h.
- **Realtime** (`ElevenLabsWebSocket.makeConnectRequest`): sends only `model_id`. With no commit strategy and no commit messages, segments become final only every ~36 s. The client decodes four message types and treats errors as unknown.
- **Options:** `SpeechFileTranscriptionOptions.elevenLabs(modelID:)` takes a model only. `ElevenLabsConfiguration` holds models and endpoints but has no realtime options struct, unlike Grok, Meta, Mistral and Fish Audio.
- **Relay:**
  - `speechkit-relay/src/streams.ts:19` accepts only the `file` and `model_id` form fields.
  - `src/routes.ts:188` accepts only the `model_id` query parameter on the WebSocket.
  - `src/websocket.ts:80` rejects unknown keys in client messages, so `keyterm_library` would be refused.
  - The model allowlists (`routes.ts:95-96`) contain only `scribe_v1,scribe_v2` and `scribe_v2_realtime`.
- **CLI:** `ElevenLabsRunner` handles file transcription only, and lists `scribe_v1` and `scribe_v2`.
- **Demo:** `DemoConfiguration.swift:926` builds `.elevenLabs(modelID:)`.

## Decisions

1. **Fold into 3.0.0, not 3.1.0.** 3.0.0 (8bf8f6a) is committed locally but not published; 2.0.1 is the last published release. This work changes defaults and extends the `.elevenLabs(...)` option case, which breaks any external `case .elevenLabs(let modelID)` pattern match. Inside an unpublished major that costs nothing. (Confirmed by the user.)
2. **Option shape follows Mistral and Fish Audio.**
   - A new `ElevenLabsFileTranscriptionOptions` struct holds the file defaults in `ElevenLabsConfiguration.fileOptions`. The per-request enum case `.elevenLabs(modelID:language:secondaryLanguages:numbersFormat:diarize:speakerCount:diarizationThreshold:keyterms:tagAudioEvents:noVerbatim:entityDetection:timeoutInterval:)` takes optional overrides, all defaulted to `nil`.
   - A new `ElevenLabsRealtimeOptions` struct sits in `ElevenLabsConfiguration.realtimeOptions`.
3. **The commit strategy default is `.automatic`, which resolves by model.** `scribe_v3_live` gets `turn_prediction`. `scribe_v2_realtime` gets `vad`, because it rejects turn prediction and `manual` never commits. An explicit `.manual`, `.vad` or `.turnPrediction` is sent as given. SpeechKit itself never sends manual commits; `.manual` is for callers who commit with a new `commitRealtimeSegment()`.
4. **Check combinations locally before connecting or uploading**, and throw `SpeechError` with `.invalidOptions`. The server would otherwise return a vague 422, or close the socket mid-start. Checks:
   - v3-only fields (`numbersFormat`, `secondaryLanguages` on file; `diarize`, `multilingual`, `turnPrediction` and `keytermLibrary` on realtime) used with another model.
   - `diarizationThreshold` without `diarize`, or together with `speakerCount`.
   - `speakerCount` outside 1–32.
   - Keyterm count, length, word count or forbidden characters.
   - `keytermLibrary` over 10,000 terms, 50 characters per term or 2 MB in total.
   - `diarize` combined with background filtering. That combination can't occur until background filtering is exposed.
5. **Speaker labels stay raw** (`speaker_0`). Fish Audio's labels likewise keep the vendor's format. Apps that want "Speaker 1" can map labels themselves.
6. **Realtime diarization is resolved inside SpeechKit**, so apps never see a stale label:
   - `committed_transcript` appends an entry at once, with `sourceID: "segment:N"` and no speaker, so text isn't delayed.
   - The matching `diarized_transcript` replaces that entry. It becomes **one entry per consecutive run of the same speaker**: the first run keeps the original entry `id`, and every run keeps `sourceID "segment:N"` and has `speaker` and `words` set. A segment with only `null` speakers stays a single entry with words.
   - `speakers_merged` is recorded in an alias map. SpeechKit rewrites `speaker` on every stored entry and word, applying chained merges in order. Because entries are value types, this means rebuilding the affected entries with the same `id`, so SwiftUI keeps their identity.
   - The partial (live) entry carries words with draft speakers, after the alias map is applied.
   - A `diarized_transcript` for an unknown or already-cleared segment is dropped.
7. **Turn probability is exposed, not just used.** `ElevenLabsRealtimeService.turnProbability: Double?` is updated on each partial and reset on commit. It also appears on the realtime facade for `.elevenLabs` if the facade has a matching slot; check `SpeechService+Realtime.swift`.
8. **Realtime error messages become errors.** Each error type decodes into `ElevenLabsError.serverError(type, reason)`, sets `lastError` and ends the session. The vendor's `error` text is used only through the existing safe error mapping (`SpeechErrorBoundary`), never shown raw. `warning` is logged, not surfaced.
9. **File limits are raised to 5 GB and 15 h** to match ElevenLabs. The relay keeps its own tighter limits.
10. **The detailed file response grows by addition only.** New fields: `languageProbability`, `audioDurationSeconds`, `transcriptionID` and `entities: [ElevenLabsEntity]?`. `ElevenLabsWordTimestamp` gains `speakerID`. `start`, `end` and `logprob` become optional, because the docs mark them optional (audio events and unaligned partial words). Making them optional is source-breaking, which is one more reason to fold into 3.0.0. The normalized `SpeechTranscriptWord` mapping passes `speaker` through.
11. **`scribeV2Medical` is added** as a file model. It needs no new options.

## Phases

### Phase 0: prerequisites

- Get answers to questions A–D.
- Check that the ElevenLabs key in the demo or CLI keychain works with `scribe_v3` and `scribe_v3_live`, using one curl and one websocat call by hand.
- Record two fixtures: a short clip with three or more speakers, and a clip that switches language.

### Phase 1: models and file transcription

1. Update `ElevenLabsMessages.swift`:
   - Add `scribeV3 = "scribe_v3"`, `scribeV3Live = "scribe_v3_live"` and `scribeV2Medical = "scribe_v2_medical"`, and update `allCases`.
   - Replace the string check in `supportsFileTranscription` with a switch, and add `supportsRealtime` and `isScribeV3` helpers.
2. Add `ElevenLabsFileTranscriptionOptions` (Decision 2) in a new `ElevenLabs/ElevenLabsOptions.swift`, along with:
   - `ElevenLabsNumbersFormat` (`digits`, `words`).
   - `ElevenLabsEntityDetection`: `.all`, `.categories([ElevenLabsEntityCategory])` or `.types([String])`.
   - `ElevenLabsCommitStrategy` (Decision 3).
3. Update `ElevenLabsConfiguration`:
   - Change the defaults to `.scribeV3Live` and `.scribeV3`.
   - Add `fileOptions` and `realtimeOptions`.
   - Keep both inits source-compatible by giving the new parameters defaults.
4. Update `ElevenLabsFileTranscriptionClient`:
   - `makeRequest(file:options:secret:)` emits the multipart parts. Repeated parts carry `keyterms` and `secondary_language_codes`, and only fields that are set are sent.
   - Run the Decision 4 checks before any I/O.
   - Raise the limits (Decision 9).
5. Response: apply Decision 10.
6. Public API:
   - Add `transcribeElevenLabsAudioFile(file:options:)` and its security-scoped twin.
   - Keep the `modelID:` overloads as convenience calls into it.
   - Update `resolvedElevenLabsModelID` into `resolvedElevenLabsOptions`, so request overrides are merged over the configuration defaults.
7. Normalized results: the generic file transcription path keeps returning text. Where the shared result type carries words, include speakers.

### Phase 2: realtime

1. Add `ElevenLabsRealtimeOptions` with:
   - `language`, `secondaryLanguages` and `multilingual`.
   - `commitStrategy` (default `.automatic`).
   - The VAD tuning fields, each optional.
   - `diarize`, `keyterms`, `keytermLibrary`, `includeTimestamps`, `noVerbatim`, `entityDetection` and `previousText`.
2. `ElevenLabsWebSocket.makeConnectRequest(credential:modelID:options:endpoint:)` builds the query string, repeating items for `keyterms` and `secondary_languages`. Run the Decision 4 checks there.
3. `InputAudioChunk` gains optional `previous_text` and `keyterm_library`, encoded only when non-nil. `sendAudioChunks` adds them to the first chunk of a run only.
4. Messages:
   - Add `segment_index` and `turn_probability` to `PartialTranscript` and `CommittedTranscript`, and `words` to `PartialTranscript`.
   - Add new cases `diarizedTranscript`, `speakersMerged`, `committedTranscriptEntities`, `warning` and `serverError`.
   - `SessionConfig` currently requires `vad_commit_strategy` and other fields that newer servers may rename. Make every field optional so a schema change can't fail `session_started`.
5. In `ElevenLabsService`, apply Decisions 6, 7 and 8. Add `commitRealtimeSegment()`, which sends an empty chunk with `commit: true` and is allowed only when the strategy is `.manual`. Reset the alias map, the segment index table and `turnProbability` on start and on clear.
6. Fix the existing commit behaviour: v2 Realtime now commits by VAD (Decision 3).

### Phase 3: relay (`../speechkit-relay`)

1. Update the model allowlists to `ELEVENLABS_FILE: "scribe_v2,scribe_v3,scribe_v2_medical"` and `ELEVENLABS_REALTIME: "scribe_v2_realtime,scribe_v3_live"`. Decide whether to keep `scribe_v1`; it's removed upstream, so drop it.
2. File form fields (`streams.ts`): allow:
   - `language_code`, `diarize`, `num_speakers`, `diarization_threshold` and `numbers_format`.
   - `tag_audio_events`, `no_verbatim` and `timestamps_granularity`.
   - The repeated fields `secondary_language_codes`, `keyterms` and `entity_detection`.

   Validate each value in `validateOption`: booleans; 1–32; 0–1; enums; ≤50 characters with no control characters; and a count cap per repeated field. Check that the `seen` set allows these fields to repeat.
3. WebSocket query (`routes.ts`): allow:
   - `language_code`, `commit_strategy`, the VAD fields, `diarize` and `multilang_mode`.
   - `include_timestamps`, `include_language_detection`, `no_verbatim` and `previous_text`.
   - The repeated fields `secondary_languages`, `keyterms` and `entity_detection`.

   Check the existing `query.toString().length > 8192` limit against 50 realtime keyterms.
4. Client messages (`websocket.ts`): accept `keyterm_library` in the **first** `input_audio_chunk` only, as an array of strings within the vendor limits. This frame can be up to ~2 MB. Check the relay's frame and message size limits, and decide whether to cap it lower.
5. Add relay tests for each new field (accepted, rejected, repeated) and the first-chunk-only rule. Update the relay README option table.

### Phase 4: tests (`Tests/SpeechKitTests/ElevenLabsProviderTests.swift`, new)

- File request building:
  - Each field appears as a multipart part, with repeated parts for lists.
  - Unset fields are absent.
  - Every Decision 4 rule throws.
  - v3-only fields are rejected on v2.
- File response decoding:
  - Speakers, audio events with no timestamps, entities and `language_probability`.
  - A captured v3 response fixture.
- Realtime connection URL: the commit strategy each model resolves to, repeated query items, and diarization or multilingual mode rejected on v2.
- First chunk: `previous_text` and `keyterm_library` are sent once only.
- Diarization state machine, fed recorded message sequences:
  - commit then diarized, giving a split into speaker runs with ids kept;
  - an out-of-order or unknown `segment_index`;
  - a chained `speakers_merged` across stored and partial words;
  - all-`null` speakers;
  - a clear in the middle of a session.
- Turn probability is updated, then reset on commit.
- Each server error message type maps to an error, and the vendor text never leaks.
- Update the existing tests that assume `scribe_v2` defaults (`SpeechServiceTests.swift:34`, `PublicAPISmokeTests`).
- Run the full `swift test` suite, then a manual live test against both fixtures with direct and relay credentials.

### Phase 5: docs and release notes

- DocC:
  - `ProviderConfiguration.md`, `FileTranscription.md` and `RealtimeTranscription.md`: a diarization section, the turn-prediction default, and a table of model-only options. No cost notes (Question C is deferred).
  - `ProviderHowToGuides.md`: an ElevenLabs diarization example.
  - `MigratingTo3.md`: the default models change to v3, the `.elevenLabs(...)` case is extended, and the timestamp fields become optional.
- README: the provider table and model list.
- CHANGELOG under 3.0.0.

### Phase 6: demo app

- Add v3 models to the model pickers, with v3 as the default.
- ElevenLabs settings:
  - Diarization toggle, speaker count, numbers format, secondary languages and a keyterms field.
  - Realtime: diarization, multilingual mode and a commit strategy picker.
- The transcript view shows speaker labels for ElevenLabs entries (check whether the Fish Audio speaker UI can be reused), and a small turn-probability meter while listening.

### Phase 7: speechkit CLI (`../speechkit-cli`)

- `ElevenLabsRunner`:
  - `fileModelIDs` becomes `scribe_v3`, `scribe_v2` and `scribe_v2_medical`, with v3 as the default.
  - Pass `--language` through instead of warning that it's ignored.
  - Add `--diarize`, `--speakers N`, `--numbers digits|words`, `--secondary-language` (repeatable), `--keyterm` (repeatable), `--tag-audio-events` and `--no-verbatim`.
- Map `speaker_id` into the transcript document, so the existing speaker output formats work.
- Fold into the unpublished 0.12.0 (no version bump), and update PLAN-CLI.md's log and the CHANGELOG.

## Release

- Commit SpeechKit, relay and CLI locally, one commit per repo, plus the demo commit. **Push nothing until the user says so.**

## Risks

- **Doc conflicts.** The keyterm library limit appears as both 10k and 100k terms; we use 10k. The realtime `session_started` enum lists only `manual` and `vad`, so `SessionConfig` must tolerate `turn_prediction` (Phase 2.4). The realtime keyterm limits (50 × 20 characters) appear only in the overview.
- **Turn prediction can commit mid-thought** at a 0.9 probability, and that threshold isn't configurable. VAD is still the fallback.
- **Rebuilding entries on merge** changes `entries` after the fact. Apps that copied entries out won't see relabels. Document this.
- **One `diarized_transcript` can split into several entries,** so entry counts change. Apps that index by position (not `id`) could misbehave.
- **Multipart booleans:** confirm that ElevenLabs accepts the strings `true` and `false` for every boolean field, including `diarize` on v3.
- **The relay keyterm-library frame** (up to 2 MB) may exceed the relay's frame limit. Phase 3.4 decides the cap.
- **The SDKs lag the API.** ElevenLabs' own SDKs don't support `numbers_format`, `secondary_language_codes`, `multilang_mode`, `keyterm_library` or `turn_prediction` yet, so there's no reference implementation to compare against. Rely on the raw-API docs and live tests.

## Sources

- https://elevenlabs.io/blog/scribe-v3
- https://elevenlabs.io/speech-to-text-api
- https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- https://elevenlabs.io/docs/api-reference/speech-to-text/v-1-speech-to-text-realtime
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/diarization
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/language-options
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/number-and-language-options
- https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/batch/keyterm-prompting
- https://elevenlabs.io/docs/overview/capabilities/speech-to-text
