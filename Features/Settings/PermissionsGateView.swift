import SwiftUI

struct PermissionsGateView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var isRequesting: Bool = false

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: AppTheme.Spacing.xl) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(AppTheme.Colors.accent)

                VStack(spacing: AppTheme.Spacing.sm) {
                    Text("Permissions Required")
                        .font(AppTheme.Fonts.title)
                        .foregroundColor(AppTheme.Colors.primary)
                    Text("StudioMemo needs microphone and speech recognition access to record and transcribe audio.")
                        .font(AppTheme.Fonts.body)
                        .foregroundColor(AppTheme.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                }

                VStack(spacing: AppTheme.Spacing.sm) {
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Microphone",
                        description: "Required to capture audio recordings.",
                        granted: Permissions.microphoneGranted
                    )
                    PermissionRow(
                        icon: "text.bubble.fill",
                        title: "Speech Recognition",
                        description: "Required for automatic transcription.",
                        granted: Permissions.speechGranted
                    )
                }
                .padding(.horizontal, AppTheme.Spacing.md)

                Button {
                    isRequesting = true
                    Task {
                        await env.retryPermissions()
                        isRequesting = false
                    }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white) }
                        Text(isRequesting ? "Requesting…" : "Grant Access")
                    }
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(AppTheme.Spacing.md)
                    .background(AppTheme.Colors.accent)
                    .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
                .disabled(isRequesting)
                .padding(.horizontal, AppTheme.Spacing.md)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(AppTheme.Fonts.caption)
                .foregroundColor(AppTheme.Colors.secondary)
            }
            .padding(AppTheme.Spacing.lg)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let granted: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(granted ? .green : AppTheme.Colors.accent)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Fonts.headline)
                    .foregroundColor(AppTheme.Colors.primary)
                Text(description)
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(AppTheme.Colors.secondary)
            }
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(granted ? .green : AppTheme.Colors.secondary)
        }
        .cardStyle()
    }
}
