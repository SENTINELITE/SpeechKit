import SpeechKit
import SpeechKitVoz
import SwiftUI

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
