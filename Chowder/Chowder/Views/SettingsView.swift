import SwiftUI
import PhotosUI

// MARK: - Main Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var currentIdentity: BotIdentity = BotIdentity()
    var currentProfile: UserProfile = UserProfile()
    var locationPreferences: LocationPreferences = LocationPreferences()
    var locationAuthorizationLabel: String = "Not Determined"
    var locationAccuracyLabel: String = "Unknown"
    var locationSyncState: LocationSyncState = LocationSyncState()
    var isConnected: Bool = false
    var onSave: ((BotIdentity, UserProfile) -> Void)?
    var onLocationSharingChanged: ((Bool) -> Void)?
    var onSyncLocationNow: (() -> Void)?
    var onSaveConnection: (() -> Void)?
    var onClearHistory: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {

                    // MARK: - Agent Card

                    NavigationLink {
                        AgentDetailView(
                            currentIdentity: currentIdentity,
                            onSave: { identity in
                                onSave?(identity, currentProfile)
                            }
                        )
                    } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                agentAvatar(size: 40)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(currentIdentity.name.isEmpty ? "Agent" : currentIdentity.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                        Text(isConnected ? "Online" : "Offline")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: - Mac Mini Card

                    NavigationLink {
                        ConnectionDetailView(
                            onSave: {
                                onSaveConnection?()
                            }
                        )
                    } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                GlassIcon(systemName: "macmini")

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mac Mini")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(isConnected ? Color.green : Color.gray.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                        Text(isConnected ? "Connected" : "Disconnected")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: - User Card

                    NavigationLink {
                        UserDetailView(
                            currentProfile: currentProfile,
                            locationPreferences: locationPreferences,
                            locationAuthorizationLabel: locationAuthorizationLabel,
                            locationAccuracyLabel: locationAccuracyLabel,
                            locationSyncState: locationSyncState,
                            onLocationSharingChanged: onLocationSharingChanged,
                            onSyncLocationNow: onSyncLocationNow,
                            onSave: { profile in
                                onSave?(currentIdentity, profile)
                            }
                        )
                    } label: {
                        GlassCard {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(.systemGray5))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Text(String((currentProfile.name.isEmpty ? "U" : currentProfile.name).prefix(1)).uppercased())
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(currentProfile.name.isEmpty ? "User" : currentProfile.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text("Primary User")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // MARK: - Passbook Section

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Passbook")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        Text("For demo purposes only. This section will be contributed to as the project evolves.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)

                        GlassCard(padding: 4) {
                            VStack(spacing: 0) {
                                ForEach(Array(PassbookItem.allItems.enumerated()), id: \.element.id) { index, item in
                                    PassbookRow(item: item)

                                    if index < PassbookItem.allItems.count - 1 {
                                        Divider()
                                            .opacity(0.3)
                                            .padding(.leading, 52)
                                    }
                                }
                            }
                        }
                    }

                    // MARK: - Developer Section

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Developer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        Text("For demo purposes only. This section will be contributed to as the project evolves.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)

                        GlassCard {
                            Button {
                                LiveActivityManager.shared.startDemo()
                            } label: {
                                HStack(spacing: 12) {
                                    GlassIcon(systemName: "platter.filled.bottom.and.arrow.down.iphone", size: 32, iconSize: 14)

                                    Text("Live Activity Demo")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)

                                    Spacer()
                                }
                            }
                        }
                    }

                    // MARK: - Data Section

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 4)
                            .padding(.top, 8)

                        GlassCard {
                            Button(role: .destructive) {
                                onClearHistory?()
                            } label: {
                                HStack {
                                    Text("Clear Chat History")
                                        .font(.system(size: 16))
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Agent Avatar Helper

    @ViewBuilder
    private func agentAvatar(size: CGFloat) -> some View {
        if let customAvatar = LocalStorage.loadAvatar() {
            Image(uiImage: customAvatar)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let uiImage = UIImage(named: "BotAvatar") {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                .frame(width: size, height: size)
                .overlay(
                    Text(String((currentIdentity.name.isEmpty ? "A" : currentIdentity.name).prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

// MARK: - Glass Icon

struct GlassIcon: View {
    let systemName: String
    var size: CGFloat = 40
    var iconSize: CGFloat = 18

    var body: some View {
        Circle()
            .fill(Color(.systemGray5))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Passbook Item Model

struct PassbookItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String

    static let allItems: [PassbookItem] = [
        PassbookItem(icon: "phone", title: "Phone Number"),
        PassbookItem(icon: "envelope", title: "Email"),
        PassbookItem(icon: "icloud", title: "iCloud"),
        PassbookItem(icon: "wallet.pass", title: "Wallet"),
        PassbookItem(icon: "airplane", title: "Travel"),
        PassbookItem(icon: "car", title: "Car"),
        PassbookItem(icon: "house", title: "Home"),
    ]
}

// MARK: - Passbook Row

struct PassbookRow: View {
    let item: PassbookItem

    var body: some View {
        HStack(spacing: 12) {
            GlassIcon(systemName: item.icon, size: 32, iconSize: 14)

            Text(item.title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Agent Detail View

struct AgentDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var currentIdentity: BotIdentity = BotIdentity()
    var onSave: ((BotIdentity) -> Void)?

    // Agent Avatar
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?

    // Bot Identity fields
    @State private var botName: String = ""
    @State private var botCreature: String = ""
    @State private var botVibe: String = ""
    @State private var botEmoji: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Avatar section
                VStack(spacing: 12) {
                    if let avatarImage {
                        Image(uiImage: avatarImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else if let uiImage = UIImage(named: "BotAvatar") {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(red: 219/255, green: 84/255, blue: 75/255))
                            .frame(width: 88, height: 88)
                            .overlay(
                                Text(String((botName.isEmpty ? "A" : botName).prefix(1)).uppercased())
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundStyle(.white)
                            )
                    }

                    HStack(spacing: 16) {
                        PhotosPicker(selection: $avatarItem, matching: .images) {
                            Text("Choose Photo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.blue)
                        }

                        if avatarImage != nil {
                            Button("Remove", role: .destructive) {
                                avatarImage = nil
                                avatarItem = nil
                                LocalStorage.deleteAvatar()
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
                .padding(.top, 12)

                // Identity fields
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        GlassTextField(label: "Name", text: $botName)
                        GlassDivider()
                        GlassTextField(label: "Creature", placeholder: "AI, robot, familiar...", text: $botCreature)
                        GlassDivider()
                        GlassTextField(label: "Vibe", placeholder: "warm, sharp, chaotic...", text: $botVibe)
                        GlassDivider()
                        GlassTextField(label: "Emoji", text: $botEmoji)
                    }
                }

                Text("Synced with IDENTITY.md on the gateway.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                // Save button
                GlassSaveButton {
                    if let avatarImage {
                        LocalStorage.saveAvatar(avatarImage)
                    }

                    let identity = BotIdentity(
                        name: botName.trimmingCharacters(in: .whitespacesAndNewlines),
                        creature: botCreature.trimmingCharacters(in: .whitespacesAndNewlines),
                        vibe: botVibe.trimmingCharacters(in: .whitespacesAndNewlines),
                        emoji: botEmoji.trimmingCharacters(in: .whitespacesAndNewlines),
                        avatar: currentIdentity.avatar
                    )
                    onSave?(identity)
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: avatarItem) {
            Task {
                if let data = try? await avatarItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    avatarImage = image
                }
            }
        }
        .onAppear {
            avatarImage = LocalStorage.loadAvatar()
            botName = currentIdentity.name
            botCreature = currentIdentity.creature
            botVibe = currentIdentity.vibe
            botEmoji = currentIdentity.emoji
        }
    }
}

// MARK: - Connection Detail View

struct ConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (() -> Void)?

    @State private var gatewayURL: String = ""
    @State private var token: String = ""
    @State private var sessionKey: String = ""
    @State private var cfAccessEnabled: Bool = false
    @State private var cfAccessClientId: String = ""
    @State private var cfAccessClientSecret: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Gateway
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gateway")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        GlassTextField(label: "URL", placeholder: "ws://100.x.y.z:18789", text: $gatewayURL)
                            .textContentType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Authentication
                VStack(alignment: .leading, spacing: 6) {
                    Text("Authentication")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        HStack {
                            Text("Token")
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                                .frame(width: 80, alignment: .leading)

                            SecureField("Token", text: $token)
                                .font(.system(size: 16))
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }

                // Cloudflare Zero Trust
                VStack(alignment: .leading, spacing: 6) {
                    Text("Cloudflare Zero Trust")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Enable")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Toggle("", isOn: $cfAccessEnabled.animation())
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)

                            if cfAccessEnabled {
                                Divider().padding(.leading, 16)

                                HStack {
                                    Text("Client ID")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .frame(width: 80, alignment: .leading)

                                    SecureField("Service token client ID", text: $cfAccessClientId)
                                        .font(.system(size: 16))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)

                                Divider().padding(.leading, 16)

                                HStack {
                                    Text("Secret")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .frame(width: 80, alignment: .leading)

                                    SecureField("Service token secret", text: $cfAccessClientSecret)
                                        .font(.system(size: 16))
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 13)
                            }
                        }
                    }
                }

                // Session
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        GlassTextField(label: "Key", placeholder: "agent:main:main", text: $sessionKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                // Save button
                GlassSaveButton(
                    disabled: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ) {
                    var config = ConnectionConfig()
                    config.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.sessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    config.cfAccessClientId = cfAccessEnabled ? cfAccessClientId.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    config.cfAccessClientSecret = cfAccessEnabled ? cfAccessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                    onSave?()
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Mac Mini")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let config = ConnectionConfig()
            gatewayURL = config.gatewayURL
            token = config.token
            sessionKey = config.sessionKey
            cfAccessEnabled = config.hasCloudflareAccessTokens
            cfAccessClientId = config.cfAccessClientId
            cfAccessClientSecret = config.cfAccessClientSecret
        }
    }
}

// MARK: - User Detail View

struct UserDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var currentProfile: UserProfile = UserProfile()
    var locationPreferences: LocationPreferences = LocationPreferences()
    var locationAuthorizationLabel: String = "Not Determined"
    var locationAccuracyLabel: String = "Unknown"
    var locationSyncState: LocationSyncState = LocationSyncState()
    var onLocationSharingChanged: ((Bool) -> Void)?
    var onSyncLocationNow: (() -> Void)?
    var onSave: ((UserProfile) -> Void)?

    @State private var userName: String = ""
    @State private var userCallName: String = ""
    @State private var userPronouns: String = ""
    @State private var userTimezone: String = ""
    @State private var userNotes: String = ""
    @State private var userContext: String = ""
    @State private var shareLocation: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // User avatar
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 88, height: 88)
                    .overlay(
                        Text(String((userName.isEmpty ? "U" : userName).prefix(1)).uppercased())
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    )
                    .padding(.top, 12)

                // Profile fields
                VStack(alignment: .leading, spacing: 6) {
                    Text("Profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            GlassTextField(label: "Name", text: $userName)
                                .textContentType(.name)
                            GlassDivider()
                            GlassTextField(label: "Call Name", placeholder: "What to call you", text: $userCallName)
                            GlassDivider()
                            GlassTextField(label: "Pronouns", text: $userPronouns)
                            GlassDivider()
                            GlassTextField(label: "Timezone", text: $userTimezone)
                            GlassDivider()
                            GlassMultilineField(label: "Notes", text: $userNotes)
                        }
                    }

                    Text("Synced with USER.md on the gateway.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // Context
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        TextField("Context, preferences, interests...", text: $userContext, axis: .vertical)
                            .lineLimit(3...8)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                    }

                    Text("What do you care about? What projects are you working on? Build this over time.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // Location
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    GlassCard(padding: 0) {
                        VStack(spacing: 0) {
                            Toggle(isOn: $shareLocation) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share Location with OpenClaw")
                                        .font(.system(size: 16))
                                    Text("Updates LOCATION.md with visits and significant changes")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .onChange(of: shareLocation) { _, value in
                                onLocationSharingChanged?(value)
                            }

                            GlassDivider()

                            VStack(spacing: 10) {
                                HStack {
                                    Text("Authorization")
                                        .font(.system(size: 15))
                                    Spacer()
                                    Text(locationAuthorizationLabel)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Text("Accuracy")
                                        .font(.system(size: 15))
                                    Spacer()
                                    Text(locationAccuracyLabel)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }

                                HStack {
                                    Text("Last Updated")
                                        .font(.system(size: 15))
                                    Spacer()
                                    Text(formattedLocationDate(locationSyncState.lastSnapshot?.timestamp))
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current Address")
                                        .font(.system(size: 15))
                                    Text(currentAddressPreview())
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Button {
                                    onSyncLocationNow?()
                                } label: {
                                    HStack {
                                        Text("Sync Location Now")
                                            .font(.system(size: 15, weight: .medium))
                                        Spacer()
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 13, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(!shareLocation)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                    }

                    Text("Chowder keeps a last known location with freshness metadata in LOCATION.md.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }

                // Save button
                GlassSaveButton {
                    let profile = UserProfile(
                        name: userName.trimmingCharacters(in: .whitespacesAndNewlines),
                        callName: userCallName.trimmingCharacters(in: .whitespacesAndNewlines),
                        pronouns: userPronouns.trimmingCharacters(in: .whitespacesAndNewlines),
                        timezone: userTimezone.trimmingCharacters(in: .whitespacesAndNewlines),
                        notes: userNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                        context: userContext.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave?(profile)
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("User")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            userName = currentProfile.name
            userCallName = currentProfile.callName
            userPronouns = currentProfile.pronouns
            userTimezone = currentProfile.timezone
            userNotes = currentProfile.notes
            userContext = currentProfile.context
            shareLocation = locationPreferences.sharingEnabled
        }
    }

    private func formattedLocationDate(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func currentAddressPreview() -> String {
        guard let snapshot = locationSyncState.lastSnapshot else { return "Unknown" }
        let parts = [
            snapshot.street,
            snapshot.locality,
            snapshot.administrativeArea,
            snapshot.postalCode,
            snapshot.country
        ]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        if let place = snapshot.placeName?.trimmingCharacters(in: .whitespacesAndNewlines), !place.isEmpty {
            return place
        }
        return "Unknown"
    }
}

// MARK: - Shared Glass Components

struct GlassTextField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)

            TextField(placeholder.isEmpty ? label : placeholder, text: $text)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct GlassMultilineField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .leading)
                .padding(.top, 2)

            TextField(label, text: $text, axis: .vertical)
                .lineLimit(2...4)
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

struct GlassDivider: View {
    var body: some View {
        Divider()
            .opacity(0.3)
            .padding(.leading, 16)
    }
}

struct GlassSaveButton: View {
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Save")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(disabled ? Color.blue.opacity(0.4) : .blue)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
        .disabled(disabled)
    }
}
