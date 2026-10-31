import SpeechKit
import SwiftUI

/// One cloud provider's API key, realtime-only options, and transcription options.
struct ProviderSettingsView: View {
    @Bindable var configuration: DemoConfiguration
    let provider: DemoAPIKeyProvider
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.speechService) private var speech
    @State private var keyDraft = ""
    @State private var persistenceError: String?
    @State private var persistenceMessage: String?

    var body: some View {
        Form {
            apiKeySection

            if let realtimeProvider = provider.realtimeProvider {
                Section("Realtime") {
                    RealtimeOnlyOptionsView(configuration: configuration, provider: realtimeProvider)
                }
            }

            if let fileProvider = provider.fileProvider {
                Section {
                    FileProviderOptionsView(configuration: configuration, provider: fileProvider)
                } header: {
                    Text("Transcription")
                } footer: {
                    if let sharedSettingsNote = provider.sharedSettingsNote {
                        Text(sharedSettingsNote)
                    }
                }
            }
        }
        .navigationTitle(provider.title)
        .onAppear { configuration.refreshKeyStatus() }
        .onDisappear { keyDraft = "" }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { keyDraft = "" }
        }
    }

    /// Edits the provider's keychain-backed API key.
    private var apiKeySection: some View {
        Section {
            if configuration.isRelayEnabled {
                Text("Relay handles this provider. Saved vendor keys are not loaded while Relay mode is enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SecureField(hasKey ? "Replacement API key" : "\(provider.title) API Key", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            HStack {
                Text(hasKey ? "Key stored" : "Not configured")
                    .font(.caption)
                    .foregroundStyle(hasKey ? .green : .secondary)

                Spacer()

                Button("Save") {
                    persistKey(keyDraft)
                }
                .buttonStyle(.bordered)
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || configuration.isResettingAuthorization)
            }

            if let message = persistenceError ?? configuration.keychainError {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if let persistenceMessage {
                Text(persistenceMessage).font(.caption).foregroundStyle(.green)
            }

            if hasKey {
                Button("Remove Key", role: .destructive) {
                    persistKey("")
                }
                .disabled(configuration.isResettingAuthorization)
            }
        } header: {
            Text("API Key")
        } footer: {
            Text("Stored only on this device and available while unlocked. Saved keys are never shown. Use your own vendor key; requests use its permissions and billing. Remove Key stops local use; revoke the key with the vendor to invalidate it elsewhere.")
        }
    }

    private func persistKey(_ value: String) {
        defer { keyDraft = "" }
        persistenceMessage = nil
        persistenceError = nil
        do {
            try configuration.setAPIKey(value, for: provider)
            persistenceMessage = value.isEmpty ? "Key removed." : "Key saved."
            Task { await configuration.clearAuthorization(in: speech) }
        } catch {
            persistenceError = "The key was not changed. \(DemoFailure.message(for: error))"
        }
    }

    private var hasKey: Bool {
        configuration.savedKeyProviders.contains(provider)
    }
}

extension DemoAPIKeyProvider {
    /// The realtime provider that uses this key, if the service offers realtime transcription.
    var realtimeProvider: DemoRealtimeProvider? {
        DemoRealtimeProvider.allCases.first { $0.apiKeyProvider == self }
    }

    /// The file provider that uses this key.
    var fileProvider: DemoFileProvider? {
        DemoFileProvider.allCases.first { $0.apiKeyProvider == self }
    }

    /// The workflows this key unlocks, shown under the provider name.
    var capabilities: String {
        [
            realtimeProvider == nil ? nil : "Realtime",
            fileProvider == nil ? nil : "File & Dictation",
        ]
        .compactMap(\.self)
        .joined(separator: " · ")
    }

    /// Explains which transcription settings also shape realtime sessions.
    var sharedSettingsNote: String? {
        switch self {
        case .grok: "Language and diarization also apply to realtime sessions."
        case .meta: "Model, mode, language bias, and keywords also apply to realtime sessions."
        case .gemini: "Mode, language codes, and custom vocabulary also apply to Gemini Live. Gemini Live does not support diarization or word timestamps."
        case .mistral: "Language, context bias, and diarization also apply to realtime sessions. Diarized realtime sessions skip turn detection and start a new entry when the speaker changes."
        case .fishAudio: "File settings do not apply to realtime sessions, which have their own turn detection, speaker label, and terms settings. Realtime is in preview and is billed while the session is open."
        case .elevenLabs, .openAI, .cohere, .aqua: nil
        }
    }
}
