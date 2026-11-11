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
                        .disabled(provider.requiresAPIKey && !configuration.hasAPIKey(for: provider))
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
    /// The provider whose options to show; `nil` follows the current file provider.
    var provider: DemoFileProvider?

    var body: some View {
        switch provider ?? configuration.fileProvider {
        case .elevenLabs:
            let isScribeV3 = configuration.elevenLabsFileModel == .scribeV3
            Picker("Model", selection: $configuration.elevenLabsFileModel) {
                ForEach([ElevenLabsModelID.scribeV3, .scribeV2, .scribeV2Medical], id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Toggle("Diarize", isOn: $configuration.elevenLabsDiarize)

            Toggle("Limit speakers", isOn: $configuration.elevenLabsSpeakerLimit)
                .disabled(!configuration.elevenLabsDiarize)
            if configuration.elevenLabsSpeakerLimit {
                Stepper("Speakers: \(configuration.elevenLabsSpeakerCount)", value: $configuration.elevenLabsSpeakerCount, in: 1...32)
                    .disabled(!configuration.elevenLabsDiarize)
            }

            Picker("Numbers", selection: $configuration.elevenLabsNumbersFormat) {
                ForEach(DemoElevenLabsNumbersFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            .disabled(!isScribeV3)

            TextField("Secondary languages (comma separated)", text: $configuration.elevenLabsSecondaryLanguages)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(!isScribeV3)

            TextField("Keyterms (comma or newline separated)", text: $configuration.elevenLabsKeyterms, axis: .vertical)
                .lineLimit(2...4)

            Toggle("Tag audio events", isOn: $configuration.elevenLabsTagAudioEvents)
            Toggle("No verbatim", isOn: $configuration.elevenLabsNoVerbatim)

            if !isScribeV3 {
                Text("Numbers format and secondary languages need scribe_v3.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            TextField("Languages (comma separated)", text: $configuration.openAILanguages)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Prompt", text: $configuration.openAIPrompt, axis: .vertical)
                .lineLimit(2...4)

            TextField("Keywords (comma separated)", text: $configuration.openAIKeywords, axis: .vertical)
                .lineLimit(2...4)

            TextField("Temperature", text: $configuration.openAITemperature)
                .keyboardType(.decimalPad)

            LabeledContent("Timeout", value: "\(Int(configuration.openAITimeoutMinutes)) min")
            Slider(value: $configuration.openAITimeoutMinutes, in: 1...30, step: 1)
            Toggle("Include logprobs", isOn: $configuration.openAIIncludeLogprobs)
            Toggle("Word timestamps", isOn: $configuration.openAIWordTimestamps)
            Toggle("Segment timestamps", isOn: $configuration.openAISegmentTimestamps)
            Toggle("Diarization", isOn: $configuration.openAIDiarization)
        case .meta:
            Picker("Model", selection: $configuration.metaModel) {
                ForEach(MetaModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Mode", selection: $configuration.metaMode) {
                ForEach(MetaTranscriptionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Picker("Language bias", selection: $configuration.metaLanguage) {
                Text("Default").tag(MetaLanguage?.none)
                ForEach(MetaLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(MetaLanguage?.some(language))
                }
            }

            TextField("Keywords (comma separated)", text: $configuration.metaKeywords, axis: .vertical)
                .lineLimit(2...4)
        case .gemini:
            Picker("Model", selection: $configuration.geminiFileModel) {
                ForEach(GeminiFileTranscriptionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Mode", selection: $configuration.geminiMode) {
                ForEach(GeminiTranscriptionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            TextField("Language codes (comma separated)", text: $configuration.geminiLanguageCodes)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Custom vocabulary (comma separated)", text: $configuration.geminiCustomVocabulary, axis: .vertical)
                .lineLimit(2...4)

            Toggle("Diarize", isOn: $configuration.geminiDiarize)
            Toggle("Word timestamps", isOn: $configuration.geminiWordTimestamps)
            Toggle("Background processing", isOn: $configuration.geminiBackgroundProcessing)

            Text("Gemini rejects a custom vocabulary combined with diarization or word timestamps. Leave the vocabulary empty to use either one.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .mistral:
            Picker("Model", selection: $configuration.mistralFileModel) {
                ForEach(MistralFileTranscriptionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            TextField("Language code (e.g. en)", text: $configuration.mistralLanguage)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Context bias (comma separated)", text: $configuration.mistralContextBias, axis: .vertical)
                .lineLimit(2...4)

            Toggle("Diarize", isOn: $configuration.mistralDiarize)
        case .fishAudio:
            TextField("Language hint (e.g. en)", text: $configuration.fishAudioLanguage)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Picker("Diarization", selection: $configuration.fishAudioDiarize) {
                ForEach(FishAudioDiarization.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Toggle("Word timestamps", isOn: $configuration.fishAudioTimestamps)
            Toggle("Sound tags", isOn: $configuration.fishAudioTagAudioEvents)

            Text("Fish Audio accepts up to 60 minutes of audio and rejects AIFF and CAF files. Speaker labels need word timestamps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .voz:
            Label("Runs locally after its model is downloaded and prepared in Settings. VOZ supports 25 languages but does not detect language or accept a language hint.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .apple:
            Label("Runs locally with Apple's Speech framework in \(configuration.appleLocale.localizedString(forIdentifier: configuration.appleLocale.identifier) ?? configuration.appleLocale.identifier). Change the language in Settings.", systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Option controls that only affect a provider's realtime sessions.
///
/// Settings that realtime and file transcription share, such as language or
/// mode, live in ``FileProviderOptionsView`` so each appears only once.
struct RealtimeOnlyOptionsView: View {
    @Bindable var configuration: DemoConfiguration
    let provider: DemoRealtimeProvider

    var body: some View {
        switch provider {
        case .elevenLabs:
            let isScribeV3Live = configuration.elevenLabsRealtimeModel == .scribeV3Live
            Picker("Model", selection: $configuration.elevenLabsRealtimeModel) {
                Text(ElevenLabsModelID.scribeV3Live.rawValue).tag(ElevenLabsModelID.scribeV3Live)
                Text(ElevenLabsModelID.scribeV2Realtime.rawValue).tag(ElevenLabsModelID.scribeV2Realtime)
            }

            Picker("Commit strategy", selection: $configuration.elevenLabsRealtimeCommitStrategy) {
                ForEach(DemoElevenLabsCommitStrategy.allCases) { strategy in
                    Text(strategy.title)
                        .tag(strategy)
                        .disabled(strategy == .turnPrediction && !isScribeV3Live)
                }
            }

            Toggle("Speaker labels", isOn: $configuration.elevenLabsRealtimeDiarize)
                .disabled(!isScribeV3Live)
            Toggle("Multilingual mode", isOn: $configuration.elevenLabsRealtimeMultilingual)
                .disabled(!isScribeV3Live)

            TextField("Keyterms (comma or newline separated)", text: $configuration.elevenLabsRealtimeKeyterms, axis: .vertical)
                .lineLimit(2...4)

            if !isScribeV3Live {
                Text("Speaker labels, multilingual mode, and turn prediction need scribe_v3_live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .openAI:
            Picker("Session model", selection: $configuration.openAIRealtimeSessionModel) {
                ForEach(OpenAIRealtimeSessionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Transcription model", selection: $configuration.openAIRealtimeTranscriptionModel) {
                ForEach(OpenAIRealtimeTranscriptionModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }

            Picker("Live delay", selection: $configuration.openAIRealtimeDelay) {
                ForEach(DemoOpenAIRealtimeDelay.allCases) { delay in
                    Text(delay.rawValue).tag(delay)
                }
            }
        case .grok:
            Toggle("Filler words", isOn: $configuration.grokRealtimeFillerWords)
        case .meta:
            Picker("Partials", selection: $configuration.metaRealtimePartialMode) {
                ForEach(MetaPartialMode.allCases, id: \.self) { partialMode in
                    Text(partialMode.rawValue).tag(partialMode)
                }
            }
        case .gemini:
            Picker("Live model", selection: $configuration.geminiRealtimeModel) {
                ForEach(GeminiRealtimeModelID.allCases, id: \.self) { model in
                    Text(model.rawValue).tag(model)
                }
            }
        case .mistral:
            Picker("Streaming delay", selection: $configuration.mistralRealtimeDelay) {
                ForEach(DemoMistralStreamingDelay.allCases) { delay in
                    Text(delay.title).tag(delay)
                }
            }
        case .fishAudio:
            Picker("Turn detection", selection: $configuration.fishAudioRealtimeMode) {
                ForEach(FishAudioTurnDetectionMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }

            Toggle("Speaker labels", isOn: $configuration.fishAudioRealtimeDiarize)

            TextField("Terms (comma separated)", text: $configuration.fishAudioRealtimeTerms, axis: .vertical)
                .lineLimit(2...4)

            Text("Realtime is in preview. Fish Audio bills every second the session is open, including silence, so stop when you are done.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .apple:
            EmptyView()
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

/// Human-readable names for Meta language controls.
///
/// Meta biases transcription with language names, so each raw value is already
/// a display name.
extension MetaLanguage {
    var displayName: String { rawValue }
}

/// Speaker-labeled text for diarized ElevenLabs file transcripts.
extension ElevenLabsFileTranscriptionResponse {
    /// One `speaker_0: text` line per speaker turn, merging consecutive words from
    /// the same speaker. Falls back to ``text`` when no word has a speaker.
    var speakerLabeledText: String {
        guard let words, words.contains(where: { $0.speakerID != nil }) else { return text }

        var turns: [(speaker: String?, text: String)] = []
        for word in words {
            // A spacing token with no speaker belongs to the turn it sits in.
            let joinsCurrentTurn = word.speakerID == nil && word.type == "spacing"
            if let last = turns.last, last.speaker == word.speakerID || joinsCurrentTurn {
                turns[turns.count - 1].text += word.text
            } else {
                turns.append((word.speakerID, word.text))
            }
        }
        return turns
            .map { turn in
                let turnText = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return turn.speaker.map { "\($0): \(turnText)" } ?? turnText
            }
            .joined(separator: "\n\n")
    }
}

/// Speaker-labeled text for diarized realtime entries, such as ElevenLabs speaker runs.
extension [SpeechTranscriptEntry] {
    /// One `speaker_0: text` line per speaker turn, merging consecutive entries
    /// from the same speaker. Falls back to plain joined text when no entry has a speaker.
    var speakerLabeledText: String {
        guard contains(where: { $0.speaker != nil }) else {
            return map(\.text).joined(separator: " ")
        }

        var turns: [(speaker: String?, text: String)] = []
        for entry in self {
            let entryText = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entryText.isEmpty else { continue }
            if let last = turns.last, last.speaker == entry.speaker {
                turns[turns.count - 1].text = last.text + " " + entryText
            } else {
                turns.append((entry.speaker, entryText))
            }
        }
        return turns
            .map { turn in turn.speaker.map { "\($0): \(turn.text)" } ?? turn.text }
            .joined(separator: "\n\n")
    }
}

/// Speaker-labeled text for diarized Mistral file transcripts.
extension MistralFileTranscriptionResponse {
    /// One `speaker_1: text` line per speaker turn, merging consecutive segments
    /// from the same speaker. Falls back to ``text`` when no segment has a speaker.
    var speakerLabeledText: String {
        guard segments.contains(where: { $0.speakerID != nil }) else { return text }

        var turns: [(speaker: String?, text: String)] = []
        for segment in segments {
            let segmentText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segmentText.isEmpty else { continue }
            if let last = turns.last, last.speaker == segment.speakerID {
                turns[turns.count - 1].text = last.text + " " + segmentText
            } else {
                turns.append((segment.speakerID, segmentText))
            }
        }
        return turns
            .map { turn in turn.speaker.map { "\($0): \(turn.text)" } ?? turn.text }
            .joined(separator: "\n\n")
    }
}

/// Human-readable names for Fish Audio diarization modes, whose raw values are `auto`, `true`, and `false`.
extension FishAudioDiarization {
    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .on: "On"
        case .off: "Off"
        }
    }
}

/// Speaker-labeled text for Fish Audio file transcripts.
extension FishAudioFileTranscriptionResponse {
    /// One `speaker:0: text` line per speaker, merging consecutive turns from the
    /// same speaker. Falls back to ``transcriptText`` when there are no speaker turns.
    var speakerLabeledText: String {
        guard !speakerTurns.isEmpty else { return transcriptText }

        var turns: [(speaker: String, text: String)] = []
        for turn in speakerTurns {
            let turnText = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !turnText.isEmpty else { continue }
            if let last = turns.last, last.speaker == turn.speaker {
                turns[turns.count - 1].text = last.text + " " + turnText
            } else {
                turns.append((turn.speaker, turnText))
            }
        }
        return turns
            .map { "\($0.speaker): \($0.text)" }
            .joined(separator: "\n\n")
    }
}
