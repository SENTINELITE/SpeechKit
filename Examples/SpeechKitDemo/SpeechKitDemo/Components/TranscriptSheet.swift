import SpeechKit
import SpeechKitVoz
import SwiftUI

/// A transcript snapshot to present in ``TranscriptSheet``.
///
/// Presenting with `.sheet(item:)` hands the text to the sheet together with the
/// presentation. With `.sheet(isPresented:)` plus separate `@State` text, the
/// first presentation rendered the stale empty value.
struct DemoTranscript: Identifiable {
    let id = UUID()
    let text: String
    var vozResponse: VozFileTranscriptionResponse?
}

/// A small transcript reader used by realtime, recorded-upload, and file-upload examples.
struct TranscriptSheet: View {
    let transcript: String
    let vozResponse: VozFileTranscriptionResponse?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(transcript.isEmpty ? "No transcript yet." : transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let vozResponse {
                    VozTranscriptionDetailView(response: vozResponse)
                }
            }
            .padding()
            .navigationTitle("Transcript")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }
}
