import SwiftUI

extension View {
    /// Creates a relay-backed ``SpeechService`` once and places it in this view's environment.
    ///
    /// ```swift
    /// ContentView()
    ///     .speechKit(relay: SpeechRelay(url: relayURL))
    /// ```
    ///
    /// Views below read ``SwiftUI/EnvironmentValues/speechTranscriber`` for transcription, or
    /// ``SwiftUI/EnvironmentValues/speechService`` when they need configuration access.
    /// The service is created on first use and kept for the life of this view, like `@State`.
    /// Later changes to the arguments are ignored. To rebuild the service, for example after
    /// an account switch, give the view a new identity with `.id(_:)`.
    public func speechKit(
        relay: SpeechRelay,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) -> some View {
        modifier(SpeechKitModifier { SpeechService(relay: relay, credentialPolicy: credentialPolicy) })
    }

    /// Creates a ``SpeechService`` with direct provider configurations once and places it in
    /// this view's environment.
    ///
    /// ```swift
    /// ContentView()
    ///     .speechKit(openAI: OpenAIConfiguration(credential: .apiKey(savedKey)))
    /// ```
    ///
    /// The service is created on first use and kept for the life of this view, like `@State`.
    /// Later changes to the arguments are ignored. Change credentials through
    /// ``SwiftUI/EnvironmentValues/speechService`` instead.
    public func speechKit(
        elevenLabs: ElevenLabsConfiguration? = nil,
        cohere: CohereConfiguration? = nil,
        grok: GrokConfiguration? = nil,
        aqua: AquaConfiguration? = nil,
        openAI: OpenAIConfiguration? = nil,
        meta: MetaConfiguration? = nil,
        gemini: GeminiConfiguration? = nil,
        mistral: MistralConfiguration? = nil,
        fishAudio: FishAudioConfiguration? = nil,
        credentialPolicy: SpeechCredentialPolicy = .allowStaticKeys
    ) -> some View {
        modifier(SpeechKitModifier {
            SpeechService(
                elevenLabs: elevenLabs, cohere: cohere, grok: grok, aqua: aqua,
                openAI: openAI, meta: meta, gemini: gemini, mistral: mistral,
                fishAudio: fishAudio, credentialPolicy: credentialPolicy
            )
        })
    }

    /// Places an existing ``SpeechService`` in this view's environment.
    ///
    /// Use this when you create and own the service yourself, for example to configure
    /// Apple local Speech or to rebuild the service on account changes.
    public func speechKit(_ service: SpeechService) -> some View {
        environment(\.speechService, service)
    }
}

/// Holds the lazily created service so SwiftUI keeps one instance across view updates.
@MainActor
private final class SpeechServiceStorage {
    private var make: (@MainActor () -> SpeechService)?
    private var service: SpeechService?

    init(make: @escaping @MainActor () -> SpeechService) { self.make = make }

    var value: SpeechService {
        if let service { return service }
        let created = make!()
        service = created
        make = nil
        return created
    }
}

private struct SpeechKitModifier: ViewModifier {
    // `State` keeps the first storage; later inits only build a cheap, discarded holder.
    private let storage: State<SpeechServiceStorage>

    init(make: @escaping @MainActor () -> SpeechService) {
        storage = State(initialValue: SpeechServiceStorage(make: make))
    }

    func body(content: Content) -> some View {
        content.environment(\.speechService, storage.wrappedValue.value)
    }
}
