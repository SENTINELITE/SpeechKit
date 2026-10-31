import Foundation
import CryptoKit
import Testing
@testable import SpeechKit

private struct FakeAppAttest: SpeechAppAttesting {
    func sessionBody(relay: SpeechRelay, session: URLSession) async throws -> Data {
        Data(#"{"keyId":"synthetic-key-id","assertion":"synthetic-assertion","challenge":"synthetic-challenge"}"#.utf8)
    }
}

@Suite("Speech relay v1")
struct SpeechRelayTests {
    @Test(arguments: SpeechFileTranscriptionProvider.allCases.filter { $0.rawValue != "apple" })
    func routes(provider: SpeechFileTranscriptionProvider) throws {
        let relay = SpeechRelay(url: URL(string: "https://relay.example.com:9443")!, authentication: .none)
        let expected: [SpeechFileTranscriptionProvider: String] = [.elevenLabs: "/v1/speech-to-text", .openAI: "/v1/audio/transcriptions", .grok: "/v1/stt", .meta: "/v1/asr/transcribe",
            .mistral: "/v1/audio/transcriptions", .fishAudio: "/v1/asr", .cohere: "/v2/audio/transcriptions", .aqua: "/v1/audio/transcriptions", .gemini: "/v1beta/interactions"]
        let file = try relay.route(provider: provider, capability: .fileTranscription)
        #expect(file.absoluteString == "https://relay.example.com:9443/speechkit/v1/" + provider.rawValue.lowercased() + expected[provider]!)
        if [.cohere, .aqua].contains(provider) {
            #expect(throws: SpeechFailure(.unsupportedAuthentication)) { try relay.route(provider: provider, capability: .realtime) }
        } else {
            let socket = try relay.route(provider: provider, capability: .realtime)
            #expect(socket.scheme == "wss")
            #expect(socket.host == file.host)
            #expect(socket.port == file.port)
            #expect(socket.path.hasPrefix("/speechkit/v1/" + provider.rawValue.lowercased() + "/"))
            if provider == .openAI { #expect(socket.query == "intent=transcription") }
            if provider == .gemini { #expect(socket.path.hasSuffix("/gemini/live")) }
        }
    }

    @Test func relayValidation() {
        for url in ["http://relay.example.com", "https://user:pass@relay.example.com", "https://relay.example.com/path", "https://relay.example.com?token=sentinel"] {
            #expect(throws: SpeechFailure(.invalidEndpoint)) { try SpeechRelay(url: URL(string: url)!).validate() }
        }
        #expect(throws: SpeechFailure(.pinningFailed)) { try SpeechRelay(url: URL(string: "https://relay.example.com")!, pinnedPublicKeyHashes: ["invalid"]).validate() }
        #expect(throws: SpeechFailure(.unsupportedAuthentication)) {
            try SpeechRelay(url: URL(string: "https://relay.example.com")!, providers: [.openAI]).route(provider: .gemini, capability: .fileTranscription)
        }
    }

    @Test func ticketsAreCoalescedAndRenewed() async throws {
        let fixture = SecurityHTTPFixture { request in
            #expect(request.url?.path == "/speechkit/v1/session")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-login")
            let body = #"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#
            return .init(body: Data(body.utf8))
        }
        let relay = SpeechRelay(url: fixture.url, authentication: .bearer(SpeechTokenResolver { _ in "synthetic-login" }))
        let session = SpeechRelaySession(relay: relay, session: fixture.session())
        let context = SpeechTokenContext(provider: .openAI, capability: .realtime, model: "synthetic")
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<12 { group.addTask { try await session.ticket(context: context) } }
            for try await value in group { #expect(value == "synthetic-ticket") }
        }
        #expect(fixture.requests.count == 1)
        _ = try await session.ticket(context: context, forceRenewal: true)
        #expect(fixture.requests.count == 2)
        await session.reset()
        _ = try await session.ticket(context: context)
        #expect(fixture.requests.count == 3)
    }

    @Test func shortTicketIsProactivelyRenewed() async throws {
        let fixture = SecurityHTTPFixture { _ in .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 10)}"#.utf8)) }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none), session: fixture.session())
        let context = SpeechTokenContext(provider: .fishAudio, capability: .realtime, model: "transcribe-stream-1")
        _ = try await session.ticket(context: context)
        _ = try await session.ticket(context: context)
        #expect(fixture.requests.count == 2)
    }

    @Test func appAttestBodyAndBearerAreSeparateFromProviderAuth() async throws {
        let fixture = SecurityHTTPFixture { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-login")
            let object = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
            #expect(object?["assertion"] == "synthetic-assertion")
            return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .appAttestAndBearer(SpeechTokenResolver { _ in "synthetic-login" })), session: fixture.session(), attester: FakeAppAttest())
        let route = try await session.route(provider: .meta, capability: .realtime, model: "synthetic")
        let credential = try await route.credential.resolved(for: .meta, capability: .realtime, endpoint: route.endpoint)
        let request = try MetaRealtimeWebSocket.makeConnectRequest(credential: credential, options: MetaRealtimeOptions(), endpoint: route.endpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-ticket")
        let message = MetaRealtimeOptions().handshakeMessage(secret: credential.secret)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as! [String: Any]
        #expect((body["authorization"] as? [String: String])?["accessToken"] == "Bearer synthetic-ticket")
    }

    @Test func vendorTokensFallBackOnlyOn404() async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            #expect(request.url?.path == "/speechkit/v1/tokens/elevenlabs/fileTranscription")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-ticket")
            return .init(status: 404)
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none, tokenStrategy: .vendorTokensWhenAvailable), session: fixture.session())
        let route = try await session.route(provider: .elevenLabs, capability: .fileTranscription, model: "scribe_v2")
        #expect(route.credential.kind == .relay)
        #expect(route.endpoint.host == fixture.host)
    }

    @Test func resetDiscardsInFlightVendorTokenAllocation() async throws {
        let gate = SecurityGate()
        let fixture = SecurityHTTPFixture(beforeResponse: { request in
            if request.url?.path.contains("/tokens/") == true { await gate.wait() }
        }) { request in
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            return .init(body: Data(#"{"token":"synthetic-vendor-token","expiresAt":\#(Date().timeIntervalSince1970 + 60),"singleUse":true}"#.utf8))
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none,
                                                           tokenStrategy: .vendorTokensWhenAvailable), session: fixture.session())
        let pending = Task { try await session.route(provider: .elevenLabs, capability: .realtime, model: "scribe_v2_realtime") }
        while !(await gate.entered) { await Task.yield() }
        await session.reset()
        await gate.open()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(fixture.requests.count == 2)
    }

    @Test func vendorTokenAllocationIsSingleUse() async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
            }
            return .init(body: Data(#"{"token":"synthetic-vendor-token","expiresAt":\#(Date().timeIntervalSince1970 + 60),"singleUse":true}"#.utf8))
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none, tokenStrategy: .vendorTokensWhenAvailable), session: fixture.session())
        let route = try await session.route(provider: .elevenLabs, capability: .realtime, model: "scribe_v2_realtime")
        #expect(route.credential.kind == .vendorToken)
        #expect(route.endpoint.host == "api.elevenlabs.io")
        async let first = try? route.credential.resolved(for: .elevenLabs, capability: .realtime, endpoint: route.endpoint)
        async let second = try? route.credential.resolved(for: .elevenLabs, capability: .realtime, endpoint: route.endpoint)
        let outcomes = await [first, second]
        #expect(outcomes.compactMap { $0 }.count == 1)
    }

    @Test(arguments: [401, 403, 429, 502])
    func tokenFailuresDoNotDowngrade(status: Int) async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" { return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8)) }
            return .init(status: status, body: Data("SECURITY_SENTINEL".utf8))
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none, tokenStrategy: .vendorTokensWhenAvailable), session: fixture.session())
        await #expect(throws: SpeechFailure(.server, statusCode: status)) {
            try await session.route(provider: .openAI, capability: .realtime, model: "synthetic")
        }
        #expect(fixture.requests.count == (status == 401 ? 4 : 2))
    }

    @Test func uncertainMintOutcomeIsNotRetriedOrDowngraded() async throws {
        let fixture = SecurityHTTPFixture { request in
            if request.url?.path == "/speechkit/v1/session" {
                return .init(body: Data(#"{"ticket":"synthetic-ticket","expiresAt":\#(Int(Date().timeIntervalSince1970) + 240)}"#.utf8))
            }
            throw URLError(.timedOut)
        }
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url, authentication: .none,
                                                           tokenStrategy: .vendorTokensWhenAvailable), session: fixture.session())
        await #expect(throws: SpeechFailure(.transport)) {
            try await session.route(provider: .elevenLabs, capability: .realtime, model: "scribe_v2_realtime")
        }
        #expect(fixture.requests.count == 2)
    }

    @Test func retryClassifier() {
        for path in ["/speechkit/v1/gemini/upload-sessions/synthetic", "/speechkit/v1/openai/v1/audio/transcriptions", "/speechkit/v1/gemini/v1beta/interactions"] {
            var request = URLRequest(url: URL(string: "https://relay.example" + path)!)
            request.httpMethod = "POST"
            #expect(!SpeechRelayRetry.permitsHTTPRenewal(request))
        }
        #expect(SpeechRelayRetry.permitsRenewal(statusCode: 401, audioSent: false, accepted: false, attempt: 0))
        for status in [403, 429, 500, 101] { #expect(!SpeechRelayRetry.permitsRenewal(statusCode: status, audioSent: false, accepted: false, attempt: 0)) }
        #expect(!SpeechRelayRetry.permitsRenewal(statusCode: 401, audioSent: true, accepted: false, attempt: 0))
        #expect(!SpeechRelayRetry.permitsRenewal(statusCode: 401, audioSent: false, accepted: true, attempt: 0))
        #expect(!SpeechRelayRetry.permitsRenewal(statusCode: 401, audioSent: false, accepted: false, attempt: 1))
        #expect(!SpeechRelayRetry.permitsRenewal(statusCode: nil, audioSent: false, accepted: false, attempt: 0))
    }

    @Test func publicKeyPinsHashSPKIRatherThanRawKey() throws {
        // Synthetic DER: certificate -> TBSCertificate -> five fields -> SPKI.
        let field: [UInt8] = [0x30, 0x00]
        let fields: [UInt8] = Array(repeating: field, count: 5).flatMap { $0 }
        let spki: [UInt8] = [0x30, 0x03, 0x03, 0x01, 0x01]
        var tbs: [UInt8] = [0x30, UInt8(fields.count + spki.count)]
        tbs.append(contentsOf: fields)
        tbs.append(contentsOf: spki)
        let header: [UInt8] = [0x30, UInt8(tbs.count)]
        let certificate = Data(header + tbs)
        let expected = Data(SHA256.hash(data: Data(spki))).base64EncodedString()
        #expect(try SpeechPublicKeyPinning.hash(certificateDER: certificate) == expected)
        #expect(SpeechPublicKeyPinning.matches(certificateDER: certificate, pins: ["sha256/" + expected]))
        #expect(!SpeechPublicKeyPinning.matches(certificateDER: certificate, pins: [Data(repeating: 0, count: 32).base64EncodedString()]))
        #expect(throws: SpeechFailure(.pinningFailed)) { try SpeechPublicKeyPinning.hash(certificateDER: Data([0x30, 0x80])) }
    }
}
