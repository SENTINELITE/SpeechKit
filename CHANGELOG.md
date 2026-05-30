# Changelog

All notable changes to SpeechKit will be documented in this file.

SpeechKit follows semantic versioning. Source-breaking changes may still ship before `1.0.0`; after `1.0.0`, source-breaking changes should ship in a new major version.

## [Unreleased]

## [0.9.0] - 2026-05-30

### Added

- Provider-neutral `SpeechService` facade for realtime microphone transcription and audio file transcription.
- Realtime transcription support for ElevenLabs, OpenAI, and xAI Grok.
- File transcription support for ElevenLabs, Aqua, Cohere, Grok, and OpenAI.
- OpenAI diarization options for `gpt-4o-transcribe-diarize`, including automatic chunking, server VAD tuning, known speaker references, and diarized segment decoding.
- DocC documentation for getting started, provider configuration, realtime transcription, file transcription, error handling, and security-scoped files.
- GitHub Actions CI for SwiftPM build/test and generic platform builds across macOS, iOS, watchOS, and visionOS.

### Changed

- Hardened realtime start/stop behavior so duplicate starts, stops, provider switches, and stale async callbacks are handled safely.
- Removed underscored Foundation re-exports from the public module surface before the first public release.

### Security

- Documented that provider API keys should not be shipped directly in distributed client apps.
