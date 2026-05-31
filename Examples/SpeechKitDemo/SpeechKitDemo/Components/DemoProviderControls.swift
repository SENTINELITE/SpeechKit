import SpeechKit
import SwiftUI

/// A provider picker for file-based SpeechKit workflows.
struct FileProviderPicker: View {
    @Bindable var configuration: DemoConfiguration
    let title: String

    var body: some View {
        Section(title) {
            Picker(title, selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }
        }
    }
}

/// A provider picker for realtime SpeechKit workflows.
struct RealtimeProviderPicker: View {
    @Bindable var configuration: DemoConfiguration

    var body: some View {
        Section("Realtime Provider") {
            Picker("Realtime Provider", selection: $configuration.realtimeProvider) {
                ForEach(DemoRealtimeProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }
        }
    }
}

/// Shared provider-specific option controls for file import and recorded-upload transcription.
struct FileProviderOptionsView: View {
    @Bindable var configuration: DemoConfiguration

    var body: some View {
        switch configuration.fileProvider {
        case .elevenLabs:
            Picker("Model", selection: $configuration.elevenLabsFileModel) {
                ForEach([ElevenLabsModelID.scribeV1, ElevenLabsModelID.scribeV2], id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }
        case .aqua:
            Picker("Model", selection: $configuration.aquaModel) {
                ForEach(AquaModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Language", selection: $configuration.aquaLanguage) {
                Text("Default").tag(AquaLanguage?.none)
                ForEach(AquaLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(AquaLanguage?.some(language))
                }
            }
        case .cohere:
            Picker("Model", selection: $configuration.cohereModel) {
                ForEach(CohereModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Language", selection: $configuration.cohereLanguage) {
                ForEach(CohereLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }

            TextField("Temperature", text: $configuration.cohereTemperature)
                .keyboardType(.decimalPad)
        case .grok:
            Picker("Model", selection: $configuration.grokModel) {
                ForEach(GrokModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Language", selection: $configuration.grokLanguage) {
                Text("Default").tag(GrokLanguage?.none)
                ForEach(GrokLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(GrokLanguage?.some(language))
                }
            }

            LabeledContent("Timeout", value: "\(Int(configuration.grokTimeoutMinutes)) min")
            Slider(value: $configuration.grokTimeoutMinutes, in: 1...30, step: 1)
            Toggle("Format transcript", isOn: $configuration.grokFormat)
            Toggle("Multichannel", isOn: $configuration.grokMultichannel)
            Toggle("Diarize", isOn: $configuration.grokDiarize)
        case .openAI:
            Picker("Model", selection: $configuration.openAIFileModel) {
                ForEach(OpenAIFileTranscriptionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            TextField("Language hint", text: $configuration.openAILanguage)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Prompt", text: $configuration.openAIPrompt, axis: .vertical)
                .lineLimit(2...4)

            TextField("Temperature", text: $configuration.openAITemperature)
                .keyboardType(.decimalPad)

            LabeledContent("Timeout", value: "\(Int(configuration.openAITimeoutMinutes)) min")
            Slider(value: $configuration.openAITimeoutMinutes, in: 1...30, step: 1)
            Toggle("Include logprobs", isOn: $configuration.openAIIncludeLogprobs)
            Toggle("Word timestamps", isOn: $configuration.openAIWordTimestamps)
            Toggle("Segment timestamps", isOn: $configuration.openAISegmentTimestamps)
            Toggle("Diarization", isOn: $configuration.openAIDiarization)
        }
    }
}

/// Human-readable names for Aqua language controls.
extension AquaLanguage {
    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .english: "English"
        case .german: "German"
        case .spanish: "Spanish"
        case .french: "French"
        case .japanese: "Japanese"
        case .russian: "Russian"
        }
    }
}

/// Human-readable names for Cohere language controls.
extension CohereLanguage {
    var displayName: String {
        "\(rawValue) - \(String(describing: self))"
    }
}

/// Human-readable names for Grok language controls.
extension GrokLanguage {
    var displayName: String {
        "\(rawValue) - \(String(describing: self))"
    }
}
