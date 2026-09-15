@preconcurrency import AVFoundation
import CoreMedia
import Foundation

#if !os(watchOS)
import Speech

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
enum AppleSpeechSupport {
    static func makeFileTranscriber(
        configuration: AppleSpeechConfiguration,
        options: AppleSpeechFileTranscriptionOptions? = nil
    ) async throws -> (transcriber: SpeechTranscriber, locale: Locale, preparesAssetsAutomatically: Bool) {
        let locale = options?.locale ?? configuration.locale
        let resolvedLocale = try await resolvedLocale(for: locale)
        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .timeIndexedTranscriptionWithAlternatives)
        let preparesAssetsAutomatically = options?.preparesAssetsAutomatically ?? configuration.preparesAssetsAutomatically
        try await prepareAssets(for: [transcriber], locale: resolvedLocale, preparesAssetsAutomatically: preparesAssetsAutomatically)
        return (transcriber, resolvedLocale, preparesAssetsAutomatically)
    }

    static func makeRealtimeTranscriber(
        configuration: AppleSpeechConfiguration
    ) async throws -> (transcriber: SpeechTranscriber, locale: Locale) {
        let resolvedLocale = try await resolvedLocale(for: configuration.locale)
        let transcriber = SpeechTranscriber(locale: resolvedLocale, preset: .timeIndexedProgressiveTranscription)
        try await prepareAssets(
            for: [transcriber],
            locale: resolvedLocale,
            preparesAssetsAutomatically: configuration.preparesAssetsAutomatically
        )
        return (transcriber, resolvedLocale)
    }

    static func analyzerOptions(from retention: AppleSpeechModelRetention) -> SpeechAnalyzer.Options {
        SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: speechRetention(from: retention))
    }

    static func analysisContext(from configuration: AppleSpeechConfiguration) -> AnalysisContext {
        let context = AnalysisContext()
        if !configuration.contextualStrings.isEmpty {
            context.contextualStrings[.general] = configuration.contextualStrings
        }
        return context
    }

    static func makeEntry(
        from result: SpeechTranscriber.Result,
        locale: Locale
    ) -> SpeechTranscriptEntry? {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let start = seconds(from: result.range.start)
        let duration = seconds(from: result.range.duration)
        return SpeechTranscriptEntry(
            provider: .apple,
            sourceID: sourceID(for: result.range),
            text: text,
            start: start,
            duration: duration,
            isFinal: result.isFinal,
            isUtteranceFinal: result.isFinal,
            speaker: locale.identifier,
            words: words(from: result.text)
        )
    }

    static func sourceID(for range: CMTimeRange) -> String {
        let start = range.start
        let duration = range.duration
        return "apple:\(start.value)/\(start.timescale):\(duration.value)/\(duration.timescale)"
    }

    static func sortsBefore(_ lhs: SpeechTranscriptEntry, _ rhs: SpeechTranscriptEntry) -> Bool {
        switch (lhs.start, rhs.start) {
        case (let lhsStart?, let rhsStart?) where lhsStart != rhsStart:
            return lhsStart < rhsStart
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.timestamp < rhs.timestamp
        }
    }

    private static func resolvedLocale(for locale: Locale) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw SpeechError.appleSpeechUnavailable
        }
        guard let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechError.appleSpeechUnsupportedLocale(localeIdentifier: locale.identifier)
        }
        return resolvedLocale
    }

    private static func prepareAssets(
        for modules: [any SpeechModule],
        locale: Locale,
        preparesAssetsAutomatically: Bool
    ) async throws {
        let status = await AssetInventory.status(forModules: modules)
        switch status {
        case .installed:
            return
        case .unsupported:
            throw SpeechError.appleSpeechUnsupportedLocale(localeIdentifier: locale.identifier)
        case .supported, .downloading:
            guard preparesAssetsAutomatically else {
                throw SpeechError.appleSpeechAssetsUnavailable(localeIdentifier: locale.identifier)
            }
            guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules) else {
                return
            }
            try await request.downloadAndInstall()
        @unknown default:
            throw SpeechError.appleSpeechAssetsUnavailable(localeIdentifier: locale.identifier)
        }
    }

    private static func speechRetention(
        from retention: AppleSpeechModelRetention
    ) -> SpeechAnalyzer.Options.ModelRetention {
        switch retention {
        case .whileInUse:
            return .whileInUse
        case .lingering:
            return .lingering
        case .processLifetime:
            return .processLifetime
        }
    }

    private static func words(from attributedText: AttributedString) -> [SpeechTranscriptWord] {
        attributedText.runs.compactMap { run in
            let wordText = String(attributedText[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wordText.isEmpty else { return nil }

            let timeRange = run.audioTimeRange
            return SpeechTranscriptWord(
                text: wordText,
                start: timeRange.flatMap { seconds(from: $0.start) },
                end: timeRange.flatMap { seconds(from: CMTimeRangeGetEnd($0)) },
                confidence: run.transcriptionConfidence
            )
        }
    }

    private static func seconds(from time: CMTime) -> Double? {
        guard time.isValid, time.isNumeric else { return nil }
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite else { return nil }
        return seconds
    }
}
#endif
