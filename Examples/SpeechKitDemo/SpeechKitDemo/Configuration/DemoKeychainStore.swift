import Foundation
import Security

/// Storage can be replaced with an in-memory or failing store for demo verification.
protocol DemoCredentialStore {
    func contains(account: String) throws -> Bool
    func read(account: String) throws -> String?
    func save(_ value: String, account: String) throws
    func delete(account: String) throws
}

/// Injectable Security calls keep status handling testable without real credentials.
struct DemoKeychainOperations {
    var update: (CFDictionary, CFDictionary) -> OSStatus = { SecItemUpdate($0, $1) }
    var add: (CFDictionary) -> OSStatus = { SecItemAdd($0, nil) }
    var delete: (CFDictionary) -> OSStatus = { SecItemDelete($0) }
    var copy: (CFDictionary) -> (OSStatus, AnyObject?) = { query in
        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        return (status, result)
    }
}

/// Foreground-only, device-local storage for user-supplied vendor keys.
struct DemoKeychainStore: DemoCredentialStore {
    var service = "com.sentinelite.SpeechKitDemo.api-keys"
    var operations = DemoKeychainOperations()

    func save(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        var attributes = protectionAttributes
        attributes[kSecValueData as String] = Data(value.utf8)
        let status = operations.update(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrSynchronizable as String] = false
            let addStatus = operations.add(item as CFDictionary)
            // Another writer may have added the item after our update.
            if addStatus == errSecDuplicateItem {
                try check(operations.update(query as CFDictionary, attributes as CFDictionary))
            } else {
                try check(addStatus)
            }
        } else {
            try check(status)
        }
    }

    func contains(account: String) throws -> Bool {
        guard try migrate(account: account) else { return false }
        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, _) = operations.copy(query as CFDictionary)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    func read(account: String) throws -> String? {
        guard try migrate(account: account) else { return nil }
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = operations.copy(query as CFDictionary)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw DemoKeychainError.unhandledStatus(errSecDecode)
        }
        return value
    }

    func delete(account: String) throws {
        let status = operations.delete(baseQuery(account: account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    /// Updates legacy AfterFirstUnlock items without reading or replacing their value.
    private func migrate(account: String) throws -> Bool {
        let status = operations.update(baseQuery(account: account) as CFDictionary, protectionAttributes as CFDictionary)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    private var protectionAttributes: [String: Any] {
        [
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw DemoKeychainError.unhandledStatus(status) }
    }
}

enum DemoKeychainError: LocalizedError {
    case unhandledStatus(OSStatus)
    case missingKey

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status): "Keychain operation failed with status \(status)."
        case .missingKey: "Save an API key in Settings before starting transcription."
        }
    }
}
