import SpeechKit
import SpeechKitVoz
import SwiftUI

/// The pages reachable from the settings root.
enum SettingsRoute: Hashable {
    case provider(DemoAPIKeyProvider)
    case voz
    case appleSpeech
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
                defaultProvidersSection
                cloudProvidersSection
                onDeviceSection
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
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
            Text("A cloud provider becomes selectable once its API key is saved. On-device providers need no key.")
        }
    }

    /// Lists every cloud provider with its key status.
    private var cloudProvidersSection: some View {
        Section("Cloud Providers") {
            ForEach(DemoAPIKeyProvider.allCases) { provider in
                NavigationLink(value: SettingsRoute.provider(provider)) {
                    ProviderRow(provider: provider, hasKey: configuration.hasAPIKey(for: provider))
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

    var body: some View {
        LabeledContent {
            Image(systemName: hasKey ? "checkmark.circle.fill" : "key.slash")
                .foregroundStyle(hasKey ? .green : .secondary)
                .accessibilityLabel(hasKey ? "Key saved" : "No key")
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
