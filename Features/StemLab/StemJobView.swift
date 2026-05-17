import SwiftUI

struct StemJobView: View {
    @ObservedObject var vm: StemViewModel
    @State private var selectedJob: StemJob?

    var body: some View {
        NavigationStack {
            Group {
                if vm.jobs.isEmpty {
                    emptyState
                } else {
                    jobList
                }
            }
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationTitle("Stem Jobs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if vm.jobs.contains(where: {
                        $0.model.status == .complete || $0.model.status == .failed
                    }) {
                        Button("Clear Done") { vm.clearCompleted() }
                            .foregroundColor(AppTheme.Colors.accent)
                    }
                }
            }
            .sheet(item: $selectedJob) { job in
                StemPlayerView(job: job.model, vm: vm)
            }
        }
    }

    // MARK: - Job list
    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(vm.jobs) { job in
                    StemJobCard(job: job)
                        .onTapGesture {
                            if job.model.status == .complete { selectedJob = job }
                        }
                }
            }
            .padding(AppTheme.Spacing.md)
        }
    }

    // MARK: - Empty
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tuningfork")
                .font(.system(size: 56))
                .foregroundColor(AppTheme.Colors.secondary)
            Text("No stem jobs")
                .font(AppTheme.Fonts.title)
                .foregroundColor(AppTheme.Colors.primary)
            Text("Import an audio file in Stem Lab to start a separation job.")
                .font(AppTheme.Fonts.body)
                .foregroundColor(AppTheme.Colors.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(AppTheme.Spacing.xl)
    }
}

// MARK: - StemJobCard
struct StemJobCard: View {
    @ObservedObject var job: StemJob

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.model.sourceURL.lastPathComponent)
                        .font(AppTheme.Fonts.headline)
                        .foregroundColor(AppTheme.Colors.primary)
                        .lineLimit(1)
                    Text(job.model.mode.rawValue)
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.Colors.secondary)
                }
                Spacer()
                statusBadge
            }

            // Progress bar (processing only)
            if job.model.status == .processing {
                ProgressView(value: job.model.progress)
                    .tint(AppTheme.Colors.accent)
                Text("Separating… \(Int(job.model.progress * 100))%")
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(AppTheme.Colors.accent)
            }

            // Output track chips (complete only)
            if job.model.status == .complete, !job.model.outputURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(job.model.outputURLs.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { track in
                            Label(track.displayName, systemImage: track.systemImage)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppTheme.Colors.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.Colors.accent.opacity(0.12))
                                .cornerRadius(AppTheme.Radius.pill)
                        }
                    }
                }
            }

            // Error message
            if let msg = job.model.errorMessage {
                Text(msg)
                    .font(AppTheme.Fonts.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            // Tap hint
            if job.model.status == .complete {
                HStack {
                    Spacer()
                    Text("Tap to open mixer →")
                        .font(AppTheme.Fonts.caption)
                        .foregroundColor(AppTheme.Colors.accent)
                }
            }
        }
        .cardStyle()
        .animation(AppTheme.Animation.standard, value: job.model.status)
    }

    @ViewBuilder private var statusBadge: some View {
        switch job.model.status {
        case .queued:
            Label("Queued", systemImage: "clock")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppTheme.Colors.secondary)
        case .processing:
            ProgressView().tint(AppTheme.Colors.accent).scaleEffect(0.8)
        case .complete:
            Label("Complete", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.red)
        }
    }
}
