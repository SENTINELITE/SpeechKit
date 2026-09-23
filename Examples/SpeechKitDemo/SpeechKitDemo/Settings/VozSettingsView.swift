import SpeechKit
import SpeechKitVoz
import SwiftUI

/// Manages the optional VOZ model that performs file transcription entirely on this device.
///
/// VOZ reports a percentage only while downloading. Cache verification and the
/// Core ML load report no progress, so those phases show elapsed time instead.
struct VozSettingsView: View {
    let speech: SpeechService
    /// Whether verified model files are on disk, so preparing skips the download.
    @State private var isModelCached = false
    /// When the current cache check or load began, for the elapsed-time readout.
    @State private var phaseStartedAt: Date?

    var body: some View {
        Form {
            statusSection
            actionsSection
            aboutSection
        }
        .navigationTitle("VOZ")
        .onAppear {
            updatePhaseStart(for: speech.vozModelState)
        }
        .onChange(of: speech.vozModelState) { _, state in
            updatePhaseStart(for: state)
        }
        .task(id: isReady) {
            // `isModelCached()` verifies every cached file's digest, so keep it off
            // the main actor and only re-check when the model finishes loading.
            guard let voz = speech.voz else { return }
            isModelCached = await Task.detached { voz.isModelCached() }.value
        }
    }

    private var statusSection: some View {
        Section {
            Label(stateTitle, systemImage: statusImageName)
                .foregroundStyle(statusColor)

            switch speech.vozModelState {
            case .downloading:
                ProgressView(value: speech.vozModelDownloadProgress)
                LabeledContent(
                    "Downloaded",
                    value: speech.vozModelDownloadProgress,
                    format: .percent.precision(.fractionLength(0))
                )
            case .checkingCache, .loading:
                elapsedTimeRow
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            case .unprepared, .ready:
                EmptyView()
            }
        } header: {
            Text("Model")
        } footer: {
            Text(statusFooter)
        }
    }

    /// Shows how long the current unmeasurable phase has been running.
    @ViewBuilder
    private var elapsedTimeRow: some View {
        if let phaseStartedAt {
            TimelineView(.periodic(from: phaseStartedAt, by: 1)) { context in
                LabeledContent("Elapsed") {
                    Text(Duration.seconds(context.date.timeIntervalSince(phaseStartedAt)), format: .units(allowed: [.minutes, .seconds], width: .abbreviated))
                        .monospacedDigit()
                }
            }
        }
        ProgressView()
            .frame(maxWidth: .infinity)
    }

    private var actionsSection: some View {
        Section {
            if isPreparing {
                Button("Cancel", role: .cancel, action: speech.releaseVozModel)
            } else if !isReady {
                Button(preparationActionTitle, action: speech.prepareVozModelInBackground)
            }

            Button("Unload Model", role: .destructive, action: speech.releaseVozModel)
                .disabled(isPreparing || isUnprepared)
        } footer: {
            Text("Unloading frees memory and keeps the downloaded files for the next launch.")
        }
    }

    private var aboutSection: some View {
        Section {
            Text("VOZ transcribes selected and recorded audio on this device. The first download is about 467 MB.")
                .font(.callout)
            Link("Powered by Desert Ant Labs", destination: URL(string: "https://desertant.com")!)
            Link("VOZ License", destination: URL(string: "https://license.desertant.com/1.0")!)
        } header: {
            Text("About")
        }
    }

    private func updatePhaseStart(for state: VozModelState) {
        switch state {
        case .checkingCache, .loading:
            phaseStartedAt = .now
        case .unprepared, .downloading, .ready, .failed:
            phaseStartedAt = nil
        }
    }

    private var stateTitle: String {
        switch speech.vozModelState {
        case .unprepared:
            isModelCached ? "Downloaded, not loaded" : "Not downloaded"
        case .checkingCache:
            "Verifying cached files"
        case .downloading:
            "Downloading"
        case .loading:
            "Loading into memory"
        case .ready:
            "Ready for local transcription"
        case .failed:
            "Preparation failed"
        }
    }

    private var statusFooter: String {
        switch speech.vozModelState {
        case .checkingCache:
            "VOZ checks every cached file's digest before loading. This reports no progress."
        case .loading:
            "The first load after a download takes about 20 seconds while the Neural Engine specializes the model. Later loads take a fraction of a second. Core ML reports no progress for this step."
        case .unprepared where isModelCached:
            "The model files are on this device. Loading them does not download anything."
        case .unprepared, .downloading, .ready, .failed:
            "The model has to be loaded into memory on every launch. Once downloaded, the demo loads it in the background at launch."
        }
    }

    private var isPreparing: Bool {
        switch speech.vozModelState {
        case .checkingCache, .downloading, .loading: true
        case .unprepared, .ready, .failed: false
        }
    }

    private var isReady: Bool {
        if case .ready = speech.vozModelState { return true }
        return false
    }

    private var isUnprepared: Bool {
        if case .unprepared = speech.vozModelState { return true }
        return false
    }

    private var preparationActionTitle: String {
        if case .failed = speech.vozModelState { return "Retry" }
        return isModelCached ? "Load Model" : "Download and Load"
    }

    private var statusImageName: String {
        switch speech.vozModelState {
        case .unprepared: isModelCached ? "internaldrive" : "arrow.down.circle"
        case .checkingCache: "magnifyingglass.circle"
        case .downloading: "arrow.down.circle.fill"
        case .loading: "gearshape.2"
        case .ready: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch speech.vozModelState {
        case .ready: .green
        case .failed: .red
        case .unprepared, .checkingCache, .downloading, .loading: .secondary
        }
    }
}
