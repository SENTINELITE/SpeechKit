import Foundation

/// Storage owned by the demo, separate from imported and exported user files.
enum DemoProtectedStorage {
    static func directory(named name: String) throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var directory = caches.appendingPathComponent("SpeechKitDemo", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: directoryAttributes)
        try FileManager.default.setAttributes(directoryAttributes, ofItemAtPath: directory.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        return directory
    }

    static func protectFile(at url: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
#if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
#endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// Only direct children of the dedicated directory are eligible for expiry.
    static func removeExpiredFiles(in directory: URL, olderThan age: TimeInterval, now: Date = Date()) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        for file in files {
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values.isRegularFile == true, let modified = values.contentModificationDate, now.timeIntervalSince(modified) >= age {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Earlier demo versions wrote these UUID-named WAVs directly into temporary storage.
    static func removeLegacyRecordings(in temporary: URL = FileManager.default.temporaryDirectory, now: Date = Date()) throws {
        let files = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: [.contentModificationDateKey])
        let prefix = "SpeechKitDemo-Dictation-"
        for file in files where file.pathExtension == "wav" {
            let name = file.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix), UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else { continue }
            let values = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modified = values.contentModificationDate, now.timeIntervalSince(modified) >= 24 * 60 * 60 {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    private static var directoryAttributes: [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
#if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
#endif
        return attributes
    }
}
