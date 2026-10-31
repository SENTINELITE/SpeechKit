import Foundation
import Security

@main
struct HelperChecks {
    static func main() throws {
        try keychainChecks()
        try preferencesChecks()
        try storageChecks()
        print("Demo helper checks passed.")
    }

    private static func expectFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected storage failure")
        } catch {}
    }

    private static func keychainChecks() throws {
        var stored = "synthetic-old-value"
        var addCount = 0
        var readCount = 0
        var updateStatus = errSecAuthFailed
        var addStatus = errSecSuccess
        var deleteStatus = errSecAuthFailed
        var readStatus = errSecSuccess
        let operations = DemoKeychainOperations(
            update: { query, attributes in
                let query = query as! [String: Any]
                let attributes = attributes as! [String: Any]
                precondition(query[kSecAttrAccount as String] as? String == "selected")
                precondition(query[kSecAttrSynchronizable as String] as? Bool == false)
                precondition(attributes[kSecAttrSynchronizable as String] as? Bool == false)
                precondition(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
                if updateStatus == errSecSuccess, let data = attributes[kSecValueData as String] as? Data {
                    stored = String(decoding: data, as: UTF8.self)
                }
                return updateStatus
            },
            add: { _ in
                addCount += 1
                return addStatus
            },
            delete: { _ in deleteStatus },
            copy: { query in
                let query = query as! [String: Any]
                if query[kSecReturnData as String] as? Bool == true {
                    readCount += 1
                    return (readStatus, Data(stored.utf8) as NSData)
                }
                precondition(query[kSecReturnAttributes as String] as? Bool == true)
                return (readStatus, NSDictionary())
            }
        )
        let store = DemoKeychainStore(service: "synthetic-test", operations: operations)
        expectFailure { try store.save("synthetic-new-value", account: "selected") }
        precondition(stored == "synthetic-old-value" && addCount == 0)
        expectFailure { try store.delete(account: "selected") }
        precondition(stored == "synthetic-old-value")
        expectFailure { _ = try store.read(account: "selected") }
        precondition(readCount == 0)

        updateStatus = errSecItemNotFound
        addStatus = errSecAuthFailed
        expectFailure { try store.save("synthetic-new-value", account: "selected") }
        precondition(addCount == 1)
        addStatus = errSecSuccess
        try store.save("synthetic-new-value", account: "selected")
        precondition(addCount == 2)
        let missingValue = try store.read(account: "selected")
        precondition(missingValue == nil)
        precondition(readCount == 0)

        updateStatus = errSecSuccess
        let containsValue = try store.contains(account: "selected")
        precondition(containsValue)
        precondition(readCount == 0)
        readStatus = errSecAuthFailed
        expectFailure { _ = try store.read(account: "selected") }
        readStatus = errSecSuccess
        try store.save("synthetic-new-value", account: "selected")
        let value = try store.read(account: "selected")
        precondition(value == "synthetic-new-value")
        deleteStatus = errSecItemNotFound
        try store.delete(account: "selected")
        deleteStatus = errSecSuccess
        try store.delete(account: "selected")
    }

    private static func preferencesChecks() throws {
        let suite = "SpeechKitDemo-Verification-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in DemoPrivateTextPreferences.keys { defaults.set("synthetic-private-text", forKey: key) }
        defaults.set("openAI", forKey: "fileProvider")
        DemoPrivateTextPreferences.clearSavedValues(in: defaults)
        precondition(DemoPrivateTextPreferences.keys.allSatisfy { defaults.object(forKey: $0) == nil })
        precondition(defaults.string(forKey: "fileProvider") == "openAI")
    }

    private static func storageChecks() throws {
        let directory = try DemoProtectedStorage.directory(named: "Verification-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let imported = FileManager.default.temporaryDirectory.appendingPathComponent("SpeechKitDemo-import-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: imported) }
        try Data("synthetic imported audio".utf8).write(to: imported)
        let stale = directory.appendingPathComponent("stale.wav")
        let fresh = directory.appendingPathComponent("fresh.wav")
        try Data("synthetic audio".utf8).write(to: stale)
        try Data("synthetic audio".utf8).write(to: fresh)
        try DemoProtectedStorage.protectFile(at: fresh)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: stale.path)
        try DemoProtectedStorage.removeExpiredFiles(in: directory, olderThan: 60)
        let legacy = directory.appendingPathComponent("SpeechKitDemo-Dictation-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: legacy) }
        try Data("synthetic legacy audio".utf8).write(to: legacy)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)], ofItemAtPath: legacy.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)], ofItemAtPath: imported.path)
        try DemoProtectedStorage.removeLegacyRecordings(in: directory)
        precondition(!FileManager.default.fileExists(atPath: legacy.path))
        precondition(!FileManager.default.fileExists(atPath: stale.path))
        precondition(FileManager.default.fileExists(atPath: fresh.path))
        precondition(FileManager.default.fileExists(atPath: imported.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: fresh.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        precondition(values.isExcludedFromBackup == true)
    }
}
