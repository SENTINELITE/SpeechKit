import Foundation
import CryptoKit
import Security
#if canImport(DeviceCheck)
import DeviceCheck
#endif

protocol SpeechAppAttestDevice: Sendable {
    func generateKey() async throws -> String
    func attestKey(_ key: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ key: String, clientDataHash: Data) async throws -> Data
}

protocol SpeechAppAttestKeyStore: Sendable {
    func loadKey(account: String) throws -> String?
    func saveKey(_ key: String, account: String) throws
    func removeKey(account: String) throws
}

enum SpeechAppAttestError: Error { case invalidKey, identityChanged }

/// Registration and session assertions share a device-only key per relay/account.
actor SpeechAppAttest: SpeechAppAttesting {
    static let shared = SpeechAppAttest()
    private let assertionGate = SpeechAssertionGate()
    private let keyGate = SpeechAssertionGate()
    private let device: any SpeechAppAttestDevice
    private let store: any SpeechAppAttestKeyStore
    private var versions: [String: UInt64] = [:]

    init(device: any SpeechAppAttestDevice = SpeechSystemAppAttestDevice(),
         store: any SpeechAppAttestKeyStore = SpeechAppAttestKeychain()) {
        self.device = device
        self.store = store
    }

    func acquireAssertion() async throws { try await assertionGate.acquire() }
    func releaseAssertion() async { await assertionGate.release() }
    private struct Challenge: Decodable { let challenge: String; let expiresAt: Double }

    nonisolated static func keyAccount(relay: SpeechRelay) -> String {
        let identity: Data
        if let account = relay.appAttestAccountID {
            identity = Data(("speechkit-account:\(relay.url.absoluteString.utf8.count):" + relay.url.absoluteString + account).utf8)
        } else {
            identity = Data(relay.url.absoluteString.utf8)
        }
        return SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
    }

    func identityVersion(relay: SpeechRelay) -> UInt64 {
        versions[Self.keyAccount(relay: relay), default: 0]
    }

    func resetKey(relay: SpeechRelay) async throws {
        try await acquireAssertion()
        do {
            try await invalidateKey(relay: relay)
            await releaseAssertion()
        } catch {
            await releaseAssertion()
            throw error
        }
    }

    func invalidateKey(relay: SpeechRelay) async throws {
        try await keyGate.acquire()
        do {
            let account = Self.keyAccount(relay: relay)
            try store.removeKey(account: account)
            versions[account, default: 0] += 1
            await keyGate.release()
        } catch {
            await keyGate.release()
            throw SpeechFailure(.attestationFailed)
        }
    }

    func sessionBody(relay: SpeechRelay, session: URLSession) async throws -> Data {
        try await keyGate.acquire()
        do {
            let account = Self.keyAccount(relay: relay)
            let key: String
            if let existing = try store.loadKey(account: account) { key = existing }
            else {
                let newKey = try await device.generateKey()
                let challenge = try await challenge(relay: relay, session: session)
                let hash = Self.registrationClientDataHash(challenge)
                let object = try await device.attestKey(newKey, clientDataHash: hash)
                var request = URLRequest(url: try relay.endpoint("/attest/register"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "keyId": newKey, "attestation": object.base64EncodedString(), "challenge": challenge
                ])
                let (_, response) = try await SpeechTransport.data(for: request, session: session)
                try SpeechRelaySession.requireSuccess(response)
                try Task.checkCancellation()
                try store.saveKey(newKey, account: account)
                key = newKey
            }
            let challenge = try await challenge(relay: relay, session: session)
            let assertion = try await device.generateAssertion(key, clientDataHash: Self.sessionClientDataHash(challenge))
            let body = try JSONSerialization.data(withJSONObject: [
                "keyId": key, "assertion": assertion.base64EncodedString(), "challenge": challenge
            ])
            await keyGate.release()
            return body
        } catch {
            await keyGate.release()
            if Self.isInvalidKey(error) { throw SpeechAppAttestError.invalidKey }
            if error is SpeechAppAttestError { throw error }
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? SpeechFailure { throw failure }
            throw SpeechFailure(.attestationFailed)
        }
    }

    func operationHeaders(request: URLRequest, ticket: String, relay: SpeechRelay, session: URLSession) async throws -> [String: String] {
        try await keyGate.acquire()
        do {
            let account = Self.keyAccount(relay: relay)
            guard let key = try store.loadKey(account: account) else { throw SpeechAppAttestError.invalidKey }
            let challenge = try await challenge(relay: relay, session: session)
            let canonical = try SpeechRelayProof.canonical(request: request, ticket: ticket, challenge: challenge)
            let assertion = try await device.generateAssertion(key, clientDataHash: Data(SHA256.hash(data: canonical)))
            await keyGate.release()
            return ["X-SpeechKit-Challenge": challenge, "X-SpeechKit-Assertion": assertion.base64EncodedString()]
        } catch {
            await keyGate.release()
            if Self.isInvalidKey(error) { throw SpeechAppAttestError.invalidKey }
            if error is SpeechAppAttestError { throw error }
            if error is CancellationError { throw CancellationError() }
            if let failure = error as? SpeechFailure { throw failure }
            throw SpeechFailure(.attestationFailed)
        }
    }

    private static func isInvalidKey(_ error: Error) -> Bool {
        #if canImport(DeviceCheck)
        if let failure = error as? DCError { return failure.code == .invalidKey }
        #endif
        return false
    }

    private func challenge(relay: SpeechRelay, session: URLSession) async throws -> String {
        var request = URLRequest(url: try relay.endpoint("/attest/challenge"))
        request.httpMethod = "POST"
        let (data, response) = try await SpeechTransport.data(for: request, session: session)
        try SpeechRelaySession.requireSuccess(response)
        return try Self.validatedChallenge(data)
    }

    nonisolated static func registrationClientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    nonisolated static func sessionClientDataHash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(("speechkit-session:" + challenge).utf8)))
    }

    nonisolated static func validatedChallenge(_ data: Data, now: Date = Date()) throws -> String {
        guard let body = try? JSONDecoder().decode(Challenge.self, from: data),
              body.expiresAt > now.timeIntervalSince1970,
              body.expiresAt <= now.timeIntervalSince1970 + 301,
              body.challenge.utf8.count == 43,
              body.challenge.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw SpeechFailure(.invalidResponse)
        }
        var base64 = body.challenge.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard Data(base64Encoded: base64)?.count == 32 else { throw SpeechFailure(.invalidResponse) }
        return body.challenge
    }

}

struct SpeechSystemAppAttestDevice: SpeechAppAttestDevice {
    func generateKey() async throws -> String {
        #if canImport(DeviceCheck) && !os(watchOS)
        guard DCAppAttestService.shared.isSupported else { throw SpeechFailure(.attestationUnsupported) }
        return try await DCAppAttestService.shared.generateKey()
        #else
        throw SpeechFailure(.attestationUnsupported)
        #endif
    }

    func attestKey(_ key: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck) && !os(watchOS)
        return try await DCAppAttestService.shared.attestKey(key, clientDataHash: clientDataHash)
        #else
        throw SpeechFailure(.attestationUnsupported)
        #endif
    }

    func generateAssertion(_ key: String, clientDataHash: Data) async throws -> Data {
        #if canImport(DeviceCheck) && !os(watchOS)
        guard DCAppAttestService.shared.isSupported else { throw SpeechFailure(.attestationUnsupported) }
        return try await DCAppAttestService.shared.generateAssertion(key, clientDataHash: clientDataHash)
        #else
        throw SpeechFailure(.attestationUnsupported)
        #endif
    }
}

struct SpeechAppAttestKeychain: SpeechAppAttestKeyStore {
    private func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "SpeechKit.Relay.AppAttest",
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func loadKey(account: String) throws -> String? {
        var query = query(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { throw SpeechFailure(.attestationFailed) }
        return value
    }

    func saveKey(_ key: String, account: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                       kSecAttrSynchronizable as String: false]
        let query = query(account: account)
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, value in value }) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SpeechFailure(.attestationFailed) }
    }

    func removeKey(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SpeechFailure(.attestationFailed) }
    }
}
