import SwiftUI
import AVFoundation

// MARK: - StemMixerEngine
/// Manages simultaneous multi-track playback of separated stems via AVAudioEngine.
@MainActor
final class StemMixerEngine: ObservableObject {
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var stemStates: [StemJobModel.StemTrack: StemTrackState] = [:]

    private let engine = AVAudioEngine()
    private var players: [StemJobModel.StemTrack: AVAudioPlayerNode] = [:]
    private var mixers: [StemJobModel.StemTrack: AVAudioMixerNode] = [:]
    private var files: [StemJobModel.StemTrack: AVAudioFile] = [:]
    private var startHostTime: AVAudioTime?
    private var timer: Task<Void, Never>?

    struct StemTrackState {
        var volume: Float = 1.0
        var isMuted: Bool = false
    }

    // MARK: - Load job
    func load(job: StemJobModel) {
        teardown()
        for (track, url) in job.outputURLs {
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            engine.attach(player)
            engine.attach(mixer)
            engine.connect(player, to: mixer, format: file.processingFormat)
            engine.connect(mixer, to: engine.mainMixerNode, format: nil)
            players[track] = player
            mixers[track] = mixer
            files[track] = file
            stemStates[track] = StemTrackState()
        }
        duration = job.outputURLs.values.compactMap { url in
            let a = AVURLAsset(url: url)
            let d = a.duration
            return d.isValid ? CMTimeGetSeconds(d) : nil
        }.max() ?? 0
    }

    // MARK: - Transport
    func play() {
        guard !players.isEmpty else { return }
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            for (track, player) in players {
                guard let file = files[track] else { continue }
                file.framePosition = 0
                player.scheduleFile(file, at: nil, completionHandler: nil)
            }
            let startTime = AVAudioTime(hostTime: mach_absolute_time() + UInt64(0.1 * Double(NSEC_PER_SEC)))
            for (_, player) in players { player.play(at: startTime) }
            startHostTime = startTime
            isPlaying = true
            startTimer()
        } catch {
            AppLogger.error("StemMixer play error: \(error)", category: .audio)
        }
    }

    func pause() {
        for (_, player) in players { player.pause() }
        isPlaying = false
        stopTimer()
    }

    func stop() {
        for (_, player) in players { player.stop() }
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying
        stop()
        let sr = files.values.first?.processingFormat.sampleRate ?? 44100
        let frame = AVAudioFramePosition(time * sr)
        for (track, player) in players {
            guard let file = files[track] else { continue }
            let remaining = AVAudioFrameCount(max(0, file.length - frame))
            guard remaining > 0 else { continue }
            file.framePosition = frame
            player.scheduleSegment(file, startingFrame: frame, frameCount: remaining, at: nil)
        }
        currentTime = time
        if wasPlaying { play() }
    }

    func skip(by delta: TimeInterval) {
        seek(to: max(0, min(duration, currentTime + delta)))
    }

    // MARK: - Per-stem controls
    func setVolume(_ volume: Float, for track: StemJobModel.StemTrack) {
        stemStates[track]?.volume = volume
        applyGain(for: track)
    }

    func toggleMute(for track: StemJobModel.StemTrack) {
        stemStates[track]?.isMuted.toggle()
        applyGain(for: track)
    }

    private func applyGain(for track: StemJobModel.StemTrack) {
        guard let state = stemStates[track], let mixer = mixers[track] else { return }
        mixer.outputVolume = state.isMuted ? 0 : state.volume
    }

    // MARK: - Timer
    private func startTimer() {
        timer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                guard let self, self.isPlaying,
                      let player = self.players.values.first,
                      let nodeTime = player.lastRenderTime,
                      let playerTime = player.playerTime(forNodeTime: nodeTime) else { continue }
                self.currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                if self.currentTime >= self.duration { self.stop() }
            }
        }
    }

    private func stopTimer() { timer?.cancel(); timer = nil }

    private func teardown() {
        stop()
        for (_, player) in players { engine.detach(player) }
        for (_, mixer) in mixers { engine.detach(mixer) }
        players.removeAll(); mixers.removeAll(); files.removeAll(); stemStates.removeAll()
        if engine.isRunning { engine.stop() }
    }

    deinit { teardown() }
}

// MARK: - StemPlayerView
struct StemPlayerView: View {
    let job: StemJobModel
    let vm: StemViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mixer = StemMixerEngine()

    private var sortedTracks: [StemJobModel.StemTrack] {
        job.outputURLs.keys.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    transportCard
                    stemConsole
                }
                .padding(AppTheme.Spacing.md)
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle(job.sourceURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { mixer.stop(); dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(sortedTracks) { track in
                            if let url = job.outputURLs[track] {
                                ShareLink(item: url) {
                                    Label("Share \(track.displayName)", systemImage: track.systemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                }
            }
            .onAppear { mixer.load(job: job) }
            .onDisappear { mixer.stop() }
        }
    }

    // MARK: - Transport
    private var transportCard: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Scrubber
            VStack(spacing: 4) {
                Slider(
                    value: Binding(get: { mixer.currentTime },
                                   set: { mixer.seek(to: $0) }),
                    in: 0...max(1, mixer.duration)
                )
                .tint(AppTheme.Colors.accent)
                HStack {
                    Text(mixer.currentTime.mmss)
                    Spacer()
                    Text(mixer.duration.mmss)
                }
                .font(AppTheme.Fonts.mono)
                .foregroundColor(AppTheme.Colors.secondary)
            }

            // Transport buttons
            HStack(spacing: AppTheme.Spacing.xl) {
                Button { mixer.skip(by: -10) } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundColor(AppTheme.Colors.primary)
                }

                Button {
                    mixer.isPlaying ? mixer.pause() : mixer.play()
                } label: {
                    Image(systemName: mixer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(AppTheme.Colors.accent)
                }
                .animation(AppTheme.Animation.fast, value: mixer.isPlaying)

                Button { mixer.skip(by: 10) } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                        .foregroundColor(AppTheme.Colors.primary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Stem console
    private var stemConsole: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Stem Console", systemImage: "slider.vertical.3")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.Colors.primary)

            ForEach(sortedTracks) { track in
                if let state = mixer.stemStates[track] {
                    StemChannelStrip(
                        track: track,
                        state: state,
                        onVolumeChange: { mixer.setVolume($0, for: track) },
                        onMuteToggle: { mixer.toggleMute(for: track) }
                    )
                }
            }
        }
    }
}

// MARK: - StemChannelStrip
private struct StemChannelStrip: View {
    let track: StemJobModel.StemTrack
    let state: StemMixerEngine.StemTrackState
    let onVolumeChange: (Float) -> Void
    let onMuteToggle: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack {
                Image(systemName: track.systemImage)
                    .foregroundColor(state.isMuted ? AppTheme.Colors.secondary : AppTheme.Colors.accent)
                    .frame(width: 20)

                Text(track.displayName)
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(state.isMuted ? AppTheme.Colors.secondary : AppTheme.Colors.primary)

                Spacer()

                Text("\(Int(state.volume * 100))%")
                    .font(AppTheme.Fonts.mono)
                    .foregroundColor(AppTheme.Colors.secondary)
                    .frame(width: 40, alignment: .trailing)

                Button(action: onMuteToggle) {
                    Image(systemName: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(state.isMuted ? .red : AppTheme.Colors.secondary)
                }
                .buttonStyle(.plain)

                if let url = [track].compactMap({ _ in nil as URL? }).first {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                }
            }

            Slider(
                value: Binding(get: { Double(state.volume) },
                               set: { onVolumeChange(Float($0)) }),
                in: 0...1
            )
            .tint(state.isMuted ? AppTheme.Colors.secondary : AppTheme.Colors.accent)
            .disabled(state.isMuted)
        }
        .padding(AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
        .cornerRadius(AppTheme.Radius.sm)
        .animation(AppTheme.Animation.fast, value: state.isMuted)
    }
}

// MARK: - StemJobModel.StemTrack Identifiable
extension StemJobModel.StemTrack: Identifiable {
    public var id: String { rawValue }
}
