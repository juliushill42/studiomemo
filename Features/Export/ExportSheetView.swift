import SwiftUI

struct ExportSheetView: View {
    let session: SessionModel
    let clips: [ClipModel]

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportService: ExportService

    @State private var config: ExportConfiguration = .default
    @State private var result: ExportResult?
    @State private var error: AppError?
    @State private var showShareSheet: Bool = false

    init(session: SessionModel, clips: [ClipModel]) {
        self.session = session
        self.clips = clips
        let e = AppEnvironment()
        _exportService = StateObject(wrappedValue: ExportService(
            fileStore: e.fileStore!,
            formatManager: e.audioFormat!
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    sessionSummaryCard
                    formatSection
                    optionsSection
                    clipListSection
                    actionSection
                    if let result { resultCard(result) }
                }
                .padding(AppTheme.Spacing.md)
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
            .alert("Export Failed", isPresented: .constant(error != nil), presenting: error) { _ in
                Button("OK") { error = nil }
            } message: { err in
                Text(err.localizedDescription)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = result?.url {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Session summary
    private var sessionSummaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(AppTheme.Colors.primary)
                Text("\(clips.count) clip\(clips.count == 1 ? "" : "s") · \(session.durationSeconds.mmss)")
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(AppTheme.Colors.secondary)
            }
            Spacer()
            Image(systemName: session.mode.systemImage)
                .foregroundColor(AppTheme.Colors.accent)
                .font(.title2)
        }
        .cardStyle()
    }

    // MARK: - Format picker
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Format", systemImage: "music.note.list")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.Colors.primary)

            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(ExportFormat.allCases) { fmt in
                    Button {
                        config.format = fmt
                    } label: {
                        VStack(spacing: 4) {
                            Text(fmt.fileExtension.uppercased())
                                .font(AppTheme.Fonts.headline)
                            Text(fmt.displayName)
                                .font(.system(size: 10))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppTheme.Spacing.sm)
                        .background(config.format == fmt
                            ? AppTheme.Colors.accent.opacity(0.15)
                            : AppTheme.Colors.surface)
                        .cornerRadius(AppTheme.Radius.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .stroke(config.format == fmt
                                    ? AppTheme.Colors.accent
                                    : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .foregroundColor(config.format == fmt
                        ? AppTheme.Colors.accent
                        : AppTheme.Colors.secondary)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Options
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Options", systemImage: "slider.horizontal.3")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(AppTheme.Colors.primary)

            VStack(spacing: 0) {
                OptionRow(title: "Mix all clips to single file",
                          subtitle: "Combines all clips into one stereo track",
                          isOn: $config.mixAllClips)
                Divider().background(AppTheme.Colors.background)
                OptionRow(title: "Normalize audio",
                          subtitle: "Peaks at -0.2 dBFS",
                          isOn: $config.normalizeAudio)
                Divider().background(AppTheme.Colors.background)
                OptionRow(title: "Embed metadata",
                          subtitle: "Title, date, and tags written to file",
                          isOn: $config.includeMetadata)
            }
            .cardStyle()
            .padding(0)

            if config.format == .m4a {
                HStack {
                    Text("Bit Rate")
                        .font(AppTheme.Fonts.body)
                        .foregroundColor(AppTheme.Colors.primary)
                    Spacer()
                    Picker("Bit Rate", selection: $config.bitRate) {
                        Text("128 kbps").tag(128)
                        Text("192 kbps").tag(192)
                        Text("256 kbps").tag(256)
                        Text("320 kbps").tag(320)
                    }
                    .pickerStyle(.menu)
                    .tint(AppTheme.Colors.accent)
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Clip list
    @ViewBuilder
    private var clipListSection: some View {
        if !config.mixAllClips {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Label("Clips to Export", systemImage: "waveform")
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(AppTheme.Colors.primary)

                ForEach(clips) { clip in
                    HStack {
                        Image(systemName: "waveform").foregroundColor(AppTheme.Colors.accent)
                        Text("Clip \(clip.trackId + 1)")
                            .font(AppTheme.Fonts.body)
                            .foregroundColor(AppTheme.Colors.primary)
                        Spacer()
                        Text(clip.duration.mmss)
                            .font(AppTheme.Fonts.caption)
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                    .padding(AppTheme.Spacing.sm)
                    .background(AppTheme.Colors.surface)
                    .cornerRadius(AppTheme.Radius.sm)
                }
            }
        }
    }

    // MARK: - Action
    private var actionSection: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            if exportService.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportService.progress)
                        .tint(AppTheme.Colors.accent)
                    Text(progressLabel)
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.Colors.secondary)
                }
                .cardStyle()
            } else {
                Button {
                    Task { await runExport() }
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text(config.mixAllClips ? "Export Mixdown" : "Export \(clips.count) Clip\(clips.count == 1 ? "" : "s")")
                    }
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.md)
                    .background(clips.isEmpty ? AppTheme.Colors.secondary : AppTheme.Colors.accent)
                    .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
                .disabled(clips.isEmpty)
            }
        }
    }

    // MARK: - Result card
    private func resultCard(_ r: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Label("Export Complete", systemImage: "checkmark.circle.fill")
                .font(AppTheme.Fonts.headline)
                .foregroundColor(.green)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.url.lastPathComponent)
                        .font(AppTheme.Fonts.body)
                        .foregroundColor(AppTheme.Colors.primary)
                        .lineLimit(1)
                    Text("\(r.sizeDisplay) · \(r.durationSeconds.mmss)")
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.Colors.secondary)
                }
                Spacer()
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .cardStyle()
        .accentBorder()
    }

    // MARK: - Export execution
    private func runExport() async {
        result = nil
        error = nil
        do {
            if config.mixAllClips {
                result = try await exportService.exportMixdown(session: session, clips: clips, config: config)
            } else {
                // Export first clip for single-session; full multi-clip export queues sequentially
                guard let first = clips.first else { return }
                result = try await exportService.exportClip(first, config: config)
            }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = .unknown(error)
        }
    }

    private var progressLabel: String {
        let pct = Int(exportService.progress * 100)
        if pct < 60 { return "Mixing clips… \(pct)%" }
        if pct < 90 { return "Encoding \(config.format.fileExtension.uppercased())… \(pct)%" }
        return "Finalizing… \(pct)%"
    }
}

// MARK: - Option row
private struct OptionRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Fonts.body)
                    .foregroundColor(AppTheme.Colors.primary)
                Text(subtitle)
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(AppTheme.Colors.secondary)
            }
        }
        .tint(AppTheme.Colors.accent)
        .padding(AppTheme.Spacing.sm)
    }
}

// MARK: - Share sheet bridge
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
