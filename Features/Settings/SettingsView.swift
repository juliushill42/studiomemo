import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var showRecoveryConfirm: Bool = false
    @State private var diskUsageMB: Double = 0
    @State private var sessionCount: Int = 0
    @AppStorage("hapticFeedback") private var hapticFeedback: Bool = true
    @AppStorage("autoTranscribeOnStop") private var autoTranscribe: Bool = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake: Bool = true

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Audio
                Section {
                    NavigationLink(destination: AudioSettingsView()) {
                        Label("Audio Engine", systemImage: "speaker.wave.3.fill")
                    }
                } header: {
                    Text("Hardware")
                }

                // MARK: - Behavior
                Section {
                    Toggle(isOn: $hapticFeedback) {
                        Label("Haptic Feedback", systemImage: "hand.tap.fill")
                    }
                    .tint(AppTheme.Colors.accent)

                    Toggle(isOn: $autoTranscribe) {
                        Label("Auto-Transcribe on Stop", systemImage: "text.bubble.fill")
                    }
                    .tint(AppTheme.Colors.accent)

                    Toggle(isOn: $keepScreenAwake) {
                        Label("Keep Screen On While Recording", systemImage: "sun.max.fill")
                    }
                    .tint(AppTheme.Colors.accent)
                    .onChange(of: keepScreenAwake) { _, value in
                        UIApplication.shared.isIdleTimerDisabled = value
                    }
                } header: {
                    Text("Behavior")
                }

                // MARK: - Pro
                Section {
                    NavigationLink(destination: PurchaseView()) {
                        Label("Upgrade to Pro", systemImage: "bolt.fill")
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                } header: {
                    Text("Pro Features")
                }

                // MARK: - Storage
                Section {
                    HStack {
                        Label("Sessions", systemImage: "folder.fill")
                        Spacer()
                        Text("\(sessionCount)")
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                    HStack {
                        Label("Disk Usage", systemImage: "internaldrive.fill")
                        Spacer()
                        Text(String(format: "%.1f MB", diskUsageMB))
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                    Button(role: .destructive) {
                        showRecoveryConfirm = true
                    } label: {
                        Label("Run Recovery Sweep", systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text("Storage")
                }

                // MARK: - About
                Section {
                    HStack {
                        Label("Version", systemImage: "info.circle.fill")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                    HStack {
                        Label("Build", systemImage: "hammer.fill")
                        Spacer()
                        Text(buildNumber)
                            .foregroundColor(AppTheme.Colors.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .confirmationDialog("Run Recovery Sweep?",
                                isPresented: $showRecoveryConfirm,
                                titleVisibility: .visible) {
                Button("Run Sweep", role: .destructive) {
                    Task { await env.recoveryManager.sweepOrphanedSessions() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes orphaned audio files not linked to any clip. This cannot be undone.")
            }
        }
        .task { await loadStorageInfo() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenAwake }
    }

    // MARK: - Storage info
    private func loadStorageInfo() async {
        await env.projectRepository.loadAllSessions()
        let sessions = env.projectRepository.sessions
        sessionCount = sessions.count
        let totalBytes = sessions.reduce(Int64(0)) { acc, s in
            acc + env.fileStore.diskUsage(for: s.id)
        }
        diskUsageMB = Double(totalBytes) / 1_048_576
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
