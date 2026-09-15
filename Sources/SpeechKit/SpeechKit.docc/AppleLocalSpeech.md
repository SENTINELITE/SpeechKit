# Apple Local Speech

Use Apple's on-device Speech framework for realtime and file transcription on supported OS versions.

## Overview

SpeechKit exposes Apple local Speech as the `.apple` provider on iOS 26, macOS 26, and visionOS 26. The provider is unavailable on watchOS and is omitted from ``SpeechRealtimeProvider/allCases`` and ``SpeechFileTranscriptionProvider/allCases`` until the current OS can run Apple's `SpeechAnalyzer` and `SpeechTranscriber` APIs.

Apple local Speech does not use an API key. Configure ``AppleSpeechConfiguration`` with the preferred locale, optional contextual strings, asset behavior, and model retention policy.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let speech = SpeechService(
        apple: AppleSpeechConfiguration(
            locale: .current,
            preparesAssetsAutomatically: true,
            contextualStrings: ["SpeechKit"],
            modelRetention: .whileInUse
        )
    )
}
```

## Asset Preparation

Apple Speech may need local model assets for the selected locale. By default, SpeechKit asks Apple's `AssetInventory` to install missing assets before transcription. Set ``AppleSpeechConfiguration/preparesAssetsAutomatically`` to `false` when your app wants to fail fast and handle download timing itself.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    try await speech.prepareAppleSpeechAssets(locale: Locale(identifier: "en-US"))
}
```

When assets are missing and automatic preparation is disabled, SpeechKit throws ``SpeechError/appleSpeechAssetsUnavailable(localeIdentifier:)``. Unsupported locales throw ``SpeechError/appleSpeechUnsupportedLocale(localeIdentifier:)``.

## Realtime Transcription

Realtime Apple transcription uses the same observable ``SpeechService`` state as the network realtime providers. Volatile Apple results become ``SpeechService/partialTranscriptEntry``; final results are inserted into ``SpeechService/transcriptEntries``.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    await speech.startListening(provider: .apple)
}
```

Apple can revise a volatile segment before finalization. SpeechKit deduplicates by Apple's audio time range rather than by text, so a final result replaces its matching volatile result even when Apple adds punctuation or revises words.

## File Transcription

Use the provider-neutral API when your app only needs text:

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let text = try await speech.transcribeAudioFile(
        provider: .apple,
        file: audioFileURL
    )
}
```

Use ``SpeechService/transcribeAppleAudioFile(file:options:)`` when your app needs detailed normalized entries.

```swift
if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
    let response = try await speech.transcribeAppleAudioFile(
        file: audioFileURL,
        options: AppleSpeechFileTranscriptionOptions(
            locale: Locale(identifier: "en-US")
        )
    )

    print(response.text)
    print(response.entries)
}
```

## Topics

### Configuration

- ``AppleSpeechConfiguration``
- ``AppleSpeechModelRetention``
- ``AppleSpeechFileTranscriptionOptions``

### File Transcription

- ``AppleSpeechFileTranscriptionClient``
- ``AppleSpeechFileTranscriptionResponse``
- ``SpeechService/transcribeAppleAudioFile(file:options:)``
- ``SpeechService/transcribeAppleAudioFile(securityScopedURL:options:)``

### Asset Preparation

- ``SpeechService/prepareAppleSpeechAssets(locale:)``

### Errors

- ``SpeechError/appleSpeechUnavailable``
- ``SpeechError/appleSpeechNotSupportedOnWatch``
- ``SpeechError/appleSpeechUnsupportedLocale(localeIdentifier:)``
- ``SpeechError/appleSpeechAssetsUnavailable(localeIdentifier:)``
