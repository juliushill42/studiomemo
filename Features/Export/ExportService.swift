import AVFoundation
import Foundation

// MARK: - Export configuration
struct ExportConfiguration: Sendable {
    var format: ExportFormat
    var normalizeAudio: Bool
    var includeMetadata: Bool
    var mixAllClips: Bool
    var bitRate: Int        // kbps
    var sampleRate: Double
    var channels: Int

    static let `default` = ExportConfiguration(
        format: .m4a,
        normalizeAudio: true,
        includeMetadata: true,
        mixAllClips: false,
        bitRate: 256,
        sampleRate: 44100,
        channels: 2
    )
}

// MARK: - Export result
struct ExportResult: Sendable {
    let url: URL
    let format: ExportFormat
    let sizeBytes: Int64
    let durationSeconds: TimeInterval

    var sizeDisplay: String {
        let mb = Double(sizeBytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(sizeBytes) / 1024)
    }
}

// MARK: - ExportService
@MainActor
final class ExportService: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isExporting: Bool = false

    private let fileStore: FileStore
    private let formatManager: AudioFormatManager

    init(fileStore: FileStore, formatManager: AudioFormatManager) {
        self.fileStore = fileStore
        self.formatManager = formatManager
    }

    // MARK: - Export single clip
    func exportClip(_ clip: ClipModel, config: ExportConfiguration) async throws -> ExportResult {
        isExporting = true
        progress = 0
        defer { isExporting = false; progress = 0 }

        let destURL = fileStore.exportDirectory(for: clip.sessionId)
            .appendingPathComponent("\(clip.id.uuidString).\(config.format.fileExtension)")

        try await convert(source: clip.fileURL, destination: destURL, config: config)
        progress = 1.0
        return try makeResult(url: destURL, format: config.format)
    }

    // MARK: - Export all clips mixed down
    func exportMixdown(session: SessionModel, clips: [ClipModel], config: ExportConfiguration) async throws -> ExportResult {
        guard !clips.isEmpty else { throw AppError.export(.exportFailed("No clips to mix")) }
        isExporting = true
        progress = 0
        defer { isExporting = false; progress = 0 }

        let destURL = fileStore.exportDirectory(for: session.id)
            .appendingPathComponent("Mixdown_\(session.id.uuidString).\(config.format.fileExtension)")

        // Build mixdown as CAF first (lossless intermediate), then convert
        let mixCAF = fileStore.tempURL(suffix: ".caf")
        defer { try? FileManager.default.removeItem(at: mixCAF) }

        try await mixClips(clips: clips, to: mixCAF, config: config)
        progress = 0.6

        if config.format == .caf {
            try FileManager.default.moveItem(at: mixCAF, to: destURL)
        } else {
            try await convert(source: mixCAF, destination: destURL, config: config)
        }
        progress = 1.0
        return try makeResult(url: destURL, format: config.format)
    }

    // MARK: - Mix engine
    private func mixClips(clips: [ClipModel], to outputURL: URL, config: ExportConfiguration) async throws {
        try await Task.detached(priority: .userInitiated) { [weak self] in
            let sr = config.sampleRate
            let ch = AVAudioChannelCount(config.channels)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: ch) else {
                throw AppError.audio(.conversionFailed("Mix format init failed"))
            }

            // Determine output length = max(endTime) across all clips
            var maxEnd: TimeInterval = 0
            for clip in clips {
                if let dur = self?.duration(of: clip.fileURL) { maxEnd = max(maxEnd, dur) }
            }
            let totalFrames = AVAudioFrameCount(maxEnd * sr)
            guard totalFrames > 0 else { throw AppError.export(.exportFailed("Zero-length mix")) }

            // Accumulate into a float buffer
            guard let mixBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
                throw AppError.audio(.bufferAllocationFailed)
            }
            mixBuffer.frameLength = totalFrames

            for (i, clip) in clips.enumerated() {
                guard let srcFile = try? AVAudioFile(forReading: clip.fileURL),
                      let srcBuf = AVAudioPCMBuffer(pcmFormat: srcFile.processingFormat,
                                                     frameCapacity: AVAudioFrameCount(srcFile.length)) else { continue }
                try srcFile.read(into: srcBuf)

                // Resample if needed (naive: skip if format matches — real impl uses AVAudioConverter)
                let frames = min(Int(srcBuf.frameLength), Int(totalFrames))
                for ch in 0..<Int(ch) {
                    let srcCh = min(ch, Int(srcBuf.format.channelCount) - 1)
                    guard let src = srcBuf.floatChannelData?[srcCh],
                          let dst = mixBuffer.floatChannelData?[ch] else { continue }
                    for f in 0..<frames {
                        dst[f] += src[f] * (clip.isMuted ? 0 : clip.gain)
                    }
                }
                await MainActor.run { self?.progress = 0.1 + 0.5 * Double(i + 1) / Double(clips.count) }
            }

            // Normalize if requested
            if config.normalizeAudio {
                self?.normalize(buffer: mixBuffer)
            }

            // Write
            guard let outFile = try? AVAudioFile(forWriting: outputURL,
                                                  settings: format.settings,
                                                  commonFormat: .pcmFormatFloat32,
                                                  interleaved: false) else {
                throw AppError.audio(.fileWriteFailed(outputURL))
            }
            try outFile.write(from: mixBuffer)
        }.value
    }

    // MARK: - Normalize
    private func normalize(buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let chCount = Int(buffer.format.channelCount)
        var peak: Float = 0
        for c in 0..<chCount {
            for f in 0..<count { peak = max(peak, abs(ch[c][f])) }
        }
        guard peak > 0, peak != 1 else { return }
        let gain = 0.98 / peak
        for c in 0..<chCount {
            for f in 0..<count { ch[c][f] *= gain }
        }
    }

    // MARK: - Format conversion
    private func convert(source: URL, destination: URL, config: ExportConfiguration) async throws {
        switch config.format {
        case .m4a:
            try await convertToM4A(source: source, destination: destination, bitRate: config.bitRate * 1000)
        case .wav:
            try await convertToWAV(source: source, destination: destination, sampleRate: config.sampleRate)
        case .caf:
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func convertToM4A(source: URL, destination: URL, bitRate: Int) async throws {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AppError.export(.sessionCreationFailed)
        }
        session.outputURL = destination
        session.outputFileType = .m4a
        await session.export()
        if let error = session.error {
            throw AppError.export(.exportFailed(error.localizedDescription))
        }
    }

    private func convertToWAV(source: URL, destination: URL, sampleRate: Double) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let srcFile = try? AVAudioFile(forReading: source) else {
                throw AppError.audio(.fileReadFailed(source))
            }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            guard let dstFile = try? AVAudioFile(forWriting: destination,
                                                  settings: settings,
                                                  commonFormat: .pcmFormatInt32,
                                                  interleaved: true) else {
                throw AppError.audio(.fileWriteFailed(destination))
            }
            let capacity = AVAudioFrameCount(4096)
            guard let buf = AVAudioPCMBuffer(pcmFormat: srcFile.processingFormat, frameCapacity: capacity) else {
                throw AppError.audio(.bufferAllocationFailed)
            }
            while srcFile.framePosition < srcFile.length {
                try srcFile.read(into: buf)
                try dstFile.write(from: buf)
            }
        }.value
    }

    // MARK: - Helpers
    private func duration(of url: URL) -> TimeInterval? {
        formatManager.duration(of: url)
    }

    private func makeResult(url: URL, format: ExportFormat) throws -> ExportResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.export(.invalidDestination(url))
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs[.size] as? Int64 ?? 0
        let dur = formatManager.duration(of: url) ?? 0
        AppLogger.info("Export complete → \(url.lastPathComponent) [\(size) bytes]", category: .persistence)
        return ExportResult(url: url, format: format, sizeBytes: size, durationSeconds: dur)
    }
}
