import Speech
import SpeechKit
import SwiftUI

/// Configures Apple's on-device Speech framework for realtime and file transcription.
@available(iOS 26.0, *)
struct AppleSpeechSettingsView: View {
    @Bindable var configuration: DemoConfiguration
    let speech: SpeechService

    @State private var supportedLocales: [Locale] = []
    @State private var assetState = AssetState.idle

    private enum AssetState: Equatable {
        case idle
        case preparing
        case ready
        case failed(String)
    }

    var body: some View {
        Form {
            languageSection
            assetsSection
            optionsSection
        }
        .navigationTitle("Apple Speech")
        .task {
            supportedLocales = await SpeechTranscriber.supportedLocales
                .sorted { displayName(for: $0) < displayName(for: $1) }
        }
        .onChange(of: configuration.appleLocaleIdentifier) { _, _ in
            assetState = .idle
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $configuration.appleLocaleIdentifier) {
                Text("Device Language").tag("")
                ForEach(supportedLocales, id: \.identifier) { locale in
                    Text(displayName(for: locale)).tag(locale.identifier)
                }
            }
        } footer: {
            Text("Apple Speech does not detect the spoken language, so pick the one you will speak.")
        }
    }

    private var assetsSection: some View {
        Section {
            switch assetState {
            case .idle:
                Button("Download Speech Assets", action: prepareAssets)
            case .preparing:
                ProgressView("Preparing assets…")
                    .frame(maxWidth: .infinity)
            case .ready:
                Label("Assets ready", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Retry", action: prepareAssets)
            }
        } header: {
            Text("Assets")
        } footer: {
            Text("The system downloads a language's speech model the first time it is used. Downloading here keeps that wait out of your first recording.")
        }
    }

    private var optionsSection: some View {
        Section {
            TextField("Contextual strings (comma separated)", text: $configuration.appleContextualStrings, axis: .vertical)
                .lineLimit(2...4)

            Picker("Keep models loaded", selection: $configuration.appleModelRetention) {
                ForEach(DemoAppleModelRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Contextual strings bias recognition toward names and terms you expect. Keeping models loaded longer makes the next session start faster.")
        }
    }

    private func prepareAssets() {
        assetState = .preparing
        configuration.apply(to: speech)
        Task {
            do {
                try await speech.prepareAppleSpeechAssets()
                assetState = .ready
            } catch {
                assetState = .failed(error.localizedDescription)
            }
        }
    }

    private func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}
