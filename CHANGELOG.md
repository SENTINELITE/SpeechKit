# Changelog

All notable changes to SpeechKit will be documented in this file.

SpeechKit follows semantic versioning. Source-breaking changes ship in a new major version.

## [Unreleased]

### Added

- OpenAI `gpt-transcribe` support for file transcription and committed Realtime turns, including plural language hints, keyword hints, and detected-language decoding.
- OpenAI `gpt-live-transcribe` support for low-latency Realtime transcription, including named latency/accuracy delay tiers.
- Demo controls for OpenAI language lists, keywords, and live transcription delay selection.

### Changed

- OpenAI configuration defaults now use `gpt-transcribe` for files and `gpt-live-transcribe` for Realtime transcription.

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
