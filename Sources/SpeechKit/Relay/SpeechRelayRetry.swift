import Foundation

/// Renewal needs an explicit rejection before any audio or billable operation.
enum SpeechRelayRetry {
    static func permitsHTTPRenewal(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "POST", let path = request.url?.path else { return false }
        // These two relay routes authenticate before allocating a token or
        // upload capability. Uploaded audio and claimed sessions never retry.
        return path.hasPrefix("/speechkit/v1/tokens/") || path == "/speechkit/v1/gemini/upload/v1beta/files"
    }

    static func permitsRenewal(statusCode: Int?, audioSent: Bool, accepted: Bool, attempt: Int) -> Bool {
        statusCode == 401 && !audioSent && !accepted && attempt == 0
    }
}

struct SpeechSocketConnection: Sendable {
    let session: URLSession
    let task: URLSessionWebSocketTask
    let credential: SpeechResolvedCredential

    static func open(request: URLRequest, credential: SpeechResolvedCredential) async throws -> Self {
        var request = request
        var credential = credential
        for attempt in 0...1 {
            try Task.checkCancellation()
            let prepared = try await credential.relayRequestPreparation?(request) ?? SpeechPreparedRequest(request: request)
            if credential.kind == .relay,
               let authorization = prepared.request.value(forHTTPHeaderField: "Authorization"), authorization.hasPrefix("Bearer ") {
                do { credential = try credential.replacingRelayTicket(String(authorization.dropFirst(7))) }
                catch { await prepared.finish(); throw error }
            }
            let session = SpeechTransport.session(pinnedPublicKeyHashes: credential.pinnedPublicKeyHashes)
            let task = session.webSocketTask(with: prepared.request)
            task.resume()
            do {
                // Waiting for the upgrade prevents a rejected ticket from sending a config/auth frame.
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        task.sendPing { error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                    try Task.checkCancellation()
                } onCancel: {
                    task.cancel(with: .goingAway, reason: nil)
                    session.invalidateAndCancel()
                }
                await prepared.finish()
                return Self(session: session, task: task, credential: credential)
            } catch {
                await prepared.finish()
                let status = (task.response as? HTTPURLResponse)?.statusCode
                task.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
                guard credential.kind == .relay,
                      SpeechRelayRetry.permitsRenewal(statusCode: status, audioSent: false, accepted: status == 101, attempt: attempt),
                      let renew = credential.renewRelayTicket else {
                    if let status, status != 101 { throw SpeechFailure(.server, statusCode: status) }
                    if error is CancellationError { throw CancellationError() }
                    throw SpeechErrorBoundary.safe(error)
                }
                try Task.checkCancellation()
                credential = try await renew()
                request.setValue("Bearer \(credential.secret)", forHTTPHeaderField: "Authorization")
            }
        }
        throw SpeechFailure(.transport)
    }
}
