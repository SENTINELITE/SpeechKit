import Foundation
import CryptoKit

typealias SpeechRelayRequestPreparation = @Sendable (URLRequest) async throws -> SpeechPreparedRequest

struct SpeechPreparedRequest: Sendable {
    let request: URLRequest
    var finish: @Sendable () async -> Void = {}
    var renewRejectedTicket: (@Sendable () async throws -> Void)? = nil
}

/// Canonical bytes are shared by HTTP, upload finalization and WebSocket upgrades.
enum SpeechRelayProof {
    static func canonical(request: URLRequest, ticket: String, challenge: String) throws -> Data {
        guard let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.fragment == nil else { throw SpeechFailure(.invalidEndpoint) }
        let ticketHash = Data(SHA256.hash(data: Data(ticket.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let path = parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?" + $0 } ?? "")
        let lines = ["speechkit-request:" + challenge, ticketHash, (request.httpMethod ?? "GET").uppercased(), path,
                     request.value(forHTTPHeaderField: "Content-Type") ?? "",
                     request.value(forHTTPHeaderField: "Content-Length") ?? "",
                     request.value(forHTTPHeaderField: "model") ?? "",
                     request.value(forHTTPHeaderField: "X-Goog-Upload-Header-Content-Length") ?? ""]
        guard lines.allSatisfy({ !$0.contains(where: { $0.isNewline }) }) else { throw SpeechFailure(.invalidResponse) }
        return Data(lines.joined(separator: "\n").utf8)
    }

    static func finalRequest(_ request: URLRequest) throws -> URLRequest {
        var request = request
        if let body = request.httpBody { request.setValue(String(body.count), forHTTPHeaderField: "Content-Length") }
        else if request.httpBodyStream == nil { request.setValue("0", forHTTPHeaderField: "Content-Length") }
        else if request.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init) == nil { throw SpeechFailure(.invalidResponse) }
        if request.httpBody?.isEmpty == false, request.value(forHTTPHeaderField: "Content-Type") == nil {
            throw SpeechFailure(.invalidResponse)
        }
        return request
    }
}

/// Holds a permit through submission, so App Attest counters reach the relay in order.
actor SpeechAssertionGate {
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async throws {
        if held { await withCheckedContinuation { waiters.append($0) } }
        else { held = true }
        if Task.isCancelled { release(); throw CancellationError() }
    }
    func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().resume() }
    }
}
