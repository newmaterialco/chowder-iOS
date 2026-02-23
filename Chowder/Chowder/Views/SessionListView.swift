import SwiftUI

struct SessionListView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var selectedTab: Tab
    @State private var newSessionLabel = ""
    @State private var newSessionKey = ""
    @State private var showNewSession = false
    @State private var editingSession: SavedSession?

    var body: some View {
        VStack(spacing: 0) {
            // Header (shared style)
            ChatHeaderView(
                botName: viewModel.botName,
                isOnline: viewModel.isConnected,
                avatarImage: viewModel.avatarImage,
                selectedTab: $selectedTab,
                onSettingsTapped: { viewModel.showSettings = true },
                onDebugTapped: { viewModel.showDebugLog = true }
            )

            List {
                Section {
                    ForEach(viewModel.savedSessions) { session in
                        Button {
                            viewModel.switchToSession(session)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = .chat
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(session.label)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(.primary)

                                        if session.key == viewModel.currentSessionKey {
                                            Text("ACTIVE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(session.key)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(.tertiary)

                                    HStack(spacing: 8) {
                                        Text("\(session.messageCount) messages")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Text(session.lastUsed, style: .relative)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()

                                if session.key == viewModel.currentSessionKey {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if session.key != viewModel.currentSessionKey {
                                Button(role: .destructive) {
                                    viewModel.deleteSession(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button {
                                editingSession = session
                                newSessionLabel = session.label
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    Text("Sessions")
                }

                Section {
                    Button {
                        showNewSession = true
                    } label: {
                        Label("New Session", systemImage: "plus.circle")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .alert("New Session", isPresented: $showNewSession) {
                TextField("Label (e.g. Research)", text: $newSessionLabel)
                TextField("Session key (e.g. agent:main:research)", text: $newSessionKey)
                Button("Create") {
                    let label = newSessionLabel.isEmpty ? "Session \(viewModel.savedSessions.count + 1)" : newSessionLabel
                    let key = newSessionKey.isEmpty ? "agent:main:\(label.lowercased().replacingOccurrences(of: " ", with: "-"))" : newSessionKey
                    viewModel.createSession(label: label, key: key)
                    newSessionLabel = ""
                    newSessionKey = ""
                }
                Button("Cancel", role: .cancel) {
                    newSessionLabel = ""
                    newSessionKey = ""
                }
            } message: {
                Text("Create a new conversation session with the agent.")
            }
            .alert("Rename Session", isPresented: Binding(
                get: { editingSession != nil },
                set: { if !$0 { editingSession = nil } }
            )) {
                TextField("Label", text: $newSessionLabel)
                Button("Save") {
                    if let session = editingSession {
                        viewModel.renameSession(session, newLabel: newSessionLabel)
                    }
                    editingSession = nil
                    newSessionLabel = ""
                }
                Button("Cancel", role: .cancel) {
                    editingSession = nil
                    newSessionLabel = ""
                }
            } message: {
                Text("Enter a new label for this session.")
            }
        }
    }
}
