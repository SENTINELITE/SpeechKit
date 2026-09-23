import Foundation
import SpeechKit
import SpeechKitVoz
import SwiftUI

/// A progress surface for long-running provider uploads.
struct DemoUploadStatusView: View {
    let providerName: String
    let startedAt: Date?
    let timeoutInterval: TimeInterval?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0

            VStack(alignment: .leading, spacing: 8) {
                ProgressView("Uploading to \(providerName)...")

                if let timeoutInterval {
                    ProgressView(value: min(elapsed / timeoutInterval, 1))
                    LabeledContent("Elapsed", value: elapsed.formattedDuration)
                    LabeledContent("Timeout in", value: max(timeoutInterval - elapsed, 0).formattedDuration)
                } else {
                    LabeledContent("Elapsed", value: elapsed.formattedDuration)
                    Text("Waiting for provider response")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Formats upload timing for compact demo status rows.
extension TimeInterval {
    var formattedDuration: String {
        let totalSeconds = max(Int(rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes)m \(seconds)s"
    }
}

/// A progress surface for on-device providers, whose audio stays on this device while it is transcribed.
struct DemoLocalTranscriptionStatusView: View {
    let startedAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0

            VStack(alignment: .leading, spacing: 8) {
                ProgressView("Transcribing on this device…")
                LabeledContent("Elapsed", value: elapsed.formattedDuration)
                Text("Audio transcription runs on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Shows the detailed timing data produced by a completed VOZ local transcription.
struct VozTranscriptionDetailView: View {
    let response: VozFileTranscriptionResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Processed locally by VOZ", systemImage: "lock.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)

            LabeledContent("Audio duration", value: response.duration.formattedMetricDuration)
            LabeledContent("Processing time", value: response.processingTime.formattedMetricDuration)
            LabeledContent("Speed", value: String(format: "%.2fx realtime", response.realtimeFactor))

            if !response.words.isEmpty {
                DisclosureGroup("Word timestamps (\(response.words.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(response.words.enumerated()), id: \.offset) { _, word in
                            LabeledContent(word.text, value: "\(word.startTime.formattedTimestamp) – \(word.endTime.formattedTimestamp)")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 4)
    }
}

private extension TimeInterval {
    var formattedMetricDuration: String {
        String(format: "%.2f s", self)
    }

    var formattedTimestamp: String {
        let minutes = Int(self) / 60
        let seconds = self - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }
}
