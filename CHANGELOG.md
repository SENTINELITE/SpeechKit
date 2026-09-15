# Changelog

All notable changes to SpeechKit will be documented in this file.

SpeechKit follows semantic versioning. Source-breaking changes ship in a new major version.

## [Unreleased]

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
- Gemini Live token connections now send the credential in an `Authorization: Token` header instead of the socket URL. API-key connections still use the `key` query parameter.
- `SpeechFileTranscriptionProvider`, `SpeechRealtimeProvider`, and `SpeechFileTranscriptionOptions` gained `meta` and `gemini` cases, so exhaustive switches over these types in adopting code need updating.
- `apiKey` on every provider configuration and realtime service is now a computed projection of the new `credential` property: reading it returns the key of an `.apiKey` credential and an empty string for a `.token` credential, and writing it replaces `credential` with `.apiKey`.
- Token-backed configurations compare equal by `SpeechTokenProvider.id`.

### Fixed

- Realtime services now ignore duplicate session-established messages instead of restarting audio capture, which previously left two consumers reading one audio stream.
- Meta keyword validation now rejects CRLF line breaks.
- `GeminiConfiguration.realtimeModelID` was ignored; `SpeechService` now applies it over `GeminiRealtimeOptions.modelID` when configuring or starting a Gemini Live session.
- Gemini realtime transcripts no longer collapse two identical consecutive utterances into one entry, and a repeated `setupComplete` acknowledgement no longer orphans the first audio task.
- Gemini realtime errors are redacted before publication so an API key carried in the Live socket URL cannot reach `lastError`.
- Cancelling a Gemini background transcription or Files API upload now rethrows `CancellationError` instead of a provider failure.
- Meta raw PCM uploads are duration-checked from their byte count before upload, since AVFoundation cannot measure headerless audio.

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
