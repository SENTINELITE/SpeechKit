# Contributing to SpeechKit

Thanks for helping improve SpeechKit. This project is intended to stay small, readable, and useful as both a package and an example implementation.

## Development Setup

Requirements:

- Swift 6.2 toolchain family.
- Xcode 26.2 or newer compatible Xcode 26 toolchain.
- macOS runner capable of building iOS 18, macOS 15, watchOS 11, and visionOS 2 targets.

Clone the repository and run the package tests:

```sh
swift test
```

To work on the demo app, open `Examples/SpeechKitDemo/SpeechKitDemo.xcodeproj`, choose the `SpeechKitDemo` scheme, and run the app on an iOS simulator or device. The demo project depends on the local package and keeps demo-only dependencies separate from the root `Package.swift`.

## Pull Request Checklist

Before opening a pull request, please run the relevant checks:

```sh
swift build -Xswiftc -warnings-as-errors
swift test -Xswiftc -warnings-as-errors
xcodebuild build -scheme SpeechKit -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO OTHER_SWIFT_FLAGS="-warnings-as-errors"
mkdir -p /tmp/SpeechKitSymbolGraphs
swift build --target SpeechKit -Xswiftc -warnings-as-errors -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc /tmp/SpeechKitSymbolGraphs
xcrun docc convert Sources/SpeechKit/SpeechKit.docc --additional-symbol-graph-dir /tmp/SpeechKitSymbolGraphs --output-dir /tmp/SpeechKit.doccarchive --fallback-display-name SpeechKit --fallback-bundle-identifier com.sentinelite.SpeechKit --fallback-bundle-version 1.0.0 --warnings-as-errors
xcodebuild build -project Examples/SpeechKitDemo/SpeechKitDemo.xcodeproj -scheme SpeechKitDemo -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild docbuild -project Examples/SpeechKitDemo/SpeechKitDemo.xcodeproj -scheme SpeechKitDemo -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

If a change affects the demo, also verify that the realtime, recorded-upload, file-import, settings, transcript, and audio export entry points are still reachable.

## Code Style

- Keep the package API provider-neutral where possible, with provider-specific escape hatches only when they expose real provider capabilities.
- Prefer async/await and typed configuration values over stringly typed call sites.
- Keep provider request builders and response decoders covered by focused tests.
- Keep SwiftUI demo views small enough to study in isolation.
- Add DocC declaration comments for public package API and meaningful demo declarations.
- Do not add demo-only dependencies to the root `Package.swift`.

## Documentation

SpeechKit uses DocC for package documentation and in-source declaration comments for sample code. Prefer concise documentation that explains integration contracts, provider constraints, and credential safety.

Do not add real API keys, private transcripts, or captured audio to docs, tests, screenshots, or issues.

## Dependency Policy

The root package should remain dependency-light. Demo-only visual or tooling dependencies belong under `Examples/SpeechKitDemo` and must be pinned through the demo project's package resolution.

Before adding a dependency, confirm that its license is compatible with SpeechKit's Apache License 2.0 and that it does not expand the package surface for consumers.
