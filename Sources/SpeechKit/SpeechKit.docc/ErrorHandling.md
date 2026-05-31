# Error Handling

Handle provider setup, validation, upload, and decoding failures.

## Overview

Provider-neutral file transcription APIs throw ``SpeechError``. Realtime state exposes missing configuration and provider failures through ``SpeechService/lastError``.

```swift
do {
    let text = try await speech.transcribeAudioFile(
        provider: .grok,
        file: audioFileURL
    )
    print(text)
} catch let error as SpeechError {
    print(error.localizedDescription)
} catch {
    print(error.localizedDescription)
}
```

## Common Failures

- ``SpeechError/providerNotConfigured(_:)`` means the selected file transcription provider has no configuration on ``SpeechService``.
- ``SpeechError/realtimeProviderNotConfigured(_:)`` means the selected realtime provider has no configuration on ``SpeechService``.
- ``SpeechError/invalidOptionsForProvider(expected:received:)`` means the request used options for a different provider.
- ``SpeechError/uploadFailed(provider:reason:)`` means the upload was rejected or failed.
- ``SpeechError/decodingFailed(provider:reason:)`` means the provider response could not be decoded.
- ``SpeechError/providerFailure(provider:reason:)`` covers validation failures, timeouts, and provider-specific failures without a narrower case.

Realtime failures are observable through ``SpeechService/realtimeConnectionState`` and ``SpeechService/lastError``.

## Topics

### Provider-Neutral Errors

- ``SpeechError``

### ElevenLabs Realtime Errors

- ``ElevenLabsError``
- ``SpeechService/lastError``
- ``ElevenLabsService/lastError``
