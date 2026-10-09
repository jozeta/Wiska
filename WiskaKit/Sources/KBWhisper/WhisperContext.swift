import Foundation
import whisper

/// A loaded Whisper model that transcribes one recording at a time.
public protocol WhisperModel: Sendable {
    func transcribe(_ samples: [Float], language: String) throws -> String
}

struct WhisperError: Error, CustomStringConvertible {
    let description: String
}

/// whisper.cpp's context: the GGML file loaded with Metal. `ModelRuntime.use` runs one call at
/// a time: whisper_full isn't safe in parallel on one context.
final class WhisperContext: WhisperModel, @unchecked Sendable {
    private let context: OpaquePointer

    static func load(from file: URL) throws -> any WhisperModel {
        whisper_log_set({ _, _, _ in }, nil)   // whisper.cpp logs every layer by default
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true
        guard let context = whisper_init_from_file_with_params(file.path, params) else {
            throw WhisperError(description: "the model file couldn't be loaded")
        }
        return WhisperContext(context: context)
    }

    private init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(_ samples: [Float], language: String) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_special = false
        params.print_timestamps = false
        params.translate = false
        params.no_timestamps = true
        params.suppress_blank = true
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))
        return try language.withCString { code in
            params.language = code
            let status = samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
            guard status == 0 else { throw WhisperError(description: "whisper_full returned \(status)") }
            return (0..<whisper_full_n_segments(context))
                .compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
