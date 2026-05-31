# SpeechKit Demo

SpeechKit Demo is a starter SwiftUI app for trying SpeechKit in a real app target.

Open `SpeechKitDemo.xcodeproj` in Xcode, choose the `SpeechKitDemo` scheme, and run it on an iOS simulator or device. The app references the local package at the repository root, so changes to `Sources/SpeechKit` are available to the demo while you develop.

This example project is intentionally separate from the root `Package.swift`. Demo-only app code and dependencies should stay here so consumers who add SpeechKit as a package dependency only receive the `SpeechKit` library product.
