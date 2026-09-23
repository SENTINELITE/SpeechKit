import Foundation
import Testing
@testable import SpeechKit

/// Exercises the GPT-Live socket against the real API.
///
/// These tests only run when `OPENAI_API_KEY` is present in the environment, so a
/// normal `swift test` skips them. Run them with `source .env; swift test --filter
/// OpenAILiveIntegrationTests`. They stream no audio, so a run costs nothing beyond the
/// session itself, which GPT-Live bills by seconds of audio.
private var liveIntegrationAPIKey: String? {
    ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
}

private var hasLiveIntegrationAPIKey: Bool {
    !(liveIntegrationAPIKey ?? "").isEmpty
}

@Suite("OpenAI Live integration", .enabled(if: hasLiveIntegrationAPIKey))
struct OpenAILiveIntegrationTests {
    static var apiKey: String? {
        liveIntegrationAPIKey
    }

    @Test("A silent session starts, acknowledges commands, and closes on request")
    func silentSessionLifecycle() async throws {
        let apiKey = try #require(Self.apiKey)
        let socket = OpenAILiveWebSocket()
        var options = OpenAILiveSessionOptions()
        options.instructions = "Answer in one short sentence."
        options.delegation = .responses(OpenAILiveResponsesDelegation())

        let stream = try await socket.connect(
            credential: .apiKey(apiKey),
            options: options,
            endpoint: nil
        )
        var iterator = stream.makeAsyncIterator()

        let started = try await Self.next(&iterator, matching: { message in
            if case .sessionStarted(let info) = message { return info }
            return nil
        })
        #expect(started.id.hasPrefix("live_"))
        #expect(started.model == "gpt-live-1")
        #expect(started.voice == .marin)
        let expiresAt = try #require(started.expiresAt)
        #expect(expiresAt.timeIntervalSinceNow > 60 * 60)

        try await socket.sendInputAudioMute()
        _ = try await Self.next(&iterator, matching: { message in
            if case .inputAudioMuted = message { return true }
            return nil
        })

        try await socket.sendInputAudioUnmute()
        _ = try await Self.next(&iterator, matching: { message in
            if case .inputAudioUnmuted = message { return true }
            return nil
        })

        var responses = OpenAILiveResponsesDelegation()
        responses.instructions = "Be terse."
        try await socket.send(OpenAILiveSessionUpdateMessage(responses: responses, eventID: "update_1"))
        let updated = try await Self.next(&iterator, matching: { message in
            if case .sessionUpdated(let info, _) = message { return info }
            return nil
        })
        #expect(updated.id == started.id)

        try await socket.send(
            OpenAILiveContextAppendMessage(kind: .thinking, content: "The user is testing.", eventID: "ctx_1")
        )

        try await socket.requestClose()
        let closed = try await Self.next(&iterator, matching: { message in
            if case .sessionClosed(let payload) = message { return payload }
            return nil
        })
        #expect(closed.reason == .closeRequested)
        #expect(closed.seconds == 0)
        #expect(await socket.didReceiveSessionClosed)

        await socket.disconnect()
    }

    @Test("Streaming a WAV through the socket yields a user transcript and assistant audio")
    func streamingAudioYieldsTranscriptAndAudio() async throws {
        let apiKey = try #require(Self.apiKey)
        let wavURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/live-input.wav")
        let wav = try Data(contentsOf: wavURL)
        let pcm = wav.dropFirst(44)

        let socket = OpenAILiveWebSocket()
        var options = OpenAILiveSessionOptions()
        options.instructions = "Answer in one short sentence. If asked the capital of France, say Paris."

        let stream = try await socket.connect(credential: .apiKey(apiKey), options: options, endpoint: nil)
        var iterator = stream.makeAsyncIterator()
        _ = try await Self.next(&iterator, matching: { message in
            if case .sessionStarted(let info) = message { return info }
            return nil
        })

        let chunkSize = 4800
        let sender = Task {
            var offset = pcm.startIndex
            while offset < pcm.endIndex {
                let end = min(offset + chunkSize, pcm.endIndex)
                try await socket.sendInputAudio(Data(pcm[offset..<end]))
                offset = end
                try await Task.sleep(for: .milliseconds(100))
            }
            for _ in 0..<15 {
                try await socket.sendInputAudio(Data(count: chunkSize))
                try await Task.sleep(for: .milliseconds(100))
            }
        }

        var userText = ""
        var assistantText = ""
        var audioBytes = 0
        var sawError: String?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, assistantText.isEmpty || audioBytes == 0 {
            guard let message = try await iterator.next() else { break }
            switch message {
            case .inputTranscriptDelta(let delta): userText += delta.delta
            case .outputTranscriptDelta(let delta): assistantText += delta.delta
            case .outputAudioDelta(let data): audioBytes += data.count
            case .error(let payload): sawError = payload.message
            default: break
            }
        }
        sender.cancel()
        try await socket.requestClose()
        await socket.disconnect()

        #expect(sawError == nil, "server error: \(sawError ?? "")")
        #expect(userText.lowercased().contains("france"), "user transcript was \(userText)")
        #expect(assistantText.lowercased().contains("paris"), "assistant transcript was \(assistantText)")
        #expect(audioBytes > 0)
    }

    @Test("An unknown voice is rejected before the session starts")
    func unknownVoiceIsRejected() async throws {
        let apiKey = try #require(Self.apiKey)
        let socket = OpenAILiveWebSocket()
        var options = OpenAILiveSessionOptions()
        options.voice = OpenAILiveVoice(rawValue: "not-a-real-voice")

        let stream = try await socket.connect(
            credential: .apiKey(apiKey),
            options: options,
            endpoint: nil
        )
        var iterator = stream.makeAsyncIterator()

        let error = try await Self.next(&iterator, matching: { message in
            if case .error(let payload) = message { return payload }
            return nil
        })
        #expect(error.code == "forbidden")
        #expect(error.message.contains("denied"))

        await socket.disconnect()
    }

    /// Reads messages until `matching` returns a value, failing after `timeout` seconds.
    ///
    /// Messages that do not match are skipped, so a test can wait for a specific
    /// acknowledgement while usage snapshots or other events flow past.
    private static func next<Value>(
        _ iterator: inout AsyncThrowingStream<OpenAILiveMessage, Error>.AsyncIterator,
        timeout: TimeInterval = 20,
        matching: (OpenAILiveMessage) -> Value?
    ) async throws -> Value {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let message = try await iterator.next() else {
                throw IntegrationFailure.streamEnded
            }
            if let value = matching(message) {
                return value
            }
        }
        throw IntegrationFailure.timedOut
    }

    private enum IntegrationFailure: Error {
        case streamEnded
        case timedOut
    }
}
