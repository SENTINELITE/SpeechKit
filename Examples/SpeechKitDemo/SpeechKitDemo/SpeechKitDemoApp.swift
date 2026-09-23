import Foundation
import SpeechKit
import SpeechKitVoz
import SwiftUI

/// The demo app entry point that owns the shared `SpeechService` for all sample workflows.
@main
struct SpeechKitDemoApp: App {
    @State private var speech: SpeechService = {
        let speech = SpeechService()
        // Attach VOZ once: the transcriber owns the loaded model, so replacing it
        // later would throw that model away.
        speech.voz = VozTranscriber()
        return speech
    }()
#if DEBUG
    @State private var hasRunVozSmokeTest = false
#endif

    /// Creates the main window and injects SpeechKit into SwiftUI environment values.
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.speechService, speech)
                .task {
                    await prepareCachedVozModel()
                }
#if DEBUG
                .task {
                    guard CommandLine.arguments.contains("--voz-smoke-test"), !hasRunVozSmokeTest else {
                        return
                    }

                    hasRunVozSmokeTest = true
                    await VozSmokeTestRunner.run(using: speech)
                }
#endif
        }
    }

    /// Loads the VOZ model at launch when its files are already on disk.
    ///
    /// The model has to be loaded into memory on every launch, so the demo starts
    /// that work early instead of making the first transcription wait. It never
    /// starts the initial download on its own; that stays behind an explicit
    /// button in Settings.
    private func prepareCachedVozModel() async {
        guard let voz = speech.voz else { return }
        let isCached = await Task.detached { voz.isModelCached() }.value
        if isCached {
            voz.prepareInBackground()
        }
    }
}

#if DEBUG
private enum VozSmokeTestRunner {
    private static let inputFileName = "voz-smoke-input.aiff"
    private static let resultFileName = "voz-smoke-result.json"

    @MainActor
    static func run(using speech: SpeechService) async {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        let inputURL = documentsDirectory.appendingPathComponent(inputFileName)
        let resultURL = documentsDirectory.appendingPathComponent(resultFileName)

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            write(
                VozSmokeTestResult(
                    success: false,
                    error: "Missing smoke-test input at \(inputURL.path)."
                ),
                to: resultURL
            )
            return
        }

        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            write(
                VozSmokeTestResult(
                    success: false,
                    error: "Smoke-test input is not readable at \(inputURL.path)."
                ),
                to: resultURL
            )
            return
        }

        let preparationStarted = Date()

        do {
            try await speech.prepareVozModel()
            let preparationTime = Date().timeIntervalSince(preparationStarted)
            let response = try await speech.transcribeVozAudioFile(file: inputURL)
            let words = response.words
            let isValid = !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !words.isEmpty
                && response.duration.isFinite
                && response.duration > 0
                && response.processingTime.isFinite
                && response.processingTime >= 0
                && preparationTime.isFinite
                && preparationTime >= 0
                && words.allSatisfy { word in
                    !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && word.startTime.isFinite
                        && word.endTime.isFinite
                        && word.startTime >= 0
                        && word.endTime >= word.startTime
                        && word.endTime <= response.duration
                }
            let result = VozSmokeTestResult(
                success: isValid,
                text: response.text,
                words: words.map(\.text),
                times: words.map {
                    VozSmokeTestWordTime(startTime: $0.startTime, endTime: $0.endTime)
                },
                duration: response.duration,
                processingTime: response.processingTime,
                preparationTime: preparationTime,
                error: isValid ? nil : "VOZ returned an invalid smoke-test transcription result."
            )
            write(result, to: resultURL)
            if isValid {
                print(
                    "VOZ smoke succeeded: \(words.count) words, "
                        + "\(String(format: "%.2f", response.duration))s audio, "
                        + "\(String(format: "%.2f", response.processingTime))s processing."
                )
            } else {
                print("VOZ smoke failed: \(result.error ?? "Invalid transcription result.")")
            }
        } catch {
            let preparationTime = Date().timeIntervalSince(preparationStarted)
            let errorDescription = describe(error)
            write(
                VozSmokeTestResult(
                    success: false,
                    preparationTime: preparationTime,
                    error: errorDescription
                ),
                to: resultURL
            )
            print("VOZ smoke failed: \(errorDescription)")
        }
    }

    private static func write(_ result: VozSmokeTestResult, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(result).write(to: url, options: .atomic)
        } catch {
            print("VOZ smoke could not write result: \(describe(error))")
        }
    }

    private static func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription {
            return errorDescription
        }
        return String(describing: error)
    }
}

private struct VozSmokeTestResult: Encodable {
    let success: Bool
    let text: String?
    let words: [String]?
    let times: [VozSmokeTestWordTime]?
    let duration: TimeInterval?
    let processingTime: TimeInterval?
    let preparationTime: TimeInterval?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case text
        case words
        case times
        case duration
        case processingTime
        case preparationTime
        case error
    }

    init(
        success: Bool,
        text: String? = nil,
        words: [String]? = nil,
        times: [VozSmokeTestWordTime]? = nil,
        duration: TimeInterval? = nil,
        processingTime: TimeInterval? = nil,
        preparationTime: TimeInterval? = nil,
        error: String? = nil
    ) {
        self.success = success
        self.text = text
        self.words = words
        self.times = times
        self.duration = duration
        self.processingTime = processingTime
        self.preparationTime = preparationTime
        self.error = error
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(text, forKey: .text)
        try container.encode(words, forKey: .words)
        try container.encode(times, forKey: .times)
        try container.encode(duration, forKey: .duration)
        try container.encode(processingTime, forKey: .processingTime)
        try container.encode(preparationTime, forKey: .preparationTime)
        try container.encode(error, forKey: .error)
    }
}

private struct VozSmokeTestWordTime: Encodable {
    let startTime: TimeInterval
    let endTime: TimeInterval
}
#endif
