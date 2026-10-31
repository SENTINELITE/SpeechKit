import SpeechKit
import SpeechKitVoz
import SwiftUI

/// The pages reachable from the settings root.
enum SettingsRoute: Hashable {
    case provider(DemoAPIKeyProvider)
    case voz
    case appleSpeech
    case relay
}

/// The settings root: which providers the workflows use, plus one page per provider.
///
/// Each provider keeps its key and options on its own page so the root stays a
/// short list as more providers are added.
struct SettingsSheet: View {
    @Bindable var configuration: DemoConfiguration
    @Environment(\.dismiss) private var dismiss
    @Environment(\.speechService) private var speech

    var body: some View {
        NavigationStack {
            Form {
                Section("Credentials") {
                    NavigationLink(value: SettingsRoute.relay) {
                        LabeledContent("Relay", value: configuration.isRelayEnabled ? (configuration.isRelayReady ? "Enabled" : "Reauthenticate") : "Off, vendor keys")
                    }
                }
                defaultProvidersSection
                cloudProvidersSection
                onDeviceSection
                Section {
                    Button("Clear private text", role: .destructive) { configuration.resetPrivateText() }
                } footer: {
                    Text("Prompts, names, and vocabulary stay in this app session. Clear removes them and any values saved by older versions. Transcripts and audio leave the app only when you choose an export or a cloud provider.")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .relay:
                    RelaySettingsView(configuration: configuration)
                case .provider(let provider):
                    ProviderSettingsView(configuration: configuration, provider: provider)
                case .voz:
                    VozSettingsView(speech: speech)
                case .appleSpeech:
                    if #available(iOS 26.0, *) {
                        AppleSpeechSettingsView(configuration: configuration, speech: speech)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    /// Chooses the provider each workflow uses when it starts.
    private var defaultProvidersSection: some View {
        Section {
            Picker("Realtime", selection: $configuration.realtimeProvider) {
                ForEach(DemoRealtimeProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }

            Picker("File & Dictation", selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(provider.requiresAPIKey && !configuration.hasAPIKey(for: provider))
                }
            }
        } header: {
            Text("Default Providers")
        } footer: {
            Text("Cloud providers use Relay while it is enabled, without loading vendor keys. Otherwise, save a provider key. On-device providers need neither.")
        }
    }

    /// Lists every cloud provider with its key status.
    private var cloudProvidersSection: some View {
        Section("Cloud Providers") {
            ForEach(DemoAPIKeyProvider.allCases) { provider in
                NavigationLink(value: SettingsRoute.provider(provider)) {
                    ProviderRow(provider: provider, hasKey: configuration.hasAPIKey(for: provider),
                                usesRelay: configuration.isRelayEnabled, relayReady: configuration.isRelayReady)
                }
            }
        }
    }

    /// Links to the on-device providers: VOZ everywhere, Apple Speech on iOS 26 and later.
    private var onDeviceSection: some View {
        Section("On-Device") {
            if DemoAppleSpeech.isAvailable {
                NavigationLink(value: SettingsRoute.appleSpeech) {
                    LabeledContent {
                        Text(configuration.appleLocaleIdentifier.isEmpty ? "Device Language" : Locale.current.localizedString(forIdentifier: configuration.appleLocaleIdentifier) ?? configuration.appleLocaleIdentifier)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Speech")
                            Text("Realtime · File & Dictation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            NavigationLink(value: SettingsRoute.voz) {
                LabeledContent {
                    Text(speech.vozModelState.summary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VOZ")
                        Text("File & Dictation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A cloud provider's name, the workflows it supports, and whether its key is saved.
private struct ProviderRow: View {
    let provider: DemoAPIKeyProvider
    let hasKey: Bool
    let usesRelay: Bool
    let relayReady: Bool

    var body: some View {
        LabeledContent {
            if usesRelay {
                Text(relayReady ? "Relay" : "Reauthenticate")
                    .font(.caption)
                    .foregroundStyle(relayReady ? .green : .secondary)
            } else {
                Image(systemName: hasKey ? "checkmark.circle.fill" : "key.slash")
                    .foregroundStyle(hasKey ? .green : .secondary)
                    .accessibilityLabel(hasKey ? "Key saved" : "No key")
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.title)
                Text(provider.capabilities)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct RelaySettingsView: View {
    @Bindable var configuration: DemoConfiguration
    @Environment(\.speechService) private var speech
    @Environment(\.scenePhase) private var scenePhase
    @State private var url = ""
    @State private var authentication = DemoRelayAuthentication.appAttest
    @State private var bearerToken = ""
    @State private var useVendorTokens = false
    @State private var optimizeUploads = true
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("https://relay.example.com", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Authentication", selection: $authentication) {
                    ForEach(DemoRelayAuthentication.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if authentication == .appAttest, !DemoConfiguration.supportsAppAttest {
                    Text("App Attest is unavailable on this device or Simulator. Choose Bearer test authentication explicitly or use a supported device. No fallback happens automatically.")
                        .foregroundStyle(.orange)
                }
                if authentication == .bearer {
                    SecureField("Short-lived Relay sign-in token, test only", text: $bearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Paste a backend-issued sign-in token, not a vendor key or Relay session ticket. This test entry is never saved or prefilled. The app releases it after five minutes; the backend must enforce its own expiry. Reapply with a fresh token to reauthenticate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if authentication == .none {
                    Text("Development only. No client authentication is sent. Use only a Relay configured for none-dev in an isolated test environment, never a production deployment.")
                        .foregroundStyle(.orange)
                }
                Toggle("Use vendor tokens when available", isOn: $useVendorTokens)
                Text("Off proxies every request through Relay. On allows supported short-lived vendor tokens and proxies other requests. Only providers configured on your Relay can succeed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Optimize uploads", isOn: $optimizeUploads)
                Text("On keeps supported audio unchanged, repackages AAC when needed, and converts other imports locally. Off sends original audio only or refuses it before uploading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Relay")
            } footer: {
                Text("Enter an HTTPS origin without a path, query, or credentials. HTTP is accepted only for loopback development. Applying settings stops current work and clears SDK credentials. No Relay requests occur until you start a workflow.")
            }
            Section {
                Button(configuration.isRelayEnabled ? "Apply and reauthenticate" : "Enable Relay") {
                    applyRelay()
                }
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          (authentication == .bearer && bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                          (authentication == .appAttest && !DemoConfiguration.supportsAppAttest))
                if configuration.isRelayEnabled {
                    Button("Disable Relay", role: .destructive) {
                        bearerToken = ""
                        isApplying = true
                        Task {
                            await configuration.disableRelay(in: speech)
                            isApplying = false
                            errorMessage = nil
                        }
                    }
                    Text(configuration.isRelayReady ? "Relay enabled. Vendor keys are not used." : "Relay authorization expired or was cleared. Reapply settings before using a cloud provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .disabled(isApplying || configuration.isResettingAuthorization)
        .interactiveDismissDisabled(isApplying)
        .navigationTitle("Relay")
        .onAppear {
            url = configuration.relayURL
            authentication = configuration.relayAuthentication
            useVendorTokens = configuration.relayUsesVendorTokens
            optimizeUploads = configuration.relayOptimizesUploads
            bearerToken = ""
        }
        .onDisappear { bearerToken = "" }
        .onChange(of: authentication) { _, _ in bearerToken = "" }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { bearerToken = "" }
        }
    }

    private func applyRelay() {
        let token = bearerToken
        bearerToken = ""
        isApplying = true
        errorMessage = nil
        Task {
            defer { isApplying = false }
            do {
                try await configuration.enableRelay(url: url, authentication: authentication, bearerToken: token,
                                                    useVendorTokens: useVendorTokens, optimizeUploads: optimizeUploads, replacing: speech)
                configuration.relayService?.voz = speech.voz
            } catch {
                errorMessage = DemoFailure.message(for: error)
            }
        }
    }
}

extension VozModelState {
    /// A short status for the settings root row.
    var summary: String {
        switch self {
        case .unprepared: "Not loaded"
        case .checkingCache: "Checking…"
        case .downloading(let progress): progress.formatted(.percent.precision(.fractionLength(0)))
        case .loading: "Loading…"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }
}
