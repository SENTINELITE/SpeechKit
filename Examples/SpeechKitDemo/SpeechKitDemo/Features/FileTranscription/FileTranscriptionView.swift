import SpeechKit
import SwiftUI
import UniformTypeIdentifiers

/// A standalone sample for importing an existing audio or movie file and sending it to SpeechKit.
struct FileTranscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration

    @State private var isImporterPresented = false
    @State private var selectedFile: URL?
    @State private var transcript: String?
    @State private var errorMessage: String?
    @State private var isTranscribing = false
    @State private var startedAt: Date?
    @State private var activeTimeout: TimeInterval?

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                audioFileSection
                resultSection
            }
            .navigationTitle("File Transcription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio, .movie],
                allowsMultipleSelection: false,
                onCompletion: handleImportResult
            )
        }
    }

    /// Selects the provider and exposes the shared file-option controls for this workflow.
    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(!configuration.hasAPIKey(for: provider))
                }
            }
            .pickerStyle(.segmented)

            if !configuration.hasAPIKey(for: configuration.fileProvider) {
                Label(configuration.missingAPIKeyMessage(for: configuration.fileProvider), systemImage: "key.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            FileProviderOptionsView(configuration: configuration)
        }
    }

    /// Lets a reader inspect the minimum code needed to pick a file and call transcription.
    private var audioFileSection: some View {
        Section("Audio File") {
            Button {
                isImporterPresented = true
            } label: {
                Label("Select audio file", systemImage: "waveform.badge.plus")
            }
            .disabled(isTranscribing)

            if let selectedFile {
                LabeledContent("Selected", value: selectedFile.lastPathComponent)

                Button {
                    Task {
                        await transcribe(selectedFile)
                    }
                } label: {
                    Label("Transcribe selected file", systemImage: "text.bubble")
                }
                .disabled(isTranscribing || !configuration.hasAPIKey(for: configuration.fileProvider))
            }
        }
    }

    /// Displays upload progress, errors, or the provider transcript.
    private var resultSection: some View {
        Section("Result") {
            if isTranscribing {
                DemoUploadStatusView(
                    providerName: configuration.fileProvider.title,
                    startedAt: startedAt,
                    timeoutInterval: activeTimeout
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let transcript {
                Text(transcript)
                    .textSelection(.enabled)
            } else if !isTranscribing {
                Text("No transcription yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Stores the imported file URL and clears stale result state.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFile = urls.first
            transcript = nil
            errorMessage = nil
        case .failure(let error):
            errorMessage = "Failed to import audio: \(error.localizedDescription)"
        }
    }

    /// Calls SpeechKit with a security-scoped URL so files picked outside the sandbox remain readable.
    private func transcribe(_ url: URL) async {
        guard configuration.hasAPIKey(for: configuration.fileProvider) else {
            errorMessage = configuration.missingAPIKeyMessage(for: configuration.fileProvider)
            return
        }

        configuration.apply(to: speech)
        isTranscribing = true
        startedAt = Date()
        activeTimeout = configuration.timeoutInterval(for: configuration.fileProvider)
        errorMessage = nil
        transcript = nil
        defer {
            isTranscribing = false
            startedAt = nil
            activeTimeout = nil
        }

        do {
            transcript = try await speech.transcribeAudioFile(
                provider: configuration.fileProvider.speechProvider,
                securityScopedURL: url,
                options: configuration.fileOptions(for: configuration.fileProvider)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
