import Foundation

/// Strips credentials out of realtime connection errors before they reach observable state.
///
/// Some vendors require the API key in the WebSocket URL, and Foundation's
/// `URLError` carries the failing URL in `userInfo`. Publishing such an error
/// from `lastError` or interpolating it into a connection-state message would
/// leak the key into logs, crash reports, and error UI.
enum SpeechRealtimeErrorRedaction {
    /// `URLError` `userInfo` keys that can carry the failing request URL.
    static let urlBearingUserInfoKeys: Set<String> = [
        NSURLErrorFailingURLStringErrorKey,
        NSURLErrorFailingURLErrorKey,
        NSURLErrorFailingURLPeerTrustErrorKey
    ]

    /// Returns an error safe to publish, replacing `URLError` values that may embed a credential-bearing URL.
    ///
    /// The returned error keeps the original `URLError` domain, code, and
    /// localized description, but carries no `userInfo` beyond that
    /// description. Errors that are not `URLError` are returned unchanged.
    static func redacted(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }

        var description = urlError.localizedDescription
        for urlString in failingURLStrings(in: urlError) where !urlString.isEmpty {
            description = description.replacingOccurrences(of: urlString, with: "<redacted>")
        }
        if description.isEmpty {
            description = "URL error \(urlError.errorCode)"
        }

        return NSError(
            domain: URLError.errorDomain,
            code: urlError.errorCode,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    /// Returns a message safe to publish for a caught realtime error.
    static func redactedDescription(_ error: Error) -> String {
        redacted(error).localizedDescription
    }

    private static func failingURLStrings(in urlError: URLError) -> [String] {
        var strings: [String] = []
        if let failingURL = urlError.failingURL {
            strings.append(failingURL.absoluteString)
        }

        let userInfo = (urlError as NSError).userInfo
        for key in urlBearingUserInfoKeys {
            switch userInfo[key] {
            case let urlString as String:
                strings.append(urlString)
            case let url as URL:
                strings.append(url.absoluteString)
            default:
                break
            }
        }
        return strings
    }
}
