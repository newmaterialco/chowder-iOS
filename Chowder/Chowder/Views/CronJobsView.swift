import SwiftUI

struct CronJobsView: View {
    var chatService: ChatService?
    var isConnected: Bool
    @Binding var selectedTab: Tab
    var viewModel: ChatViewModel

    @State private var jobs: [CronJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Reuse the same header with the pill toggle
                ChatHeaderView(
                    botName: viewModel.botName,
                    isOnline: viewModel.isConnected,
                    avatarImage: viewModel.avatarImage,
                    selectedTab: $selectedTab,
                    onSettingsTapped: { viewModel.showSettings = true },
                    onDebugTapped: { viewModel.showDebugLog = true }
                )

                Group {
                    if !isConnected {
                        ContentUnavailableView(
                            "Not Connected",
                            systemImage: "wifi.slash",
                            description: Text("Connect to the gateway to view cron jobs.")
                        )
                    } else if isLoading && jobs.isEmpty {
                        ProgressView("Loading cron jobs...")
                    } else if let error = errorMessage, jobs.isEmpty {
                        ContentUnavailableView(
                            "Error",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                    } else if jobs.isEmpty {
                        ContentUnavailableView(
                            "No Cron Jobs",
                            systemImage: "clock.arrow.circlepath",
                            description: Text("No cron jobs configured on the gateway.")
                        )
                    } else {
                        List {
                            ForEach(jobs) { job in
                                NavigationLink(destination: CronJobDetailView(job: job, chatService: chatService)) {
                                    CronJobRow(job: job)
                                }
                            }
                        }
                        .refreshable {
                            await fetchJobs()
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                if jobs.isEmpty {
                    Task { await fetchJobs() }
                }
            }
            .onChange(of: isConnected) { _, connected in
                if connected && jobs.isEmpty {
                    Task { await fetchJobs() }
                }
            }
        }
    }

    @MainActor
    private func fetchJobs() async {
        guard let chatService, isConnected else { return }
        isLoading = true
        errorMessage = nil

        await withCheckedContinuation { continuation in
            chatService.fetchCronJobs { ok, rawJobs in
                if ok, let rawJobs {
                    self.jobs = rawJobs.compactMap { CronJob.from(dict: $0) }
                        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                } else if !ok {
                    self.errorMessage = "Failed to fetch cron jobs."
                }
                self.isLoading = false
                continuation.resume()
            }
        }
    }
}

// MARK: - Row

private struct CronJobRow: View {
    let job: CronJob

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.name)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)

                    if !job.enabled {
                        Text("DISABLED")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .clipShape(Capsule())
                    }
                }

                Text(job.schedule.humanReadable)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Next run
            if let nextMs = job.state.nextRunAtMs {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(CronJob.relativeTime(fromMs: nextMs))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        guard job.enabled else { return Color(.systemGray4) }
        switch job.state.lastRunStatus {
        case "ok": return .green
        case "error": return .red
        default: return Color(.systemGray4)
        }
    }
}
