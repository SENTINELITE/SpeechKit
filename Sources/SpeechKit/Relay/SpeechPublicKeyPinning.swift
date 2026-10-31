import Foundation
import CryptoKit
import Security

/// Extracts the exact DER SubjectPublicKeyInfo, including its algorithm identifier.
enum SpeechPublicKeyPinning {
    static func hash(certificateDER: Data) throws -> String {
        let bytes = Array(certificateDER)
        func element(_ offset: Int) throws -> (tag: UInt8, body: Range<Int>, full: Range<Int>) {
            guard offset >= 0, offset + 2 <= bytes.count else { throw SpeechFailure(.pinningFailed) }
            let lengthByte = Int(bytes[offset + 1])
            var cursor = offset + 2
            var length = lengthByte
            if lengthByte & 0x80 != 0 {
                let count = lengthByte & 0x7f
                guard (1...4).contains(count), cursor + count <= bytes.count else { throw SpeechFailure(.pinningFailed) }
                length = 0
                for byte in bytes[cursor..<cursor + count] { length = (length << 8) | Int(byte) }
                cursor += count
            }
            guard length <= bytes.count - cursor else { throw SpeechFailure(.pinningFailed) }
            return (bytes[offset], cursor..<cursor + length, offset..<cursor + length)
        }
        let certificate = try element(0)
        guard certificate.tag == 0x30, certificate.full.upperBound == bytes.count else { throw SpeechFailure(.pinningFailed) }
        let tbs = try element(certificate.body.lowerBound)
        guard tbs.tag == 0x30, tbs.full.upperBound <= certificate.body.upperBound else { throw SpeechFailure(.pinningFailed) }
        var cursor = tbs.body.lowerBound
        if try element(cursor).tag == 0xa0 { cursor = try element(cursor).full.upperBound }
        // serialNumber, signature, issuer, validity, subject
        for _ in 0..<5 { cursor = try element(cursor).full.upperBound }
        let spki = try element(cursor)
        guard spki.tag == 0x30, spki.full.upperBound <= tbs.body.upperBound else { throw SpeechFailure(.pinningFailed) }
        return Data(SHA256.hash(data: Data(bytes[spki.full]))).base64EncodedString()
    }

    static func matches(certificateDER: Data, pins: Set<String>) -> Bool {
        guard let hash = try? hash(certificateDER: certificateDER) else { return false }
        return pins.contains(hash) || pins.contains("sha256/" + hash)
    }
}
