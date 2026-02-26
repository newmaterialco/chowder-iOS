import SwiftUI

enum Tab: String, CaseIterable {
    case sessions, chat, cron
}

struct MainTabView: View {
    @State private var viewModel = ChatViewModel()
    @State private var selectedTab: Tab = .chat
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            SessionListView(viewModel: viewModel, selectedTab: $selectedTab)
                .opacity(selectedTab == .sessions ? 1 : 0)
                .allowsHitTesting(selectedTab == .sessions)

            ChatView(viewModel: viewModel, selectedTab: $selectedTab)
                .opacity(selectedTab == .chat ? 1 : 0)
                .allowsHitTesting(selectedTab == .chat)

            CronJobsView(
                chatService: viewModel.exposedChatService,
                isConnected: viewModel.isConnected,
                selectedTab: $selectedTab,
                viewModel: viewModel
            )
            .opacity(selectedTab == .cron ? 1 : 0)
            .allowsHitTesting(selectedTab == .cron)
        }
        .onAppear {
            viewModel.connect()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                viewModel.didEnterBackground()
            } else if newPhase == .active && oldPhase != .active {
                viewModel.didReturnToForeground()
                if oldPhase == .background {
                    viewModel.reconnect()
                }
            }
        }
        .alert("Device Not Paired", isPresented: $viewModel.showNotPairedAlert) {
            Button("Open Gateway") {
                let urlString = ConnectionConfig().gatewayURL
                    .replacingOccurrences(of: "ws://", with: "http://")
                    .replacingOccurrences(of: "wss://", with: "https://")
                if let url = URL(string: urlString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Open Settings") {
                viewModel.showSettings = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This device's identity has changed (e.g. after reinstall). Please re-approve it in your gateway's device management, then reconnect.")
        }
    }
}
