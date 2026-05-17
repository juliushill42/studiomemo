import SwiftUI
import AVFoundation
import Combine

struct AudioSettingsView: View {
    @EnvironmentObject private var env: AppEnvironment

    // MARK: - State
    @State private var activeInputName: String = "—"
    @State private var inputLatency: String = "—"
    @State private var outputLatency: String = "—"
    @State private var hardwareSampleRate: String = "—"
    @State private var selectedBitDepth: BitDepth = .twentyFour
    @State private var selectedChannels: ChannelMode = .stereo
    @State private var enableNoiseGate: Bool = false
    @State private var noiseGateThreshold: Double = -40
    @State private var enableHighPassFilter: Bool = false
    @State private var inputGain: Double = 1.0
    @State private var routeChangeCancellable: AnyCancellable?

    enum BitDepth: Int, CaseIterable, Identifiable {
        case sixteen = 16, twentyFour = 24, thirtyTwo = 32
        var id: Int { rawValue }
        var display: String { "\(rawValue)-bit" }
    }

    enum ChannelMode: String, CaseIterable, Identifiable {
        case mono = "Mono", stereo = "Stereo"
        var id: String { rawValue }
        var channels: Int { self == .mono ? 1 : 2 }
    }

    var body: some View {
        List {
            // MARK: Active hardware
            Section {
                InfoRow(label: "Input Source",    value: activeInputName)
                InfoRow(label: "Sample Rate",     value: hardwareSampleRate)
                InfoRow(label: "Input Latency",   value: inputLatency)
                InfoRow(label: "Output Latency",  value: outputLatency)
                InfoRow(label: "Available Inputs", value: "\(env.audioSession.availableInputs.count)")
            } header: {
                Text("Active Hardware")
            }

            // MARK: Input source picker
            Section {
                ForEach(env.audioSession.availableInputs, id: \.uid) { port in
                    Button {
                        try? env.audioRouter.select(source: port)
                        refreshRouteData()
                    } label: {
                        HStack {
                            Image(systemName: portIcon(port.portType))
                                .foregroundColor(AppTheme.Colors.accent)
                                .frame(width: 24)
                            Text(port.portName)
                                .foregroundColor(AppTheme.Colors.primary)
                            Spacer()
                            if env.audioSession.currentInput?.uid == port.uid {
                                Image(systemName: "checkmark")
                                    .foregroundColor(AppTheme.Colors.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("Reset to Default") {
                    try? env.audioRouter.selectDefault()
                    refreshRouteData()
                }
                .foregroundColor(AppTheme.Colors.secondary)
            } header: {
                Text("Input Source")
            }

            // MARK: Recording quality
            Section {
                Picker("Bit Depth", selection: $selectedBitDepth) {
                    ForEach(BitDepth.allCases) { d in Text(d.display).tag(d) }
                }
                .tint(AppTheme.Colors.accent)

                Picker("Channels", selection: $selectedChannels) {
                    ForEach(ChannelMode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .tint(AppTheme.Colors.accent)
            } header: {
                Text("Recording Quality")
            } footer: {
                Text("Higher bit depth reduces quantization noise. Stereo uses 2× storage.")
                    .foregroundColor(AppTheme.Colors.secondary)
            }

            // MARK: Input processing
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Noise Gate", isOn: $enableNoiseGate)
                        .tint(AppTheme.Colors.accent)
                    if enableNoiseGate {
                        HStack {
                            Text("Threshold: \(Int(noiseGateThreshold)) dBFS")
                                .font(AppTheme.Fonts.caption)
                                .foregroundColor(AppTheme.Colors.secondary)
                            Spacer()
                        }
                        Slider(value: $noiseGateThreshold, in: -80...(-10))
                            .tint(AppTheme.Colors.accent)
                    }
                }

                Toggle("High-Pass Filter (80 Hz)", isOn: $enableHighPassFilter)
                    .tint(AppTheme.Colors.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Input Gain: \(String(format: "%.1f", inputGain))×")
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.Colors.secondary)
                    Slider(value: $inputGain, in: 0.5...2.0)
                        .tint(AppTheme.Colors.accent)
                }
            } header: {
                Text("Input Processing")
            }

            // MARK: Diagnostics
            Section {
                Button("Refresh Hardware Data") {
                    refreshRouteData()
                    AppLogger.info("AudioSettings: manual hardware refresh", category: .audio)
                }
                .foregroundColor(AppTheme.Colors.accent)

                Button("Re-configure Audio Session") {
                    do {
                        try env.audioSession.configure()
                        refreshRouteData()
                    } catch {
                        AppLogger.error("AudioSettings: session reconfigure failed: \(error)", category: .audio)
                    }
                }
                .foregroundColor(AppTheme.Colors.accent)
            } header: {
                Text("Diagnostics")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Audio Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshRouteData()
            observeRouteChanges()
        }
        .onDisappear { routeChangeCancellable?.cancel() }
    }

    // MARK: - Route data
    private func refreshRouteData() {
        let session = AVAudioSession.sharedInstance()
        activeInputName = session.currentRoute.inputs.first?.portName ?? "None"
        inputLatency    = String(format: "%.1f ms", session.inputLatency * 1000)
        outputLatency   = String(format: "%.1f ms", session.outputLatency * 1000)
        hardwareSampleRate = String(format: "%.0f Hz", session.sampleRate)
    }

    private func observeRouteChanges() {
        routeChangeCancellable = env.audioSession.routeChangePublisher
            .receive(on: DispatchQueue.main)
            .sink { [self] _ in refreshRouteData() }
    }

    private func portIcon(_ type: AVAudioSession.Port) -> String {
        switch type {
        case .builtInMic:           return "mic.fill"
        case .headsetMic:           return "headphones"
        case .bluetoothHFP,
             .bluetoothA2DP:        return "dot.radiowaves.left.and.right"
        case .usbAudio:             return "cable.connector"
        case .lineIn:               return "arrow.down.circle"
        default:                    return "mic"
        }
    }
}

// MARK: - InfoRow
private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(AppTheme.Colors.primary)
            Spacer()
            Text(value).foregroundColor(AppTheme.Colors.secondary)
        }
    }
}
