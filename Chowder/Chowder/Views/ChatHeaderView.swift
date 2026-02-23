import SwiftUI

struct ChatHeaderView: View {
    let botName: String
    let isOnline: Bool
    var avatarImage: UIImage?
    @Binding var selectedTab: Tab
    var onSettingsTapped: (() -> Void)?
    var onDebugTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?
    var isSpeakerEnabled: Bool = false
    var onSpeakerToggle: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Avatar tappable to open settings
                Button {
                    onSettingsTapped?()
                } label: {
                    HStack(spacing: 8) {
                        if let customAvatar = avatarImage {
                            Image(uiImage: customAvatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else if let uiImage = UIImage(named: "BotAvatar") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(String(botName.prefix(1)))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                )
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(botName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(isOnline ? "Online" : "Offline")
                                .font(.system(size: 12))
                                .foregroundStyle(.gray)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)

                // Speaker toggle (TTS)
                Button {
                    onSpeakerToggle?()
                } label: {
                    Image(systemName: isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 16))
                        .foregroundStyle(isSpeakerEnabled ? .blue : .gray)
                        .frame(width: 34, height: 34)
                }

                // Search button
                Button {
                    onSearchTapped?()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                        .frame(width: 34, height: 34)
                }

                // Sessions / Chat / Cron pill toggle
                TabPillToggle(selectedTab: $selectedTab)

                // Debug button
                Button {
                    onDebugTapped?()
                } label: {
                    Image(systemName: "ant")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray)
                        .frame(width: 34, height: 34)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Compact Pill Toggle

struct TabPillToggle: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .sessions, icon: "tray.full")
            tabButton(tab: .chat, icon: "bubble.left.and.bubble.right")
            tabButton(tab: .cron, icon: "clock.arrow.circlepath")
        }
        .padding(3)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func tabButton(tab: Tab, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selectedTab == tab ? .white : .gray)
                .frame(width: 30, height: 30)
                .background(
                    selectedTab == tab
                        ? Capsule().fill(Color.blue)
                        : Capsule().fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
