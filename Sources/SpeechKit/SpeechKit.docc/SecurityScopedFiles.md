# Security-Scoped Files

Use security-scoped overloads for files returned by document pickers.

## Overview

When a platform document picker returns a security-scoped URL, use the matching `securityScopedURL` overload. SpeechKit starts and stops access around the upload. This grants local file access, not consent to transmit the audio; choose credentials and server retention separately in <doc:ShippingInProduction>. Reset and recording discard never delete caller-owned files.

```swift
let text = try await speech.transcribeAudioFile(
    provider: .elevenLabs,
    securityScopedURL: pickedURL
)
```

Detailed provider helpers also include security-scoped overloads.

```swift
let response = try await speech.transcribeGrokAudioFile(
    securityScopedURL: pickedURL
)
```

If access cannot be started, SpeechKit throws ``SpeechError/providerFailure(provider:reason:)`` from provider-neutral APIs.

## Topics

### Provider-Neutral Access

- ``SpeechService/transcribeAudioFile(provider:securityScopedURL:options:)``

### Detailed Responses

- ``SpeechService/transcribeAquaAudioFile(securityScopedURL:options:)``
- ``SpeechService/transcribeGrokAudioFile(securityScopedURL:options:)``
- ``SpeechService/transcribeOpenAIAudioFile(securityScopedURL:options:)``
