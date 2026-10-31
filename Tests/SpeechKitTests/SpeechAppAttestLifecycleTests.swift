import CryptoKit
import DeviceCheck
import Foundation
import Synchronization
import Testing
@testable import SpeechKit

private final class AttestMemoryStore: SpeechAppAttestKeyStore, Sendable {
    private let keys = Mutex<[String: String]>([:])
    func loadKey(account: String) throws -> String? { keys.withLock { $0[account] } }
    func saveKey(_ key: String, account: String) throws { keys.withLock { $0[account] = key } }
    func removeKey(account: String) throws { keys.withLock { $0[account] = nil } }
}

private actor SyntheticAttestDevice: SpeechAppAttestDevice {
    private(set) var generated = 0
    private(set) var assertions = 0
    let invalidKeys: Set<String>
    let invalidAssertions: Set<Int>
    let invalidAttestationKeys: Set<String>
    let alwaysInvalid: Bool

    init(invalidKeys: Set<String> = [], invalidAssertions: Set<Int> = [],
         invalidAttestationKeys: Set<String> = [], alwaysInvalid: Bool = false) {
        self.invalidKeys = invalidKeys
        self.invalidAssertions = invalidAssertions
        self.invalidAttestationKeys = invalidAttestationKeys
        self.alwaysInvalid = alwaysInvalid
    }

    func generateKey() async throws -> String {
        generated += 1
        return "synthetic-key-\(generated)"
    }
    func attestKey(_ key: String, clientDataHash: Data) async throws -> Data {
        if invalidAttestationKeys.contains(key) { throw NSError(domain: DCErrorDomain, code: DCError.invalidKey.rawValue) }
        return Data("synthetic-attestation".utf8)
    }
    func generateAssertion(_ key: String, clientDataHash: Data) async throws -> Data {
        assertions += 1
        if invalidKeys.contains(key) || invalidAssertions.contains(assertions) || alwaysInvalid {
            throw NSError(domain: DCErrorDomain, code: DCError.invalidKey.rawValue)
        }
        return Data("synthetic-assertion".utf8)
    }
}

private func attestFixture(registrationStatus: Int = 204, rejectedSessions: Int = 0,
                           rejectionCode: String = "attestation_failed",
                           gate: SecurityGate? = nil) -> SecurityHTTPFixture {
    let remaining = Mutex(rejectedSessions)
    return SecurityHTTPFixture(beforeResponse: { request in
        if request.url?.path.hasSuffix("/attest/register") == true { await gate?.wait() }
    }) { request in
        switch request.url?.path {
        case "/speechkit/v1/attest/challenge":
            return .init(body: Data(#"{"challenge":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
        case "/speechkit/v1/attest/register":
            return .init(status: registrationStatus)
        case "/speechkit/v1/session":
            let reject = remaining.withLock { value in
                if value > 0 { value -= 1; return true }
                return false
            }
            if reject { return .init(status: 403, body: Data(#"{"error":{"code":"\#(rejectionCode)","message":"constant"}}"#.utf8)) }
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: String]
            return .init(body: Data(#"{"ticket":"ticket-\#(body["keyId"] ?? "missing")","expiresAt":\#(Date().timeIntervalSince1970 + 240)}"#.utf8))
        default: return .init(body: Data("synthetic-result".utf8))
        }
    }
}

private func attestContext() -> SpeechTokenContext {
    SpeechTokenContext(provider: .openAI, capability: .fileTranscription, model: "synthetic", authMode: .relay)
}

@Suite("App Attest account and key lifecycle")
struct SpeechAppAttestLifecycleTests {
    @Test func namespaceIncludesRelayAndAccountWithoutChangingLegacyLookup() {
        let url = URL(string: "https://relay.example")!
        let legacy = SpeechAppAttest.keyAccount(relay: SpeechRelay(url: url))
        #expect(legacy == SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined())
        let first = SpeechAppAttest.keyAccount(relay: SpeechRelay(url: url, appAttestAccountID: "account-a"))
        let second = SpeechAppAttest.keyAccount(relay: SpeechRelay(url: url, appAttestAccountID: "account-b"))
        let other = SpeechAppAttest.keyAccount(relay: SpeechRelay(url: URL(string: "https://other.example")!, appAttestAccountID: "account-a"))
        #expect(Set([legacy, first, second, other]).count == 4)
        #expect(first.count == 64 && !first.contains("account-a"))
    }

    @MainActor
    @Test func signOutAndAccountSwitchKeepDistinctPersistentIdentities() async throws {
        let fixture = attestFixture()
        let store = AttestMemoryStore()
        let device = SyntheticAttestDevice()
        let attester = SpeechAppAttest(device: device, store: store)
        let firstRelay = SpeechRelay(url: fixture.url, authentication: .appAttestAndBearer(SpeechTokenResolver { _ in "login-a" }), appAttestAccountID: "account-a")
        let first = SpeechService(relay: firstRelay)
        let firstSession = SpeechRelaySession(relay: firstRelay, session: fixture.session(), attester: attester)
        first.relaySession = firstSession
        #expect(try await firstSession.ticket(context: attestContext()) == "ticket-synthetic-key-1")
        await first.clearCredentials()
        #expect(first.relay == nil)
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: firstRelay)) == "synthetic-key-1")
        let secondRelay = SpeechRelay(url: fixture.url, authentication: .appAttestAndBearer(SpeechTokenResolver { _ in "login-b" }), appAttestAccountID: "account-b")
        let secondSession = SpeechRelaySession(relay: secondRelay, session: fixture.session(), attester: attester)
        #expect(try await secondSession.ticket(context: attestContext()) == "ticket-synthetic-key-2")
        let returning = SpeechRelaySession(relay: firstRelay, session: fixture.session(), attester: attester)
        #expect(try await returning.ticket(context: attestContext()) == "ticket-synthetic-key-1")
        #expect(await device.generated == 2)
        let logins = fixture.requests.filter { $0.url?.path.hasSuffix("/session") == true }.map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(logins == ["Bearer login-a", "Bearer login-b", "Bearer login-a"])
    }

    @Test func staleKeychainIDRegistersOneReplacement() async throws {
        let fixture = attestFixture()
        let relay = SpeechRelay(url: fixture.url)
        let store = AttestMemoryStore()
        try store.saveKey("stale", account: SpeechAppAttest.keyAccount(relay: relay))
        let device = SyntheticAttestDevice(invalidKeys: ["stale"])
        let attester = SpeechAppAttest(device: device, store: store)
        let session = SpeechRelaySession(relay: relay, session: fixture.session(), attester: attester)
        #expect(try await session.ticket(context: attestContext()) == "ticket-synthetic-key-1")
        #expect(await device.generated == 1)
        #expect(await device.assertions == 2)
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: relay)) == "synthetic-key-1")
    }

    @Test(arguments: [403, 502])
    func registrationFailureIsNotPersistedOrRetried(status: Int) async throws {
        let fixture = attestFixture(registrationStatus: status)
        let relay = SpeechRelay(url: fixture.url)
        let store = AttestMemoryStore()
        let device = SyntheticAttestDevice()
        let attester = SpeechAppAttest(device: device, store: store)
        let session = SpeechRelaySession(relay: relay, session: fixture.session(), attester: attester)
        await #expect(throws: SpeechFailure(.server, statusCode: status)) { try await session.ticket(context: attestContext()) }
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: relay)) == nil)
        #expect(await device.generated == 1)
        #expect(await device.assertions == 0)
    }

    @Test(arguments: ["attestation_failed", "unknown_key"])
    func relayUnknownKeyRecoversOnce(code: String) async throws {
        let fixture = attestFixture(rejectedSessions: 1, rejectionCode: code)
        let relay = SpeechRelay(url: fixture.url)
        let device = SyntheticAttestDevice()
        let session = SpeechRelaySession(relay: relay, session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        #expect(try await session.ticket(context: attestContext()) == "ticket-synthetic-key-2")
        #expect(await device.generated == 2)
        #expect(fixture.requests.filter { $0.url?.path.hasSuffix("/session") == true }.count == 2)
    }

    @Test func repeatedRelayRejectionStopsAfterOneRecovery() async throws {
        let fixture = attestFixture(rejectedSessions: 20)
        let relay = SpeechRelay(url: fixture.url)
        let device = SyntheticAttestDevice()
        let session = SpeechRelaySession(relay: relay, session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        await #expect(throws: SpeechFailure(.attestationFailed)) { try await session.ticket(context: attestContext()) }
        #expect(await device.generated == 2)
        #expect(fixture.requests.filter { $0.url?.path.hasSuffix("/session") == true }.count == 2)
    }

    @Test func repeatedAppleInvalidKeyStopsAfterOneRecovery() async throws {
        let fixture = attestFixture()
        let device = SyntheticAttestDevice(alwaysInvalid: true)
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        await #expect(throws: SpeechFailure(.attestationFailed)) { try await session.ticket(context: attestContext()) }
        #expect(await device.generated == 2)
        #expect(await device.assertions == 2)
    }

    @Test func appleInvalidKeyDuringAttestationRecoversOnce() async throws {
        let fixture = attestFixture()
        let device = SyntheticAttestDevice(invalidAttestationKeys: ["synthetic-key-1"])
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        #expect(try await session.ticket(context: attestContext()) == "ticket-synthetic-key-2")
        #expect(await device.generated == 2)
        #expect(fixture.requests.filter { $0.url?.path.hasSuffix("/attest/register") == true }.count == 1)
    }

    @Test func failedReplacementRegistrationLeavesNoStaleKey() async throws {
        let fixture = attestFixture(registrationStatus: 502)
        let relay = SpeechRelay(url: fixture.url)
        let store = AttestMemoryStore()
        try store.saveKey("stale", account: SpeechAppAttest.keyAccount(relay: relay))
        let device = SyntheticAttestDevice(invalidKeys: ["stale"])
        let session = SpeechRelaySession(relay: relay, session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: store))
        await #expect(throws: SpeechFailure(.server, statusCode: 502)) { try await session.ticket(context: attestContext()) }
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: relay)) == nil)
        #expect(await device.generated == 1)
        #expect(fixture.requests.filter { $0.url?.path.hasSuffix("/attest/register") == true }.count == 1)
    }

    @Test func resetDoesNotRemoveOtherAccountKeys() async throws {
        let fixture = attestFixture()
        let first = SpeechRelay(url: fixture.url, appAttestAccountID: "account-a")
        let second = SpeechRelay(url: fixture.url, appAttestAccountID: "account-b")
        let store = AttestMemoryStore()
        try store.saveKey("synthetic-a", account: SpeechAppAttest.keyAccount(relay: first))
        try store.saveKey("synthetic-b", account: SpeechAppAttest.keyAccount(relay: second))
        let attester = SpeechAppAttest(device: SyntheticAttestDevice(), store: store)
        try await attester.resetKey(relay: first)
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: first)) == nil)
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: second)) == "synthetic-b")
        #expect(fixture.requests.isEmpty)
    }

    @Test func unrelatedSessionFailureDoesNotRotateKey() async throws {
        let fixture = attestFixture(rejectedSessions: 1, rejectionCode: "forbidden")
        let device = SyntheticAttestDevice()
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        await #expect(throws: SpeechFailure(.server, statusCode: 403)) { try await session.ticket(context: attestContext()) }
        #expect(await device.generated == 1)
        #expect(fixture.requests.filter { $0.url?.path.hasSuffix("/session") == true }.count == 1)
    }

    @Test func concurrentRotationWaitsForRegistrationAndInvalidatesCachedTicket() async throws {
        let gate = SecurityGate()
        let fixture = attestFixture(gate: gate)
        let relay = SpeechRelay(url: fixture.url)
        let store = AttestMemoryStore()
        let device = SyntheticAttestDevice()
        let attester = SpeechAppAttest(device: device, store: store)
        let session = SpeechRelaySession(relay: relay, session: fixture.session(), attester: attester)
        let issuing = Task { try await session.ticket(context: attestContext()) }
        while !(await gate.entered) { await Task.yield() }
        let rotations = Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<8 { group.addTask { try await attester.resetKey(relay: relay) } }
                try await group.waitForAll()
            }
        }
        await gate.open()
        _ = try? await issuing.value
        try await rotations.value
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: relay)) == nil)
        #expect(try await session.ticket(context: attestContext()) == "ticket-synthetic-key-2")
        #expect(await device.generated == 2)
        #expect(try store.loadKey(account: SpeechAppAttest.keyAccount(relay: relay)) == "synthetic-key-2")
    }

    @Test func invalidOperationKeyRefreshesTicketBeforeSendingOnce() async throws {
        let fixture = attestFixture()
        let device = SyntheticAttestDevice(invalidAssertions: [2])
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        let route = try await session.route(provider: .openAI, capability: .fileTranscription, model: "synthetic")
        let credential = try await route.credential.resolved(for: .openAI, capability: .fileTranscription, endpoint: route.endpoint)
        var request = URLRequest(url: route.endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        let prepare = try #require(credential.relayRequestPreparation)
        let prepared = try await prepare(request)
        #expect(prepared.request.value(forHTTPHeaderField: "Authorization") == "Bearer ticket-synthetic-key-2")
        await prepared.finish()
        #expect(await device.generated == 2)
        #expect(await device.assertions == 4)
        #expect(fixture.requests.allSatisfy { $0.url?.path != route.endpoint.path })
    }

    @Test func recoveryBudgetIsSharedBySessionAndOperationProof() async throws {
        let fixture = attestFixture(rejectedSessions: 1)
        let device = SyntheticAttestDevice(invalidAssertions: [3])
        let session = SpeechRelaySession(relay: SpeechRelay(url: fixture.url), session: fixture.session(),
                                         attester: SpeechAppAttest(device: device, store: AttestMemoryStore()))
        let route = try await session.route(provider: .openAI, capability: .fileTranscription, model: "synthetic")
        let credential = try await route.credential.resolved(for: .openAI, capability: .fileTranscription, endpoint: route.endpoint)
        var request = URLRequest(url: route.endpoint)
        request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
        let prepare = try #require(credential.relayRequestPreparation)
        await #expect(throws: SpeechFailure(.attestationFailed)) {
            try await prepare(request)
        }
        #expect(await device.generated == 2)
        #expect(await device.assertions == 3)
        #expect(fixture.requests.allSatisfy { $0.url?.path != route.endpoint.path })
    }
}
