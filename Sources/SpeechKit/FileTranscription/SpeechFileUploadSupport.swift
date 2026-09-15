import AVFoundation
import Foundation

enum SpeechMultipartFormPart: Sendable {
    case text(name: String, value: String)
    case json(name: String, data: Data)
    case file(name: String, fileURL: URL, fileData: Data, contentType: String)
}

enum SpeechFileUploadSupport {
    static func validateFileExtension(
        _ fileURL: URL,
        allowedExtensions: Set<String>,
        provider: SpeechFileTranscriptionProvider
    ) throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            throw SpeechError.providerFailure(
                provider: provider,
                reason: "Unsupported file extension: \(fileExtension.isEmpty ? "(none)" : fileExtension)."
            )
        }
    }

    static func validateFileSize(
        _ fileURL: URL,
        maxUploadBytes: Int64,
        provider: SpeechFileTranscriptionProvider
    ) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.int64Value > maxUploadBytes {
                throw SpeechError.uploadFailed(provider: provider, reason: "Audio file exceeds \(maxUploadBytes) byte limit.")
            }
        } catch let error as SpeechError {
            throw error
        } catch {
            throw SpeechError.providerFailure(provider: provider, reason: error.localizedDescription)
        }
    }

    static func validateFileDuration(
        _ fileURL: URL,
        maxDuration: TimeInterval,
        provider: SpeechFileTranscriptionProvider
    ) async throws {
        let asset = AVURLAsset(url: fileURL)
        guard let duration = try? await asset.load(.duration) else {
            return
        }

        let seconds = duration.seconds
        if seconds.isFinite, seconds > maxDuration {
            throw SpeechError.uploadFailed(
                provider: provider,
                reason: "Audio exceeds the \(Int(maxDuration)) second limit."
            )
        }
    }

    /// Validates the duration of a headerless PCM file from its byte count.
    ///
    /// AVFoundation cannot read a duration from raw PCM, so
    /// ``validateFileDuration(_:maxDuration:provider:)`` silently accepts those
    /// files. Raw PCM is a fixed bit rate, so the duration is exactly
    /// `byteCount / (sampleRate * bytesPerFrame)` for 16-bit mono audio.
    static func validateRawPCMDuration(
        fileURL: URL,
        sampleRate: Int,
        maxDuration: TimeInterval,
        provider: SpeechFileTranscriptionProvider
    ) throws {
        guard sampleRate > 0 else { return }

        let byteCount: Int64
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard let fileSize = attributes[.size] as? NSNumber else { return }
            byteCount = fileSize.int64Value
        } catch {
            throw SpeechError.providerFailure(provider: provider, reason: error.localizedDescription)
        }

        // 16-bit mono little-endian PCM: two bytes per frame, one frame per sample.
        let bytesPerSecond = Double(sampleRate) * 2
        let seconds = Double(byteCount) / bytesPerSecond
        if seconds > maxDuration {
            throw SpeechError.uploadFailed(
                provider: provider,
                reason: "Audio exceeds the \(Int(maxDuration)) second limit."
            )
        }
    }

    static func makeMultipartBody(boundary: String, parts: [SpeechMultipartFormPart]) -> Data {
        var body = Data()

        for part in parts {
            body.append("--\(boundary)\r\n")

            switch part {
            case .text(let name, let value):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                body.append("\(value)\r\n")

            case .json(let name, let data):
                body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n")
                body.append("Content-Type: application/json\r\n\r\n")
                body.append(data)
                body.append("\r\n")

            case .file(let name, let fileURL, let fileData, let contentType):
                let fileName = fileURL.lastPathComponent.isEmpty ? "audio" : fileURL.lastPathComponent
                body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
                body.append("Content-Type: \(contentType)\r\n\r\n")
                body.append(fileData)
                body.append("\r\n")
            }
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    static func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "wav":
            return "audio/wav"
        case "mp3", "mpeg", "mpga":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "mp4":
            return "video/mp4"
        case "aiff", "aif":
            return "audio/aiff"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        case "opus":
            return "audio/opus"
        case "webm":
            return "audio/webm"
        case "mkv":
            return "video/x-matroska"
        default:
            return "application/octet-stream"
        }
    }

    static func readFileData(from fileURL: URL) throws -> Data {
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            throw ElevenLabsError.fileReadFailed
        }
    }

    /// Validates a file against the ElevenLabs upload limits.
    ///
    /// The size limit is always enforced. The duration limit is only enforced
    /// when AVFoundation can read a duration: files whose metadata cannot be
    /// read (raw PCM, containers AVFoundation does not parse) are accepted, in
    /// line with ``validateFileDuration(_:maxDuration:provider:)``.
    static func validateFileForUpload(
        _ fileURL: URL,
        maxUploadBytes: Int64? = nil,
        maxUploadDuration: TimeInterval? = nil
    ) async throws {
        if let maxUploadBytes {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let fileSize = attributes[.size] as? NSNumber,
                   fileSize.int64Value > maxUploadBytes {
                    throw ElevenLabsError.fileTooLarge(maxUploadBytes)
                }
            } catch let error as ElevenLabsError {
                throw error
            } catch {
                throw ElevenLabsError.fileReadFailed
            }
        }

        if let maxUploadDuration {
            let asset = AVURLAsset(url: fileURL)
            // An unreadable duration is tolerated rather than fatal; the limit
            // is only enforced when AVFoundation reports a finite duration.
            guard let duration = try? await asset.load(.duration) else {
                return
            }

            let seconds = duration.seconds
            if seconds.isFinite, seconds > maxUploadDuration {
                throw ElevenLabsError.audioTooLong(maxUploadDuration)
            }
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }
}
