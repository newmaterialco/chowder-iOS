import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @Binding var selectedTab: Tab
    @State private var isAtBottom = true
    @State private var showSearch = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    // Spacer to push content below header
                    Color.clear.frame(height: 72)

                    LazyVStack(alignment: .leading, spacing: 16) {
                        // "Load earlier messages" button
                        if viewModel.hasEarlierMessages {
                            Button {
                                viewModel.loadEarlierMessages()
                            } label: {
                                Text("Load earlier messages")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }

                        ForEach(viewModel.displayedMessages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        // Inline completed steps — wrapped in VStack with tight spacing
                        if let activity = viewModel.currentActivity,
                           !activity.completedSteps.isEmpty {
                            VStack(spacing: 4) {
                                ForEach(activity.completedSteps) { step in
                                    ActivityStepRow(step: step) {
                                        viewModel.showActivityCard = true
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)).animation(.easeOut(duration: 0.15)))
                                    .onAppear {
                                        print("🎨 Completed step appeared: '\(step.label)'")
                                        // Light haptic when step appears
                                        let haptic = UIImpactFeedbackGenerator(style: .light)
                                        haptic.impactOccurred()
                                    }
                                }
                            }
                            .transition(.opacity.animation(.easeOut(duration: 0.15)))
                        }

                        // Approval cards — shown inline when agent needs user approval
                        ForEach(viewModel.pendingApprovals, id: \.id) { request in
                            ApprovalCardView(
                                request: request,
                                onApprove: { viewModel.handleApprovalResponse(id: request.id, approved: true) },
                                onDeny: { viewModel.handleApprovalResponse(id: request.id, approved: false) }
                            )
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        // Thinking shimmer — shown while the agent is working
                        if let activity = viewModel.currentActivity,
                           !activity.currentLabel.isEmpty {
                            ThinkingShimmerView(label: activity.currentLabel) {
                                viewModel.showActivityCard = true
                            }
                            .id("shimmer")
                            .transition(.opacity)
                            .onAppear {
                                print("🎨 Shimmer appeared with label: '\(activity.currentLabel)'")
                            }
                        }

                        // Invisible anchor — must be inside LazyVStack so
                        // onAppear/onDisappear track scroll visibility.
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .onAppear { withAnimation(.easeOut(duration: 0.12)) { isAtBottom = true } }
                            .onDisappear { withAnimation(.easeOut(duration: 0.12)) { isAtBottom = false } }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                .defaultScrollAnchor(.bottom)
                .overlay(alignment: .bottom) {
                    if !isAtBottom {
                        Button {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(.secondaryLabel))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(.systemBackground))
                                )
                                .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
                        }
                        .padding(.bottom, 10)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    // Scroll to bottom when new messages arrive
                    if isAtBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: viewModel.messages.last?.content) {
                    // Auto-scroll as streaming message content grows
                    if isAtBottom {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                // Search overlay
                .overlay(alignment: .top) {
                    if showSearch {
                        MessageSearchView(
                            messages: viewModel.messages,
                            isPresented: $showSearch,
                            onResultTapped: { messageId in
                                showSearch = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo(messageId, anchor: .center)
                                    }
                                }
                            }
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }

            // Input bar
            HStack(spacing: 8) {
                // Image picker button
                Button {
                    viewModel.showImagePicker = true
                } label: {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20))
                        .foregroundStyle(.gray)
                }

                // Image thumbnail preview (if image is staged)
                if let stagedImage = viewModel.stagedImage {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: stagedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Button {
                            viewModel.stagedImage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .background(Circle().fill(Color.black.opacity(0.6)))
                        }
                        .offset(x: 4, y: -4)
                    }
                }

                TextField("Message...", text: $viewModel.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Mic button for voice input
                Button {
                    viewModel.toggleVoiceInput()
                } label: {
                    Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 20))
                        .foregroundStyle(viewModel.isListening ? .red : .gray)
                }

                Button {
                    isInputFocused = false
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            viewModel.canSend
                                ? Color.blue
                                : Color(.systemGray4)
                        )
                }
                .disabled(!viewModel.canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .overlay(alignment: .top) {
            ChatHeaderView(
                botName: viewModel.botName,
                isOnline: viewModel.isConnected,
                avatarImage: viewModel.avatarImage,
                selectedTab: $selectedTab,
                onSettingsTapped: { viewModel.showSettings = true },
                onDebugTapped: { viewModel.showDebugLog = true },
                onSearchTapped: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showSearch.toggle()
                    }
                },
                isSpeakerEnabled: viewModel.isSpeakerEnabled,
                onSpeakerToggle: { viewModel.toggleSpeaker() }
            )
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(
                currentIdentity: viewModel.botIdentity,
                currentProfile: viewModel.userProfile,
                currentAvatar: viewModel.avatarImage,
                isConnected: viewModel.isConnected,
                onSave: { identity, profile in
                    viewModel.saveWorkspaceData(identity: identity, profile: profile)
                },
                onSaveAvatar: { image in
                    viewModel.saveManualAvatar(image)
                },
                onDeleteAvatar: {
                    viewModel.deleteAvatar()
                },
                onSaveConnection: {
                    viewModel.reconnect()
                },
                onClearHistory: { viewModel.clearMessages() }
            )
        }
        .sheet(isPresented: $viewModel.showActivityCard) {
            if let activity = viewModel.currentActivity ?? viewModel.lastCompletedActivity {
                AgentActivityCard(activity: activity)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $viewModel.showDebugLog) {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(viewModel.debugLog.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(12)
                }
                .onAppear { viewModel.flushLogBuffer() }
                .navigationTitle("Debug Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { viewModel.showDebugLog = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        HStack(spacing: 12) {
                            Button("Clear") { viewModel.debugLog.removeAll() }
                            Button("Copy") {
                                UIPasteboard.general.string = viewModel.debugLog.joined(separator: "\n")
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showImagePicker) {
            ImagePickerView { image in
                viewModel.stagedImage = image
            }
        }
    }
}

#Preview {
    ChatView(viewModel: ChatViewModel(), selectedTab: .constant(.chat))
}
