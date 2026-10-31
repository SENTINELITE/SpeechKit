# Error handling

Handle configuration, authorization, transport, and provider failures without recording sensitive content.

## Overview

Provider-neutral file APIs return ``SpeechError`` for provider-attributed failures and can also throw ``SpeechFailure`` for authorization/transport boundaries. Realtime failures are observable through ``SpeechService/lastError`` and ``SpeechService/realtimeConnectionState``. Do not assume every error is a `SpeechError` or parse localized strings.

```swift
do {
    let text = try await speech.transcribeAudioFile(provider: .grok, file: audioFileURL)
    _ = text.isEmpty
} catch is CancellationError {
    return
} catch let failure as SpeechFailure {
    switch failure.category {
    case .cancelled:
        return
    case .attestationUnsupported:
        break
    case .staticKeysDisallowed, .unsupportedAuthentication:
        break
    default:
        break
    }
} catch let error as SpeechError {
    if case .httpFailure(_, let statusCode) = error {
        _ = statusCode
    }
} catch {
    _ = "Transcription could not be completed."
}
```

Route those branches to your application's status UI. The example deliberately logs neither the transcript nor raw errors. Avoid transcript text, file paths, request URLs, bodies, credential values, and arbitrary errors in production telemetry. Even bounded metadata needs a retention/access policy. Caller-created errors and application logging remain your responsibility.

## Changed error payloads

``SpeechError/uploadFailed(provider:reason:)``, ``SpeechError/decodingFailed(provider:reason:)``, and ``SpeechError/providerFailure(provider:reason:)`` carry ``SpeechFailureReason`` instead of arbitrary strings. ``SpeechError/httpFailure(provider:statusCode:)`` exposes numeric status without a response body. ``SpeechFailure`` has a bounded `category`, optional `statusCode`, and fixed descriptions; resolver exceptions become `credentialResolution`, not their original callback text.

Provider-specific realtime errors also use bounded reasons. Fish Audio exposes only numeric codes in `serverError(code:)` and `sessionClosed(code:)`. See <doc:MigratingTo3> for all changed cases. A normal async file cancellation can throw `CancellationError`; safe observable boundaries can represent it as `SpeechFailure.Category.cancelled`. Treat both as cancellation, not a reason to retry audio.

Missing configurations, mismatched options, invalid responses, and Apple's availability/locale/assets cases remain explicit. Credential-free relay configurations do not need per-provider keys. HTTP 401 or a dropped socket is not permission to blindly resend uploaded or committed audio; unknown outcomes require reconciliation in your application.

## Topics

### Provider-neutral errors

- ``SpeechError``
- ``SpeechError/httpFailure(provider:statusCode:)``
- ``SpeechFailure``
- ``SpeechFailure/Category``
- ``SpeechFailureReason``
- ``SpeechError/providerNotConfigured(_:)``
- ``SpeechError/realtimeProviderNotConfigured(_:)``
- ``SpeechError/appleSpeechUnavailable``
- ``SpeechError/appleSpeechNotSupportedOnWatch``
- ``SpeechError/appleSpeechUnsupportedLocale(localeIdentifier:)``
- ``SpeechError/appleSpeechAssetsUnavailable(localeIdentifier:)``

### Realtime errors

- ``ElevenLabsError``
- ``SpeechAudioCaptureError``
- ``SpeechService/lastError``
- ``ElevenLabsService/lastError``
