import Foundation
import Testing
@testable import SpeechKit

private struct OpenAILiveTestFailure: Error {
    let message: String
}

private func liveMessage(_ json: String) throws -> OpenAILiveMessage {
    try JSONDecoder().decode(OpenAILiveMessage.self, from: Data(json.utf8))
}

private func liveJSONObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw OpenAILiveTestFailure(message: "Encoded value is not a JSON object.")
    }
    return object
}

private func liveJSONString(_ value: some Encodable) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw OpenAILiveTestFailure(message: "Encoded value is not UTF-8.")
    }
    return string
}

private func liveNestedObject(_ object: [String: Any], _ keys: String...) throws -> [String: Any] {
    var current = object
    for key in keys {
        guard let next = current[key] as? [String: Any] else {
            throw OpenAILiveTestFailure(message: "Missing object at key \(key).")
        }
        current = next
    }
    return current
}

// MARK: - Captured fixtures (gpt-live-1, 2026-09-15)

private let sessionStartedFixture = """
{
  "event_id": "event_EOVuG8elMVCuqwlVfO5yp",
  "type": "session.started",
  "client_event_id": "evt_start",
  "session": {
    "id": "live_u7_EOVuEp3oN5PuPvPnmqL88ErPk8C0LQWo",
    "expires_at": 1789518426,
    "model": "gpt-live-1",
    "instructions": "You are a concise voice assistant. Answer in one short sentence. If asked the capital of France, say Paris.",
    "audio": {
      "output": {
        "voice": "marin"
      },
      "format": {
        "type": "audio/pcm",
        "rate": 24000
      }
    },
    "delegation": {
      "type": "client"
    },
    "status": "active",
    "input": []
  }
}
"""

private let inputTranscriptDeltaFixture = """
{
  "type": "session.input_transcript.delta",
  "start_ms": 600,
  "end_ms": 800,
  "delta": "Hello",
  "event_id": "event_EOVuHT1rSHrZdiQo3v4Ww"
}
"""

private let outputTranscriptDeltaFixture = """
{
  "type": "session.output_transcript.delta",
  "start_ms": 2600,
  "end_ms": 2800,
  "delta": "Paris.",
  "event_id": "event_EOVuJsz9HPLFa11JC4MbL"
}
"""

private let outputAudioDeltaFixture = """
{
  "type": "session.output_audio.delta",
  "delta": "7//w/+7/7f/w//D/7v/u/+//7//u//D/7//v//H/8P/x//D/8f/u//T/7//u//L/"
}
"""

private let usageUpdatedFixture = """
{
  "type": "session.usage.updated",
  "usage": {
    "seconds": 7
  },
  "context_window": {
    "usage_ratio": 0.007421875
  },
  "event_id": "event_EOVuU3V5SQ0VZ7IeuuD3R"
}
"""

private let sessionClosedFixture = """
{
  "event_id": "event_EOVuXy5WFuBauaXYlFabw",
  "type": "session.closed",
  "reason": "close_requested",
  "session": {
    "id": "live_u7_EOVuEp3oN5PuPvPnmqL88ErPk8C0LQWo",
    "expires_at": 1789518426,
    "model": "gpt-live-1",
    "instructions": "You are a concise voice assistant. Answer in one short sentence. If asked the capital of France, say Paris.",
    "audio": {
      "output": {
        "voice": "marin"
      },
      "format": {
        "type": "audio/pcm",
        "rate": 24000
      }
    },
    "delegation": {
      "type": "client"
    },
    "status": "active",
    "input": []
  },
  "usage": {
    "seconds": 7
  }
}
"""

private let errorFixture = """
{
  "type": "error",
  "event_id": "event_b1a9f0ac-9a8b-4235-8cfd-b85ce153e451",
  "error": {
    "type": "invalid_request_error",
    "code": "forbidden",
    "message": "Voice session access denied."
  }
}
"""

@Suite("OpenAI GPT-Live server events")
struct OpenAILiveServerEventTests {
    @Test("session.started decodes the resolved session")
    func sessionStartedDecodesResolvedSession() throws {
        guard case .sessionStarted(let info) = try liveMessage(sessionStartedFixture) else {
            throw OpenAILiveTestFailure(message: "Expected sessionStarted.")
        }

        #expect(info.id == "live_u7_EOVuEp3oN5PuPvPnmqL88ErPk8C0LQWo")
        #expect(info.expiresAt == Date(timeIntervalSince1970: 1789518426))
        #expect(info.model == "gpt-live-1")
        #expect(info.voice == .marin)
        #expect(info.status == "active")
    }

    @Test("session.input_transcript.delta decodes the fragment window")
    func inputTranscriptDeltaDecodesWindow() throws {
        guard case .inputTranscriptDelta(let delta) = try liveMessage(inputTranscriptDeltaFixture) else {
            throw OpenAILiveTestFailure(message: "Expected inputTranscriptDelta.")
        }

        #expect(delta.delta == "Hello")
        #expect(delta.startMilliseconds == 600)
        #expect(delta.endMilliseconds == 800)
        #expect(delta.eventID == "event_EOVuHT1rSHrZdiQo3v4Ww")
    }

    @Test("session.output_transcript.delta decodes the fragment window")
    func outputTranscriptDeltaDecodesWindow() throws {
        guard case .outputTranscriptDelta(let delta) = try liveMessage(outputTranscriptDeltaFixture) else {
            throw OpenAILiveTestFailure(message: "Expected outputTranscriptDelta.")
        }

        #expect(delta.delta == "Paris.")
        #expect(delta.startMilliseconds == 2600)
        #expect(delta.endMilliseconds == 2800)
    }

    @Test("session.output_audio.delta decodes base64 audio")
    func outputAudioDeltaDecodesBase64() throws {
        guard case .outputAudioDelta(let audio) = try liveMessage(outputAudioDeltaFixture) else {
            throw OpenAILiveTestFailure(message: "Expected outputAudioDelta.")
        }

        #expect(audio.count == 48)
        #expect(audio.count.isMultiple(of: 2))
        #expect(audio.first == 0xEF)
    }

    @Test("Malformed output audio falls back to unknown")
    func malformedOutputAudioFallsBackToUnknown() throws {
        let json = """
        {"type":"session.output_audio.delta","delta":"not base64!!"}
        """

        #expect(try liveMessage(json).isUnknown(of: "session.output_audio.delta"))
    }

    @Test("session.usage.updated decodes the cumulative snapshot")
    func usageUpdatedDecodesSnapshot() throws {
        guard case .usageUpdated(let usage) = try liveMessage(usageUpdatedFixture) else {
            throw OpenAILiveTestFailure(message: "Expected usageUpdated.")
        }

        #expect(usage.seconds == 7)
        #expect(usage.contextWindowUsageRatio == 0.007421875)
    }

    @Test("session.closed decodes the reason, usage, and session snapshot")
    func sessionClosedDecodesReasonAndUsage() throws {
        guard case .sessionClosed(let closed) = try liveMessage(sessionClosedFixture) else {
            throw OpenAILiveTestFailure(message: "Expected sessionClosed.")
        }

        #expect(closed.reason == .closeRequested)
        #expect(closed.seconds == 7)
        #expect(closed.session?.id == "live_u7_EOVuEp3oN5PuPvPnmqL88ErPk8C0LQWo")
        #expect(closed.session?.expiresAt == Date(timeIntervalSince1970: 1789518426))
    }

    @Test("An unrecognized close reason maps to unknown")
    func unrecognizedCloseReasonMapsToUnknown() throws {
        let json = """
        {"type":"session.closed","reason":"supernova","usage":{"seconds":3}}
        """

        guard case .sessionClosed(let closed) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected sessionClosed.")
        }

        #expect(closed.reason == .unknown)
        #expect(closed.seconds == 3)
        #expect(closed.session == nil)
    }

    @Test("error decodes the rejection payload")
    func errorDecodesRejectionPayload() throws {
        guard case .error(let payload) = try liveMessage(errorFixture) else {
            throw OpenAILiveTestFailure(message: "Expected error.")
        }

        #expect(payload.type == "invalid_request_error")
        #expect(payload.code == "forbidden")
        #expect(payload.message == "Voice session access denied.")
        #expect(payload.param == nil)
        #expect(payload.clientEventID == nil)
    }

    @Test("An error carrying a client event id keeps it for acknowledgement matching")
    func errorKeepsClientEventID() throws {
        let json = """
        {"type":"error","error":{"code":"invalid_value","message":"Too long.","client_event_id":"evt_7"}}
        """

        guard case .error(let payload) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected error.")
        }

        #expect(payload.clientEventID == "evt_7")
        #expect(payload.code == "invalid_value")
    }

    @Test("Mute and unmute acknowledgements decode")
    func muteAcknowledgementsDecode() throws {
        #expect(try liveMessage(#"{"type":"session.input_audio.muted"}"#).isInputAudioMuted)
        #expect(try liveMessage(#"{"type":"session.input_audio.unmuted"}"#).isInputAudioUnmuted)
    }

    @Test("Context acknowledgements decode their kind and window")
    func contextAcknowledgementsDecodeKind() throws {
        let json = """
        {"type":"session.thinking.appended","client_event_id":"evt_9","start_ms":4200,"end_ms":4200}
        """

        guard case .contextAppended(let appended) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected contextAppended.")
        }

        #expect(appended.kind == .thinking)
        #expect(appended.clientEventID == "evt_9")
        #expect(appended.startMilliseconds == 4200)
        #expect(appended.endMilliseconds == 4200)
    }

    @Test("session.delegation.created decodes the delegation request")
    func delegationCreatedDecodesRequest() throws {
        let json = """
        {"type":"session.delegation.created","delegation":{"id":"del_123","target":"client"}}
        """

        guard case .delegationCreated(let request) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected delegationCreated.")
        }

        #expect(request.id == "del_123")
        #expect(request.target == "client")
        #expect(request.responseID == nil)
        #expect(request.clientEventID == nil)
        #expect(request.offsetMilliseconds == nil)
    }

    /// Captured from gpt-live-1 with Responses delegation on 2026-09-15
    /// (`Scripts/live-fixtures/commands/session.delegation.created.json`).
    @Test("session.delegation.created lifts the timeline and client event id off the event")
    func delegationCreatedDecodesCapturedResponsesDelegation() throws {
        let json = """
        {
          "type": "session.delegation.created",
          "offset_ms": 0,
          "delegation": {
            "id": "item_EOWKLrONPHWv3aiMsCcNY",
            "type": "delegation",
            "response_id": "resp_0e14b6e2485f0509006aa9cc8d519087d09ddffdaea0a515c0",
            "target": "responses"
          },
          "client_event_id": "resp_1",
          "event_id": "event_EOWKLi9PoVEoU9JrDZ7wK"
        }
        """

        guard case .delegationCreated(let request) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected delegationCreated.")
        }

        #expect(request.id == "item_EOWKLrONPHWv3aiMsCcNY")
        #expect(request.target == "responses")
        #expect(request.responseID == "resp_0e14b6e2485f0509006aa9cc8d519087d09ddffdaea0a515c0")
        #expect(request.clientEventID == "resp_1")
        #expect(request.offsetMilliseconds == 0)
    }

    @Test("session.updated keeps the client event id that identifies the request")
    func sessionUpdatedKeepsClientEventID() throws {
        let json = """
        {"type":"session.updated","client_event_id":"update_1","session":{"id":"live_1","expires_at":1789520034}}
        """

        guard case .sessionUpdated(let info, let clientEventID) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected sessionUpdated.")
        }

        #expect(info.id == "live_1")
        #expect(clientEventID == "update_1")
    }

    @Test("An error decodes a null code")
    func errorDecodesNullCode() throws {
        let json = """
        {"type":"error","error":{"type":"invalid_request_error","code":null,"message":"Unknown client delegation.","param":"delegation_id","client_event_id":"ctx_bad_1"}}
        """

        guard case .error(let payload) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected error.")
        }

        #expect(payload.type == "invalid_request_error")
        #expect(payload.code == nil)
        #expect(payload.message == "Unknown client delegation.")
        #expect(payload.param == "delegation_id")
        #expect(payload.clientEventID == "ctx_bad_1")
    }

    @Test("response.event keeps the nested Responses payload untouched")
    func responseEventKeepsNestedPayload() throws {
        let json = """
        {"type":"response.event","delegation_id":"del_123","event":{"type":"response.output_text.delta","delta":"Par","index":2}}
        """

        guard case .responseEvent(let event) = try liveMessage(json) else {
            throw OpenAILiveTestFailure(message: "Expected responseEvent.")
        }

        #expect(event.delegationID == "del_123")
        #expect(event.eventType == "response.output_text.delta")
        #expect(event.raw.objectValue?["delta"] == .string("Par"))
        #expect(event.raw.objectValue?["index"] == .number(2))
    }

    @Test("An unmodeled event type falls back to unknown")
    func unmodeledEventFallsBackToUnknown() throws {
        #expect(try liveMessage(#"{"type":"session.rainbow"}"#).isUnknown(of: "session.rainbow"))
    }
}

@Suite("OpenAI GPT-Live client events")
struct OpenAILiveClientEventTests {
    @Test("session.start encodes the model, audio format, and voice")
    func sessionStartEncodesModelAudioAndVoice() throws {
        let options = OpenAILiveSessionOptions(
            instructions: "Be brief.",
            voice: .cedar,
            audioFormat: .pcm16k
        )

        let object = try liveJSONObject(OpenAILiveSessionStartMessage(options: options))
        #expect(object["type"] as? String == "session.start")
        #expect(object["event_id"] as? String == "evt_session_start")

        let session = try liveNestedObject(object, "session")
        #expect(session["model"] as? String == "gpt-live-1")
        #expect(session["instructions"] as? String == "Be brief.")
        #expect(session["delegation"] == nil)

        let format = try liveNestedObject(session, "audio", "format")
        #expect(format["type"] as? String == "audio/pcm")
        #expect(format["rate"] as? Int == 16000)

        let output = try liveNestedObject(session, "audio", "output")
        #expect(output["voice"] as? String == "cedar")
    }

    @Test("session.start omits delegation entirely for the none mode")
    func sessionStartOmitsDelegationForNone() throws {
        let object = try liveJSONObject(OpenAILiveSessionStartMessage(options: OpenAILiveSessionOptions()))
        let session = try liveNestedObject(object, "session")

        #expect(session["delegation"] == nil)
        #expect(session["instructions"] == nil)
        #expect(session.keys.contains("delegation") == false)
    }

    @Test("session.start encodes client delegation as a bare type")
    func sessionStartEncodesClientDelegation() throws {
        let options = OpenAILiveSessionOptions(delegation: .client)
        let object = try liveJSONObject(OpenAILiveSessionStartMessage(options: options))
        let delegation = try liveNestedObject(object, "session", "delegation")

        #expect(delegation["type"] as? String == "client")
        #expect(delegation["responses"] == nil)
    }

    @Test("session.start encodes Responses delegation with raw tool schemas")
    func sessionStartEncodesResponsesDelegation() throws {
        let options = OpenAILiveSessionOptions(
            delegation: .responses(
                OpenAILiveResponsesDelegation(
                    model: "gpt-5.6-luna",
                    instructions: "Use the tools.",
                    tools: [
                        [
                            "type": "function",
                            "name": "lookup_weather",
                            "parameters": ["type": "object", "required": ["city"]]
                        ]
                    ],
                    toolChoice: .function(name: "lookup_weather"),
                    parallelToolCalls: false,
                    maxOutputTokens: 256,
                    serviceTier: "auto"
                )
            )
        )

        let object = try liveJSONObject(OpenAILiveSessionStartMessage(options: options))
        let delegation = try liveNestedObject(object, "session", "delegation")
        #expect(delegation["type"] as? String == "responses")

        let responses = try liveNestedObject(delegation, "responses")
        #expect(responses["model"] as? String == "gpt-5.6-luna")
        #expect(responses["instructions"] as? String == "Use the tools.")
        #expect(responses["parallel_tool_calls"] as? Bool == false)
        #expect(responses["max_output_tokens"] as? Int == 256)
        #expect(responses["service_tier"] as? String == "auto")

        let toolChoice = try liveNestedObject(responses, "tool_choice")
        #expect(toolChoice["type"] as? String == "function")
        #expect(toolChoice["name"] as? String == "lookup_weather")

        let tools = try #require(responses["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools.first?["name"] as? String == "lookup_weather")
        let parameters = try #require(tools.first?["parameters"] as? [String: Any])
        #expect(parameters["required"] as? [String] == ["city"])
    }

    @Test("Named tool choices encode as bare strings")
    func namedToolChoicesEncodeAsStrings() throws {
        let options = OpenAILiveSessionOptions(
            delegation: .responses(OpenAILiveResponsesDelegation(toolChoice: .required))
        )
        let object = try liveJSONObject(OpenAILiveSessionStartMessage(options: options))
        let responses = try liveNestedObject(object, "session", "delegation", "responses")

        #expect(responses["tool_choice"] as? String == "required")
        #expect(responses["tools"] == nil)
    }

    @Test("Session-wide context appends send an explicit null delegation id")
    func contextAppendSendsExplicitNullDelegationID() throws {
        let message = OpenAILiveContextAppendMessage(
            kind: .instructions,
            content: "Speak slowly.",
            delegationID: nil,
            eventID: "evt_1"
        )

        let json = try liveJSONString(message)
        #expect(json.contains("\"delegation_id\":null"))

        let object = try liveJSONObject(message)
        #expect(object["type"] as? String == "session.instructions.append")
        #expect(object["event_id"] as? String == "evt_1")
        #expect(object["content"] as? String == "Speak slowly.")
    }

    @Test("Delegated context appends carry the delegation id")
    func contextAppendCarriesDelegationID() throws {
        let message = OpenAILiveContextAppendMessage(
            kind: .commentary,
            content: "The order shipped.",
            delegationID: "del_123",
            eventID: "evt_2"
        )

        let object = try liveJSONObject(message)
        #expect(object["type"] as? String == "session.commentary.append")
        #expect(object["delegation_id"] as? String == "del_123")
    }

    @Test("Audio, mute, update, and close events encode their types")
    func remainingClientEventsEncodeTheirTypes() throws {
        let append = OpenAILiveInputAudioAppendMessage(audioData: Data([0x01, 0x02]))
        let appendObject = try liveJSONObject(append)
        #expect(appendObject["type"] as? String == "session.input_audio.append")
        #expect(appendObject["audio"] as? String == Data([0x01, 0x02]).base64EncodedString())
        #expect(appendObject["byteCount"] == nil)
        #expect(append.byteCount == 2)

        #expect(try liveJSONObject(OpenAILiveInputAudioMuteMessage())["type"] as? String == "session.input_audio.mute")
        #expect(try liveJSONObject(OpenAILiveInputAudioUnmuteMessage())["type"] as? String == "session.input_audio.unmute")
        #expect(try liveJSONObject(OpenAILiveSessionCloseMessage())["type"] as? String == "session.close")

        let update = OpenAILiveSessionUpdateMessage(
            responses: OpenAILiveResponsesDelegation(model: "gpt-5.6-luna"),
            eventID: "evt_3"
        )
        let updateObject = try liveJSONObject(update)
        #expect(updateObject["type"] as? String == "session.update")
        #expect(updateObject["event_id"] as? String == "evt_3")
        let updateResponses = try liveNestedObject(updateObject, "session", "delegation", "responses")
        #expect(updateResponses["model"] as? String == "gpt-5.6-luna")
    }

    @Test("Responses passthrough events carry their payload under the right key")
    func responsePassthroughEventsCarryPayload() throws {
        let item = OpenAILiveResponseItemCreateMessage(
            item: ["type": "function_call_output", "output": "sunny"],
            delegationID: "del_123",
            eventID: "evt_4"
        )
        let itemObject = try liveJSONObject(item)
        #expect(itemObject["type"] as? String == "response.item.create")
        #expect(itemObject["delegation_id"] as? String == "del_123")
        #expect(try liveNestedObject(itemObject, "item")["output"] as? String == "sunny")

        let response = OpenAILiveResponseCreateMessage(delegationID: "del_123", eventID: "evt_5")
        let responseObject = try liveJSONObject(response)
        #expect(responseObject["type"] as? String == "response.create")
        #expect(responseObject["event_id"] as? String == "evt_5")
        #expect(responseObject["delegation_id"] as? String == "del_123")
        #expect(Set(responseObject.keys) == ["type", "event_id", "delegation_id"])

        let bareResponse = OpenAILiveResponseCreateMessage(eventID: "evt_6")
        #expect(Set(try liveJSONObject(bareResponse).keys) == ["type", "event_id"])
    }
}

@Suite("OpenAI GPT-Live connection")
struct OpenAILiveConnectionTests {
    @Test("The handshake request carries a bearer token and no query items")
    func handshakeRequestCarriesBearerAndNoQuery() throws {
        let request = try OpenAILiveWebSocket.makeConnectRequest(
            credential: .apiKey("sk-live"),
            options: OpenAILiveSessionOptions()
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-live")
        #expect(request.url?.absoluteString == "wss://api.openai.com/v1/live/sessions")
        #expect(request.url?.query == nil)
    }

    @Test("The handshake request honors an endpoint override")
    func handshakeRequestHonorsEndpointOverride() throws {
        let endpoint = try #require(URL(string: "wss://proxy.example.com/live"))
        let request = try OpenAILiveWebSocket.makeConnectRequest(
            credential: .token("proxy-token"),
            options: OpenAILiveSessionOptions(),
            endpoint: endpoint
        )

        #expect(request.url == endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer proxy-token")
    }

    @Test("The handshake request rejects invalid options")
    func handshakeRequestRejectsInvalidOptions() {
        #expect(throws: OpenAILiveError.invalidOptions("voice cannot be empty.")) {
            try OpenAILiveWebSocket.makeConnectRequest(
                credential: .apiKey("sk-live"),
                options: OpenAILiveSessionOptions(voice: OpenAILiveVoice(" "))
            )
        }
    }

    @Test("Options validation rejects unusable values")
    func optionsValidationRejectsUnusableValues() {
        #expect(throws: OpenAILiveError.invalidOptions("maxOutputTokens must be at least 16.")) {
            try OpenAILiveSessionOptions(
                delegation: .responses(OpenAILiveResponsesDelegation(maxOutputTokens: 8))
            ).validate()
        }
        #expect(throws: OpenAILiveError.invalidOptions("closeTimeout must be greater than zero.")) {
            try OpenAILiveSessionOptions(closeTimeout: 0).validate()
        }
        #expect(throws: OpenAILiveError.invalidOptions("turnGapMilliseconds cannot be negative.")) {
            try OpenAILiveSessionOptions(turnGapMilliseconds: -1).validate()
        }
    }

    @Test("Default options validate")
    func defaultOptionsValidate() throws {
        try OpenAILiveSessionOptions().validate()
        try OpenAILiveSessionOptions(
            delegation: .responses(OpenAILiveResponsesDelegation(maxOutputTokens: 16))
        ).validate()
    }

    @Test("The audio chunk aligner carries an odd trailing byte into the next chunk")
    func audioChunkAlignerCarriesOddTrailingByte() {
        var aligner = OpenAILiveAudioChunkAligner()

        let first = aligner.aligned(Data([0x01, 0x02, 0x03]))
        #expect(first == Data([0x01, 0x02]))
        #expect(aligner.carryOverByte == 0x03)

        let second = aligner.aligned(Data([0x04, 0x05, 0x06]))
        #expect(second == Data([0x03, 0x04, 0x05, 0x06]))
        #expect(aligner.carryOverByte == nil)

        let third = aligner.aligned(Data([0x07, 0x08]))
        #expect(third == Data([0x07, 0x08]))
        #expect(aligner.carryOverByte == nil)
    }

    @Test("The audio chunk aligner holds back a lone byte instead of sending it")
    func audioChunkAlignerHoldsBackLoneByte() {
        var aligner = OpenAILiveAudioChunkAligner()

        #expect(aligner.aligned(Data([0x10])).isEmpty)
        #expect(aligner.carryOverByte == 0x10)
        #expect(aligner.aligned(Data()).isEmpty)
        #expect(aligner.carryOverByte == 0x10)

        aligner.reset()
        #expect(aligner.carryOverByte == nil)
        #expect(aligner.aligned(Data()).isEmpty)
    }
}

private extension OpenAILiveMessage {
    func isUnknown(of type: String) -> Bool {
        if case .unknown(let value) = self { return value == type }
        return false
    }

    var isInputAudioMuted: Bool {
        if case .inputAudioMuted = self { return true }
        return false
    }

    var isInputAudioUnmuted: Bool {
        if case .inputAudioUnmuted = self { return true }
        return false
    }
}
