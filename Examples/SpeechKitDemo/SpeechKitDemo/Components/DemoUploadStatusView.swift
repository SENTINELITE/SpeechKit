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
