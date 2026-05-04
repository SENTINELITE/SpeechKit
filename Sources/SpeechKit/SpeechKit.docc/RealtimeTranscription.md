# Realtime Transcription

Stream microphone audio to ElevenLabs and observe partial and committed transcript text.

## Overview

Realtime transcription requires an ``ElevenLabsConfig``. Call ``SpeechService/startListening()`` and ``SpeechService/stopListening()`` from an asynchronous context.

```swift
struct TranscriptView: View {
    @Environment(\.speechService) private var speech

    var body: some View {
        VStack(alignment: .leading) {
            Text(speech.fullTranscript)

            if !speech.partialTranscript.isEmpty {
                Text(speech.partialTranscript)
                    .foregroundStyle(.secondary)
            }

            Button(speech.connectionState.isListening ? "Stop" : "Start") {
                Task {
                    if speech.connectionState.isActive {
                        await speech.stopListening()
                    } else {
                        await speech.startListening()
                    }
                }
            }
        }
    }
}
```

``SpeechService`` exposes committed entries through ``SpeechService/committedTranscripts`` and the joined text through ``SpeechService/fullTranscript``. Call ``SpeechService/clearTranscripts()`` when the user starts a new dictation session.

## Failure Handling

When ElevenLabs is not configured, ``SpeechService/startListening()`` sets ``SpeechService/connectionState`` to ``ElevenLabsService/ConnectionState/error(_:)`` and exposes ``SpeechError/providerNotConfigured(_:)`` through ``SpeechService/lastError``. ElevenLabs-specific failures surface as ``ElevenLabsError`` when using ``ElevenLabsService`` directly.

## Topics

### Realtime State

- ``SpeechService/connectionState``
- ``SpeechService/partialTranscript``
- ``SpeechService/committedTranscripts``
- ``SpeechService/fullTranscript``
- ``SpeechService/lastError``

### Realtime Operations

- ``SpeechService/startListening()``
- ``SpeechService/stopListening()``
- ``SpeechService/clearTranscripts()``

