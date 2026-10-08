import Core
import Speech

enum AppleSpeechAssets {
    private static let log = Log.logger("SpeechToText")

    /// Ensures the on-device model for `module` is installed, downloading it if needed.
    static func ensureInstalled(_ module: SpeechTranscriber, locale: Locale) async throws {
        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            return
        case .unsupported:
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        case .supported, .downloading:
            log.info("installing speech assets for \(locale.identifier, privacy: .public)")
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await request.downloadAndInstall()
            }
        @unknown default:
            return
        }
    }
}
