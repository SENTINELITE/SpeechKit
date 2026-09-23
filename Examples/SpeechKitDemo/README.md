# SpeechKit Demo

SpeechKit Demo is a starter SwiftUI app for trying SpeechKit in a real app target.

Open `SpeechKitDemo.xcodeproj` in Xcode, choose the `SpeechKitDemo` scheme, and run it on an iOS simulator or device. The app references the local package at the repository root, so changes to `Sources/SpeechKit` are available to the demo while you develop.

This example project is intentionally separate from the root `Package.swift`. Demo-only app code and dependencies should stay here so consumers who add SpeechKit as a package dependency only receive the `SpeechKit` library product.

## Conversation mode

The toolbar Mode picker has three workflows: **Realtime** (streaming transcription), **Dictation** (record then upload), and **Conversation**.

Conversation opens a full-duplex speech-to-speech session with OpenAI GPT-Live (`gpt-live-1`). You talk, the model talks back, and both sides show up in one interleaved transcript: your rows are trailing-aligned and tinted, the assistant's are leading-aligned and secondary. Entries that can still receive fragments are dimmed and end in an ellipsis. The screen also shows the assistant's output level, a mute toggle, a Flush button that drops queued assistant audio for a barge-in, the session state, billed seconds, and the session expiry.

Settings has an **OpenAI GPT-Live** section for the voice (the known voices plus a free-text override), the session instructions, the delegation mode (None, Responses with a backend model, or Client), and an optional separate GPT-Live API key. Conversations reuse the OpenAI key unless that toggle is on, which is useful when you want conversation spend on its own OpenAI project key.

`gpt-live-1` bills per second of streamed audio, so the demo ends the session as soon as the conversation screen disappears, the app moves to the background, or you switch to another mode. Keep an eye on the billed-seconds readout while you experiment.
