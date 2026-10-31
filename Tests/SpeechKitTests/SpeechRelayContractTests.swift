import Foundation
import Testing
@testable import SpeechKit

/// Synthetic assertions expose canonical bytes to the fixture, never call DeviceCheck.
actor ContractAppAttest: SpeechAppAttesting {
    let gate = SpeechAssertionGate()
    private(set) var count = 0
    func acquireAssertion() async throws { try await gate.acquire() }
    func releaseAssertion() async { await gate.release() }
    func sessionBody(relay: SpeechRelay, session: URLSession) async throws -> Data {
        Data(#"{"keyId":"c3ludGhldGljLWtleQ==","assertion":"c3ludGhldGlj","challenge":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}"#.utf8)
    }
    func operationHeaders(request: URLRequest, ticket: String, relay: SpeechRelay, session: URLSession) async throws -> [String: String] {
        count += 1
        let challenge = Data(repeating: UInt8(count % 255), count: 32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let canonical = try SpeechRelayProof.canonical(request: request, ticket: ticket, challenge: challenge)
        return ["X-SpeechKit-Challenge": challenge, "X-SpeechKit-Assertion": canonical.base64EncodedString()]
    }
}

func expectContractProof(_ request: URLRequest, ticket: String = "synthetic-ticket") throws {
    let challenge = try #require(request.value(forHTTPHeaderField: "X-SpeechKit-Challenge"))
    #expect(challenge.count == 43 && !challenge.contains("="))
    let assertion = try #require(request.value(forHTTPHeaderField: "X-SpeechKit-Assertion"))
    #expect(Data(base64Encoded: assertion) == (try SpeechRelayProof.canonical(request: request, ticket: ticket, challenge: challenge)))
    #expect(request.value(forHTTPHeaderField: "Content-Length") == String(request.httpBody?.count ?? 0))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer " + ticket)
}

@Suite("Relay CONTRACT.md encoding and proof")
struct SpeechRelayContractTests {
    @Test func challengeTextAndSessionHashVectors() throws {
        let challenge = String(repeating: "A", count: 43)
        func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(SpeechAppAttest.registrationClientDataHash(challenge)) == "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a")
        #expect(hex(SpeechAppAttest.sessionClientDataHash(challenge)) == "e8ff9ddbe72e6fb1142e104bfe7abc30d707eb84826c17431d246f9d3f23f511")
        let now = Date(timeIntervalSince1970: 1000)
        let valid = Data(#"{"challenge":"\#(challenge)","expiresAt":1300}"#.utf8)
        #expect(try SpeechAppAttest.validatedChallenge(valid, now: now) == challenge)
        for value in [challenge + "=", String(repeating: "+", count: 43), "short"] {
            #expect(throws: SpeechFailure(.invalidResponse)) {
                try SpeechAppAttest.validatedChallenge(Data(#"{"challenge":"\#(value)","expiresAt":1300}"#.utf8), now: now)
            }
        }
        #expect(throws: SpeechFailure(.invalidResponse)) {
            try SpeechAppAttest.validatedChallenge(Data(#"{"challenge":"\#(challenge)","expiresAt":999}"#.utf8), now: now)
        }
    }

    @Test func eightLineCanonicalBytesPreserveLiteralQueryAndEmptyLastLine() throws {
        var request = URLRequest(url: URL(string: "wss://relay.example/speechkit/v1/grok/v1/stt?keyterm=AC%2F42&keyterm=a%20b")!)
        request.httpMethod = "get"
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        let bytes = try SpeechRelayProof.canonical(request: request, ticket: "synthetic-ticket", challenge: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        let expected = "speechkit-request:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\nWaCrM87fi-eZHjgYhlVR7uLAarxUhXahM9utcCcP69U\nGET\n/speechkit/v1/grok/v1/stt?keyterm=AC%2F42&keyterm=a%20b\n\n0\n\n"
        #expect(bytes == Data(expected.utf8))
        #expect(String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n").count == 8)
        request.httpMethod = "POST"
        request.httpBody = Data([1, 2, 3])
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("transcribe-stream-1", forHTTPHeaderField: "model")
        request.setValue("3200", forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length")
        let final = try SpeechRelayProof.finalRequest(request)
        let lines = String(decoding: try SpeechRelayProof.canonical(request: final, ticket: "synthetic-ticket", challenge: "challenge"), as: UTF8.self).components(separatedBy: "\n")
        #expect(Array(lines.suffix(4)) == ["application/octet-stream", "3", "transcribe-stream-1", "3200"])
    }

    @Test func mintUsesTicketProofAndModelWithoutLoginJWT() async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-user-jwt")
                #expect(request.value(forHTTPHeaderField: "X-SpeechKit-Assertion") == nil)
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Int(Date().timeIntervalSince1970) + 240)}"#.utf8))
            }
            #expect(request.url?.path == "/speechkit/v1/tokens/openai/realtime")
            try expectContractProof(request)
            #expect(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: String] == ["model": "gpt-live-transcribe"])
            return .init(body: Data(#"{"token":"synthetic-native-token","expiresAt":\#(Int(Date().timeIntervalSince1970) + 60),"singleUse":false}"#.utf8))
        }
        let attester = ContractAppAttest()
        let relay = SpeechRelay(url: fixture.url, authentication: .appAttestAndBearer(SpeechTokenResolver { _ in "synthetic-user-jwt" }), tokenStrategy: .vendorTokensWhenAvailable)
        let session = SpeechRelaySession(relay: relay, session: fixture.session(), attester: attester)
        let route = try await session.route(provider: .openAI, capability: .realtime, model: "gpt-live-transcribe")
        #expect(route.credential.kind == .vendorToken)
        #expect(await attester.count == 1)
        #expect(fixture.requests.count == 2)
    }

    @Test func upgradeProofAndAssertionSubmissionAreSerialized() async throws {
        let fixture = SecurityHTTPFixture { _ in .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Int(Date().timeIntervalSince1970) + 240)}"#.utf8)) }
        let attester = ContractAppAttest()
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(), attester: attester)
        let route = try await session.route(provider: .meta, capability: .realtime, model: "synthetic")
        let credential = try await route.credential.resolved(for: .meta, capability: .realtime, endpoint: route.endpoint)
        let request = try MetaRealtimeWebSocket.makeConnectRequest(credential: credential, options: MetaRealtimeOptions(), endpoint: route.endpoint)
        let prepare = try #require(credential.relayRequestPreparation)
        let first = try await prepare(request)
        try expectContractProof(first.request)
        let pending = Task { try await prepare(request) }
        for _ in 0..<20 { await Task.yield() }
        #expect(await attester.count == 1)
        await first.finish()
        let second = try await pending.value
        try expectContractProof(second.request)
        #expect(first.request.value(forHTTPHeaderField: "X-SpeechKit-Challenge") != second.request.value(forHTTPHeaderField: "X-SpeechKit-Challenge"))
        await second.finish()
        #expect(await attester.count == 2)
    }

    @Test func preparedOperationRenewsBeforeSigningAndMetaUsesTheUpgradeTicket() async throws {
        let sequence = ContractTicketSequence()
        let fixture = SecurityHTTPFixture { _ in
            let number = sequence.next()
            let ttl = number == 1 ? 10 : 240
            return .init(body: Data(#"{"ticket":"synthetic-ticket-\#(number)","expiresAt":\#(Int(Date().timeIntervalSince1970) + ttl)}"#.utf8))
        }
        let attester = ContractAppAttest()
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(), attester: attester)
        let route = try await session.route(provider: .meta, capability: .realtime, model: "synthetic")
        let credential = try await route.credential.resolved(for: .meta, capability: .realtime, endpoint: route.endpoint)
        #expect(credential.secret == "synthetic-ticket-1")
        let request = try MetaRealtimeWebSocket.makeConnectRequest(credential: credential, options: MetaRealtimeOptions(), endpoint: route.endpoint)
        let prepare = try #require(credential.relayRequestPreparation)
        let prepared = try await prepare(request)
        try expectContractProof(prepared.request, ticket: "synthetic-ticket-2")
        let renewed = try credential.replacingRelayTicket("synthetic-ticket-2")
        let frame = MetaRealtimeOptions().handshakeMessage(secret: renewed.secret)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any]
        #expect((json?["authorization"] as? [String: String])?["accessToken"] == "Bearer synthetic-ticket-2")
        await prepared.finish()
        #expect(fixture.requests.count == 2)
    }

    @Test(arguments: [true, false])
    func explicitRejectionRenewsOnlyBeforeMintOrUploadAllocation(mint: Bool) async throws {
        let sessions = ContractTicketSequence()
        let operations = ContractTicketSequence()
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                let number = sessions.next()
                return .init(body: Data(#"{"ticket":"synthetic-ticket-\#(number)","expiresAt":\#(Int(Date().timeIntervalSince1970) + 240)}"#.utf8))
            }
            let number = operations.next()
            try expectContractProof(request, ticket: "synthetic-ticket-\(number)")
            if number == 1 { return .init(status: 401, body: Data(#"{"error":{"code":"ticket_expired","message":"Session expired."}}"#.utf8)) }
            return .init(body: Data(#"{"token":"synthetic-native-token","expiresAt":\#(Int(Date().timeIntervalSince1970) + 60),"singleUse":false}"#.utf8))
        }
        let attester = ContractAppAttest()
        let relay = SpeechRelay(url: fixture.url, tokenStrategy: mint ? .vendorTokensWhenAvailable : .proxyAll)
        let session = SpeechRelaySession(relay: relay, session: fixture.session(), attester: attester)
        if mint {
            let route = try await session.route(provider: .openAI, capability: .realtime, model: "gpt-live-transcribe")
            #expect(route.credential.kind == .vendorToken)
        } else {
            let route = try await session.route(provider: .gemini, capability: .fileTranscription, model: "gemini-3.5-transcribe")
            let resolved = try await route.credential.resolved(for: .gemini, endpoint: route.endpoint)
            var request = URLRequest(url: try #require(route.filesEndpoint))
            request.httpMethod = "POST"
            request.httpBody = Data(#"{"file":{"display_name":"synthetic"}}"#.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            try resolved.authorize(&request, provider: .gemini, capability: .fileTranscription)
            let (_, response) = try await SpeechTransport.data(for: request, session: SpeechTransport.session(copying: fixture.session()),
                                                             prepare: route.credential.relayRequestPreparation)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        }
        #expect(fixture.requests.count == 4)
        #expect(await attester.count == 2)
    }

    @Test func cancelledAssertionWaiterReleasesItsPermit() async throws {
        let gate = SpeechAssertionGate()
        try await gate.acquire()
        let pending = Task { try await gate.acquire() }
        pending.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await pending.value }
        try await gate.acquire()
        await gate.release()
    }

    @Test func geminiWholeFileFinalizeAndPollPreserveRelayResources() async throws {
        let id = String(repeating: "A", count: 43)
        let fixture = SecurityHTTPFixture { request in
            let origin = "https://" + request.url!.host!
            let root = origin + "/speechkit/v1/gemini"
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Int(Date().timeIntervalSince1970) + 240)}"#.utf8))
            }
            try expectContractProof(request)
            let path = request.url!.path
            if path.hasSuffix("/upload/v1beta/files") {
                #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length") == "3244")
                return .init(headers: ["X-Goog-Upload-URL": root + "/upload-sessions/" + id])
            }
            let file = #"{"name":"files/\#(id)","uri":"\#(root)/v1beta/files/\#(id)","mimeType":"audio/wav","state":"\#(path.contains("/upload-sessions/") ? "PROCESSING" : "ACTIVE")"}"#
            if path.contains("/upload-sessions/") {
                #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Offset") == "0")
                #expect(request.value(forHTTPHeaderField: "X-Goog-Upload-Command") == "upload, finalize")
                #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
                return .init(body: Data(("{\"file\":" + file + "}").utf8))
            }
            if path.contains("/v1beta/files/") { return .init(body: Data(file.utf8)) }
            if request.httpMethod == "GET" {
                return .init(body: Data(#"{"id":"\#(id)","status":"completed","steps":[{"content":[{"text":"contract transcript"}]}]}"#.utf8))
            }
            let object = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
            let inputs = object?["input"] as? [[String: Any]]
            #expect(inputs?.first?["uri"] as? String == root + "/v1beta/files/" + id)
            return .init(body: Data(#"{"id":"\#(id)","status":"in_progress"}"#.utf8))
        }
        let attester = ContractAppAttest()
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(), attester: attester)
        let route = try await session.route(provider: .gemini, capability: .fileTranscription, model: "gemini-3.5-transcribe")
        let client = GeminiFileTranscriptionClient(credential: route.credential, endpoint: route.endpoint, filesEndpoint: route.filesEndpoint, urlSession: fixture.session())
        let audio = try securityAudioFile()
        defer { try? FileManager.default.removeItem(at: audio) }
        let response = try await client.transcribeAudioFileDetailed(file: audio, options: GeminiFileTranscriptionOptions(uploadStrategy: .filesAPI, processingMode: .background(pollInterval: 0.001)))
        #expect(response.text == "contract transcript")
        #expect(await attester.count == 5)
        #expect(fixture.requests.count == 6)
    }
}

private final class ContractTicketSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}
