import Foundation

protocol SpeechAppAttesting: Sendable {
    func sessionBody(relay: SpeechRelay, session: URLSession) async throws -> Data
    func operationHeaders(request: URLRequest, ticket: String, relay: SpeechRelay, session: URLSession) async throws -> [String: String]
    func acquireAssertion() async throws
    func releaseAssertion() async
    func invalidateKey(relay: SpeechRelay) async throws
    func identityVersion(relay: SpeechRelay) async -> UInt64
}

extension SpeechAppAttesting {
    func acquireAssertion() async throws {}
    func releaseAssertion() async {}
    func invalidateKey(relay: SpeechRelay) async throws { throw SpeechFailure(.attestationFailed) }
    func identityVersion(relay: SpeechRelay) async -> UInt64 { 0 }
    func operationHeaders(request: URLRequest, ticket: String, relay: SpeechRelay, session: URLSession) async throws -> [String: String] {
        throw SpeechFailure(.attestationUnsupported)
    }
}

actor SpeechRelaySession: SpeechRedactedDiagnostics {
    struct Ticket: Decodable, Sendable, SpeechRedactedDiagnostics {
        let ticket: String
        let expiresAt: Double
    }
    struct VendorToken: Decodable, Sendable, SpeechRedactedDiagnostics {
        let token: String
        let expiresAt: Double
        let singleUse: Bool
    }
    struct Route: Sendable {
        let credential: SpeechCredential
        let endpoint: URL
        let filesEndpoint: URL?
    }
    private struct IssuedTicket: Sendable {
        let value: Ticket
        let identityVersion: UInt64
    }

    private let relay: SpeechRelay
    private let session: URLSession
    private let attester: any SpeechAppAttesting
    private var cached: IssuedTicket?
    private var pending: Task<IssuedTicket, Error>?
    private var pendingID: UUID?
    private var generation = UUID()

    init(relay: SpeechRelay, session: URLSession? = nil, attester: any SpeechAppAttesting = SpeechAppAttest.shared) {
        self.relay = relay
        self.session = SpeechTransport.session(copying: session, pinnedPublicKeyHashes: relay.pinnedPublicKeyHashes)
        self.attester = attester
    }

    func reset() {
        generation = UUID()
        pending?.cancel()
        pending = nil
        pendingID = nil
        cached = nil
    }

    /// Refresh before an unstarted operation; active audio is never replayed.
    func ticket(context: SpeechTokenContext, forceRenewal: Bool = false,
                recovery: SpeechAttestationRecovery = SpeechAttestationRecovery()) async throws -> String {
        try relay.validate()
        try Task.checkCancellation()
        let version = await attester.identityVersion(relay: relay)
        try Task.checkCancellation()
        if !forceRenewal, let cached, cached.identityVersion == version,
           cached.value.expiresAt > Date().timeIntervalSince1970 + 30 { return cached.value.ticket }
        let task: Task<IssuedTicket, Error>
        let taskID: UUID
        if let pending, let pendingID { task = pending; taskID = pendingID }
        else {
            taskID = UUID()
            task = Task { [relay, session, attester] in
                var request = URLRequest(url: try relay.endpoint("/session"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                switch relay.authentication {
                case .bearer(let resolver), .appAttestAndBearer(let resolver):
                    let credential = SpeechCredential.bearer(resolver)
                    let login = try await credential.resolved(for: context.provider, capability: .fileTranscription,
                        model: context.model, endpoint: request.url, operationID: context.operationID, attempt: context.attempt)
                    request.setValue("Bearer \(login.secret)", forHTTPHeaderField: "Authorization")
                case .appAttest, .none: break
                }
                let needsProof = relay.requiresProof
                if needsProof { try await attester.acquireAssertion() }
                do {
                    for attempt in 0...1 {
                        do {
                            try Task.checkCancellation()
                            switch relay.authentication {
                            case .appAttest, .appAttestAndBearer:
                                request.httpBody = try await attester.sessionBody(relay: relay, session: session)
                            case .bearer, .none: request.httpBody = Data("{}".utf8)
                            }
                            request = try SpeechRelayProof.finalRequest(request)
                            let (data, response) = try await SpeechTransport.data(for: request, session: session)
                            if needsProof, Self.rejectsAttestation(data: data, response: response) {
                                throw SpeechAppAttestError.invalidKey
                            }
                            try Self.requireSuccess(response)
                            guard let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
                                  ticket.expiresAt > Date().timeIntervalSince1970,
                                  ticket.expiresAt <= Date().timeIntervalSince1970 + 301 else { throw SpeechFailure(.invalidResponse) }
                            try SpeechResolvedCredential.validateSecret(ticket.ticket)
                            let version = await attester.identityVersion(relay: relay)
                            if needsProof { await attester.releaseAssertion() }
                            return IssuedTicket(value: ticket, identityVersion: version)
                        } catch is SpeechAppAttestError {
                            guard needsProof, attempt == 0, await recovery.consume() else {
                                throw SpeechFailure(.attestationFailed)
                            }
                            try Task.checkCancellation()
                            try await attester.invalidateKey(relay: relay)
                        }
                    }
                    throw SpeechFailure(.attestationFailed)
                } catch {
                    if needsProof { await attester.releaseAssertion() }
                    throw error
                }
            }
            pending = task
            pendingID = taskID
        }
        let current = generation
        do {
            let result = try await task.value
            try Task.checkCancellation()
            let version = await attester.identityVersion(relay: relay)
            guard current == generation, version == result.identityVersion else { throw CancellationError() }
            if pendingID == taskID {
                cached = result
                pending = nil
                pendingID = nil
            }
            return result.value.ticket
        } catch {
            if current == generation, pendingID == taskID { pending = nil; pendingID = nil }
            if error is CancellationError { throw CancellationError() }
            throw SpeechErrorBoundary.safe(error)
        }
    }

    private static func rejectsAttestation(data: Data, response: URLResponse) -> Bool {
        struct Rejection: Decodable {
            struct Detail: Decodable { let code: String }
            let error: Detail
        }
        guard (response as? HTTPURLResponse)?.statusCode == 403,
              let rejection = try? JSONDecoder().decode(Rejection.self, from: data) else { return false }
        return ["attestation_failed", "unknown_key"].contains(rejection.error.code)
    }

    func route(provider: SpeechFileTranscriptionProvider, capability: SpeechCapability, model: String, allowVendorTokens: Bool = true) async throws -> Route {
        let current = generation
        try Task.checkCancellation()
        let endpoint = try relay.route(provider: provider, capability: capability)
        let context = SpeechTokenContext(provider: provider, capability: capability, model: model,
                                          authMode: .relay, approvedDestinations: [endpoint])
        let recovery = SpeechAttestationRecovery()
        if allowVendorTokens, relay.tokenStrategy == .vendorTokensWhenAvailable, Self.supportsVendorToken(provider, capability, model: model) {
            var request = URLRequest(url: try relay.endpoint("/tokens/\(provider.rawValue.lowercased())/\(capability.rawValue)"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
            request.setValue("Bearer \(try await ticket(context: context, recovery: recovery))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await SpeechTransport.data(for: request, session: session, prepare: { [self] in try await prepare($0, context: context, recovery: recovery) })
            try Task.checkCancellation()
            guard current == generation else { throw CancellationError() }
            if (response as? HTTPURLResponse)?.statusCode != 404 {
                try Self.requireSuccess(response)
                guard let token = try? JSONDecoder().decode(VendorToken.self, from: data),
                      token.expiresAt > Date().timeIntervalSince1970 + 5 else { throw SpeechFailure(.invalidCredential) }
                try SpeechResolvedCredential.validateSecret(token.token)
                // One allocation belongs to this operation. It is never put in a shared pool.
                let reservation = SpeechVendorTokenReservation(token: token)
                let credential = SpeechCredential.vendorToken(SpeechTokenResolver { _ in try await reservation.consume() })
                return Route(credential: credential, endpoint: try Self.vendorEndpoint(provider, capability), filesEndpoint: nil)
            }
        }
        let credential = SpeechCredential.relay(SpeechTokenResolver { [self] context in
            SpeechAccessToken(value: try await ticket(context: context, forceRenewal: context.attempt > 0, recovery: recovery), isReusable: true)
        }).withRelayTransport(origin: relay.url, pinnedPublicKeyHashes: relay.pinnedPublicKeyHashes,
                             optimizeUploads: relay.optimizedUploads == .on,
                             prepare: { [self] in try await prepare($0, context: context, recovery: recovery) })
        return Route(credential: credential, endpoint: endpoint,
                     filesEndpoint: provider == .gemini ? try relay.endpoint("/gemini/upload/v1beta/files") : nil)
    }

    private func prepare(_ request: URLRequest, context: SpeechTokenContext,
                         recovery: SpeechAttestationRecovery) async throws -> SpeechPreparedRequest {
        let current = generation
        guard let url = request.url, url.host?.lowercased() == relay.url.host?.lowercased(),
              (url.port ?? (["https", "wss"].contains(url.scheme?.lowercased() ?? "") ? 443 : 80)) ==
                (relay.url.port ?? (relay.url.scheme?.lowercased() == "https" ? 443 : 80)),
              url.path.hasPrefix("/speechkit/v1/"),
              request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true else {
            throw SpeechFailure(.invalidEndpoint)
        }
        var request = try SpeechRelayProof.finalRequest(request)
        // Gemini can poll for longer than a ticket lives. Renew before each
        // unstarted request, while keeping the operation's account and route.
        var ticket = try await ticket(context: context, recovery: recovery)
        try Task.checkCancellation()
        guard current == generation else { throw CancellationError() }
        request.setValue("Bearer \(ticket)", forHTTPHeaderField: "Authorization")
        let renew: (@Sendable () async throws -> Void)?
        if SpeechRelayRetry.permitsHTTPRenewal(request) {
            renew = { [self] in try await renewRejectedTicket(context: context, generation: current, recovery: recovery) }
        } else { renew = nil }
        guard relay.requiresProof else { return SpeechPreparedRequest(request: request, renewRejectedTicket: renew) }
        for attempt in 0...1 {
            try await attester.acquireAssertion()
            do {
                try Task.checkCancellation()
                guard current == generation else { throw CancellationError() }
                let version = await attester.identityVersion(relay: relay)
                if version != cached?.identityVersion || ticket != cached?.value.ticket {
                    throw SpeechAppAttestError.identityChanged
                }
                let headers = try await attester.operationHeaders(request: request, ticket: ticket, relay: relay, session: session)
                try Task.checkCancellation()
                guard current == generation else { throw CancellationError() }
                for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
                return SpeechPreparedRequest(request: request, finish: { [attester] in await attester.releaseAssertion() }, renewRejectedTicket: renew)
            } catch let failure as SpeechAppAttestError {
                do {
                    guard attempt == 0 else { throw SpeechFailure(.attestationFailed) }
                    try Task.checkCancellation()
                    if failure == .invalidKey {
                        guard await recovery.consume() else { throw SpeechFailure(.attestationFailed) }
                        try await attester.invalidateKey(relay: relay)
                    }
                } catch {
                    await attester.releaseAssertion()
                    throw error
                }
                await attester.releaseAssertion()
                ticket = try await self.ticket(context: context, forceRenewal: true, recovery: recovery)
                request.setValue("Bearer \(ticket)", forHTTPHeaderField: "Authorization")
            } catch {
                await attester.releaseAssertion()
                throw error
            }
        }
        throw SpeechFailure(.attestationFailed)
    }

    private func renewRejectedTicket(context: SpeechTokenContext, generation expected: UUID,
                                     recovery: SpeechAttestationRecovery) async throws {
        try Task.checkCancellation()
        guard expected == generation else { throw CancellationError() }
        let retryContext = SpeechTokenContext(provider: context.provider, capability: context.capability,
            model: context.model, operationID: context.operationID, attempt: 1,
            authMode: .relay, approvedDestinations: context.approvedDestinations)
        _ = try await ticket(context: retryContext, forceRenewal: true, recovery: recovery)
    }

    static func supportsVendorToken(_ provider: SpeechFileTranscriptionProvider, _ capability: SpeechCapability, model: String) -> Bool {
        provider == .elevenLabs || (capability == .realtime && [.openAI, .gemini].contains(provider)) ||
            (provider == .mistral && capability == .realtime && model == "voxtral-mini-transcribe-realtime-2602")
    }

    static func vendorEndpoint(_ provider: SpeechFileTranscriptionProvider, _ capability: SpeechCapability) throws -> URL {
        let endpoint: URL?
        switch (provider, capability) {
        case (.elevenLabs, .fileTranscription): endpoint = ElevenLabsFileTranscriptionClient.defaultUploadURL
        case (.elevenLabs, .realtime): endpoint = ElevenLabsWebSocket.defaultURL
        case (.openAI, .realtime): endpoint = OpenAIRealtimeWebSocket.defaultURL
        case (.gemini, .realtime): endpoint = GeminiLiveWebSocket.defaultURL
        case (.mistral, .realtime): endpoint = MistralRealtimeWebSocket.defaultURL
        default: throw SpeechFailure(.unsupportedAuthentication)
        }
        guard let endpoint else { throw SpeechFailure(.invalidEndpoint) }
        return endpoint
    }

    static func requireSuccess(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw SpeechFailure(.invalidResponse) }
        guard (200...299).contains(response.statusCode) else { throw SpeechFailure(.server, statusCode: response.statusCode) }
    }
}

actor SpeechAttestationRecovery {
    private var available = true
    func consume() -> Bool {
        guard available else { return false }
        available = false
        return true
    }
}

private actor SpeechVendorTokenReservation {
    private var token: SpeechRelaySession.VendorToken?
    init(token: SpeechRelaySession.VendorToken) { self.token = token }
    func consume() throws -> SpeechAccessToken {
        guard let token else { throw SpeechFailure(.invalidCredential) }
        self.token = nil
        return SpeechAccessToken(value: token.token, expiresAt: Date(timeIntervalSince1970: token.expiresAt), isReusable: !token.singleUse)
    }
}
