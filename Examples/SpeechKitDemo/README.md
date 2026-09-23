# SpeechKit Demo

SpeechKit Demo is a starter SwiftUI app for trying SpeechKit in a real app target.

Open `SpeechKitDemo.xcodeproj` in Xcode, choose the `SpeechKitDemo` scheme, and run it on an iOS simulator or device. The app references the local package at the repository root through the `Packages/SpeechKit` symlink, so changes to `Sources/SpeechKit` are available to the demo while you develop.

The symlink gives the local package the identity `speechkit` no matter what the checkout folder is called (for example `SpeechKit-main` from a GitHub ZIP download). [SpeechKit-Voz](https://github.com/SENTINELITE/SpeechKit-Voz) depends on SpeechKit from GitHub, and Xcode only substitutes the local checkout for that dependency when the identities match.

## Try Apple on-device transcription

On iOS 26 and later, "Apple (On Device)" appears as a provider for Realtime, File Transcription, and Dictation. It uses Apple's Speech framework (`SpeechAnalyzer`), needs no API key, and keeps audio on the device.

1. Open Settings and choose Apple Speech under On-Device.
2. Pick the language you will speak. Apple Speech does not detect the language.
3. Optionally choose "Download Speech Assets" so the language's model is installed before your first recording.
4. Select "Apple (On Device)" as the Realtime or File & Dictation provider.

## Try VOZ local transcription

The demo pulls in [SpeechKit-Voz](https://github.com/SENTINELITE/SpeechKit-Voz) from GitHub, which adds VOZ on-device transcription through Desert Ant Labs' model. VOZ is available in the File Transcription and Dictation workflows. It transcribes selected files and recordings after recording stops. It does not appear in the Realtime workflow.

1. Run the app on iOS 18 or later. A physical device is recommended.
2. Open Settings and choose VOZ under On-Device.
3. Choose "Download and Load". The model is roughly 467 MB and needs a network connection only when it is not already cached. The page shows a percentage while downloading. Verifying cached files and loading the model report no progress, so the page shows elapsed time for those steps instead.
4. Select "VOZ (On Device)" in File Transcription or Dictation.
5. Select a file or record audio, then transcribe it. The demo shows the text, timing, speed, and word timestamps.

The model has to be loaded into memory on every launch. Once the files are cached, the demo starts loading it in the background at launch, so it is usually ready by the time you pick VOZ. The demo never starts the first download on its own. "Unload Model" drops the model from memory and keeps the cached files.

The demo does not upload selected or recorded VOZ audio to a transcription API. The underlying VOZ runtime may send the license's minimal device-counting telemetry, which excludes audio, transcripts, and user content.

## Run the opt-in device smoke test

The debug-only smoke hook runs only when you add `--voz-smoke-test` to the launch arguments. A normal demo launch does not start the smoke test.

1. Copy synthetic or otherwise nonprivate audio to the demo app container at `Documents/voz-smoke-input.aiff`.
2. Add `--voz-smoke-test` in the scheme's Run launch arguments and launch the Debug app on a physical device.
3. Inspect `Documents/voz-smoke-result.json` in the same container. It records success or failure, text, word timestamps, audio duration, processing time, and preparation time.

Use an optimized configuration for performance measurements. The hook is compiled only in Debug, so invoke `xcodebuild` with `SWIFT_OPTIMIZATION_LEVEL=-O` for a device measurement. Debug's default `-Onone` makes upstream pure-Swift SHA verification much slower.

The VOZ runtime and model use the [Desert Ant Labs Source-Available License 1.0](https://license.desertant.com/1.0). A distributed app must include a user-visible "Powered by Desert Ant Labs" credit, linked to [desertant.com](https://desertant.com) where links are supported. Read the [SpeechKit-Voz README](https://github.com/SENTINELITE/SpeechKit-Voz#readme) before distributing an app with VOZ.

This example project is intentionally separate from the root `Package.swift`. Demo-only app code and dependencies, including SpeechKit-Voz, stay here so consumers who add SpeechKit as a package dependency only receive the `SpeechKit` library product.
