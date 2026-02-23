import SwiftUI
import UIKit

@Observable
final class ChatViewModel: ChatServiceDelegate {

    var messages: [Message] = []
    var inputText: String = ""

    // MARK: - Pagination

    /// Number of messages shown from the end of the history.
    var displayLimit: Int = 50
    private let pageSize: Int = 50

    /// The slice of messages currently rendered in the chat view.
    var displayedMessages: [Message] {
        if messages.count <= displayLimit {
            return messages
        }
        return Array(messages.suffix(displayLimit))
    }

    /// Whether there are older messages beyond what's currently displayed.
    var hasEarlierMessages: Bool {
        messages.count > displayLimit
    }

    /// Load the next page of earlier messages.
    func loadEarlierMessages() {
        displayLimit += pageSize
    }
    var isLoading: Bool = false
    var isConnected: Bool = false
    var showSettings: Bool = false
    var debugLog: [String] = []
    var showDebugLog: Bool = false

    // Workspace-synced data from the gateway
    var botIdentity: BotIdentity = LocalStorage.loadBotIdentity()
    var userProfile: UserProfile = LocalStorage.loadUserProfile()

    /// The bot's display name — uses IDENTITY.md name, falls back to "Chowder".
    var botName: String {
        botIdentity.name.isEmpty ? "Chowder" : botIdentity.name
    }

    /// Tracks the agent's current turn activity (thinking, tool calls) for the shimmer display.
    /// Set to a new instance when a turn starts; nil when the turn ends.
    var currentActivity: AgentActivity?

    /// Snapshot of the last completed activity, kept around so the user can still
    /// tap to view it after the shimmer disappears.
    var lastCompletedActivity: AgentActivity?

    /// Controls presentation of the activity detail card.
    var showActivityCard: Bool = false

    /// The current task summary title (AI-generated), shown in the chat header during active tasks.
    var currentTaskSummary: String? {
        liveActivitySubject
    }

    private var shimmerStartTime: Date?

    /// Light haptic fired once when the assistant's response starts streaming.
    @ObservationIgnored private let responseHaptic = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private var hasPlayedResponseHaptic = false
    @ObservationIgnored private var hasReceivedAnyDelta = false

    private var chatService: ChatService?

    var isConfigured: Bool {
        ConnectionConfig().isConfigured
    }
    
    // MARK: - History Parsing State
    
    /// Generation counter incremented each time a new message is sent
    /// Used to discard stale history responses from previous runs
    private var currentRunGeneration: Int = 0
    
    /// Timestamp when the current run started - used to filter old history items
    private var currentRunStartTime: Date?
    
    /// Tracks seen thinking items by their thinkingSignature.id to prevent duplicates
    private var seenThinkingIds: Set<String> = []
    
    /// Tracks seen tool calls by their id to prevent duplicates
    private var seenToolCallIds: Set<String> = []
    /// Separate set for tool results — must not collide with seenToolCallIds
    private var seenToolResultIds: Set<String> = []
    
    /// Metadata for tool calls, keyed by toolCallId, used to show completion info
    private var toolCallMetadata: [String: ToolCallMeta] = [:]
    
    /// Metadata stored for each tool call to derive completion labels
    struct ToolCallMeta {
        let toolName: String
        let arguments: [String: Any]
        let derivedIntent: String
        let category: ToolCategory
    }

    // MARK: - Live Activity Tracking State

    /// The latest step label (thinking or tool) -- shown ALL CAPS at the bottom.
    private var liveActivityBottomText: String = "Thinking..."
    /// The most recent thinking/intent step -- shown with the yellow arrow.
    private var liveActivityYellowIntent: String?
    /// The 2nd most recent thinking/intent step -- shown with the grey checkmark.
    private var liveActivityGreyIntent: String?
    /// Accumulated cost for the current run.
    private var liveActivityCostAccumulator: Double = 0
    /// Formatted accumulated cost string.
    private var liveActivityCost: String?
    /// Total step count for the Live Activity.
    private var liveActivityStepNumber: Int = 1
    /// Subject line for the Live Activity -- latched from first thinking summary.
    private var liveActivitySubject: String?
    /// SF Symbol name for the current intent's tool category.
    private var liveActivityCurrentIcon: String?
    /// Cache of intent -> past-tense conversion so each intent is only converted once.
    private var pastTenseCache: [String: String] = [:]

    /// Shift a new thinking intent into the yellow/grey stack.
    /// Only call this for thinking steps -- NOT tool events.
    /// The new intent is placed as-is initially, then an async past-tense conversion
    /// fires and updates the value in place (grey reuses the already-converted yellow).
    private func shiftThinkingIntent(_ newIntent: String) {
        guard newIntent != liveActivityYellowIntent else { return }
        // Grey gets yellow's value (already converted or mid-conversion)
        liveActivityGreyIntent = liveActivityYellowIntent
        // Use cached past tense if available, otherwise set raw and convert async
        if let cached = pastTenseCache[newIntent] {
            liveActivityYellowIntent = cached
        } else {
            liveActivityYellowIntent = newIntent
            let intentToConvert = newIntent
            Task {
                let pastTense = await TaskSummaryService.shared.convertToPastTense(intentToConvert)
                await MainActor.run {
                    if let pastTense {
                        self.pastTenseCache[intentToConvert] = pastTense
                        // Only update if this intent is still the current yellow
                        if self.liveActivityYellowIntent == intentToConvert {
                            self.liveActivityYellowIntent = pastTense
                            self.pushLiveActivityUpdate()
                        }
                        // Or if it already shifted to grey
                        if self.liveActivityGreyIntent == intentToConvert {
                            self.liveActivityGreyIntent = pastTense
                            self.pushLiveActivityUpdate()
                        }
                    }
                }
            }
        }
        if liveActivitySubject == nil {
            liveActivitySubject = newIntent
        }
    }

    /// Push current tracking state to the Live Activity.
    private func pushLiveActivityUpdate(isAISubject: Bool = false) {
        LiveActivityManager.shared.update(
            subject: liveActivitySubject,
            currentIntent: liveActivityBottomText,
            currentIntentIcon: liveActivityCurrentIcon,
            previousIntent: liveActivityYellowIntent,
            secondPreviousIntent: liveActivityGreyIntent,
            stepNumber: liveActivityStepNumber,
            costTotal: liveActivityCost,
            isAISubject: isAISubject
        )
    }

    /// Reset Live Activity tracking state for a new run.
    private func resetLiveActivityState() {
        liveActivityBottomText = "Thinking..."
        liveActivityYellowIntent = nil
        liveActivityGreyIntent = nil
        liveActivityCostAccumulator = 0
        liveActivityCost = nil
        liveActivityStepNumber = 1
        liveActivitySubject = nil
        liveActivityCurrentIcon = nil
        pastTenseCache.removeAll()
    }

    /// Generate a completion summary message from the task title.
    /// Returns nil if no task title is available or generation fails.
    private func generateCompletionSummary(from taskTitle: String?) async -> String? {
        guard let taskTitle = taskTitle, !taskTitle.isEmpty else {
            log("📝 No task title for completion summary")
            return nil
        }
        let summary = await TaskSummaryService.shared.generateCompletionMessage(for: taskTitle)
        log("📝 Completion summary: \(summary ?? "nil")")
        return summary
    }

    // MARK: - Buffered Debug Logging

    /// Buffer for log entries — not observed by SwiftUI, so appends here are free.
    @ObservationIgnored private var logBuffer: [String] = []
    /// Whether a flush is already scheduled.
    @ObservationIgnored private var logFlushScheduled = false
    /// Interval between buffer flushes (seconds).
    @ObservationIgnored private let logFlushInterval: TimeInterval = 0.5

    private func log(_ msg: String) {
        let entry = "[\(Date().formatted(.dateTime.hour().minute().second()))] \(msg)"
        print(entry)
        logBuffer.append(entry)
        scheduleLogFlush()
    }

    /// Schedule a single coalesced flush of buffered log entries to the observable `debugLog`.
    private func scheduleLogFlush() {
        guard !logFlushScheduled else { return }
        logFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + logFlushInterval) { [weak self] in
            self?.flushLogBuffer()
        }
    }

    /// Move all buffered entries into the observable `debugLog` in one batch.
    func flushLogBuffer() {
        logFlushScheduled = false
        guard !logBuffer.isEmpty else { return }
        debugLog.append(contentsOf: logBuffer)
        logBuffer.removeAll()
    }

    // MARK: - Actions

    func connect() {
        log("connect() called")

        // Restore chat history from disk on first launch
        if messages.isEmpty {
            messages = LocalStorage.loadMessages()
            if !messages.isEmpty {
                log("Restored \(messages.count) messages from disk")
            }
        }

        let config = ConnectionConfig()
        log("config — url=\(config.gatewayURL) tokenLen=\(config.token.count) session=\(config.sessionKey) configured=\(config.isConfigured)")
        guard config.isConfigured else {
            log("Not configured — showing settings")
            showSettings = true
            return
        }

        chatService?.disconnect()

        let service = ChatService(
            gatewayURL: config.effectiveGatewayURL,
            token: config.token,
            sessionKey: config.sessionKey
        )
        service.delegate = self
        self.chatService = service
        service.connect()
        log("ChatService.connect() called")
    }

    func reconnect() {
        log("reconnect()")
        chatService?.disconnect()
        chatService = nil
        isConnected = false
        connect()
    }

    func send() {
        log("send() — isConnected=\(isConnected) isLoading=\(isLoading)")
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        hasPlayedResponseHaptic = false
        hasReceivedAnyDelta = false
        responseHaptic.prepare()

        messages.append(Message(role: .user, content: text))
        inputText = ""
        isLoading = true

        // Start a fresh activity tracker for this agent turn
        currentActivity = AgentActivity()
        currentActivity?.currentLabel = "Thinking..."
        shimmerStartTime = Date()
        
        // Increment generation counter and capture start time to filter old items
        currentRunGeneration += 1
        currentRunStartTime = Date()
        log("Starting new run generation \(currentRunGeneration) at \(currentRunStartTime!)")
        
        // Clear history parsing state for new run
        seenThinkingIds.removeAll()
        seenToolCallIds.removeAll()
        seenToolResultIds.removeAll()
        toolCallMetadata.removeAll()
        resetLiveActivityState()
        log("shimmer started — label=\"Thinking...\"")

        messages.append(Message(role: .assistant, content: ""))

        LocalStorage.saveMessages(messages)

        // Start the Live Activity immediately (subject will be updated when ready)
        let agentName = botName
        LiveActivityManager.shared.startActivity(agentName: agentName, userTask: text, subject: nil)

        // Generate AI summary for every message sent
        // Include up to the last 5 user messages to identify the overall task
        let recentUserMessages = Array(messages
            .filter { $0.role == .user }
            .suffix(5)
            .map { $0.content })
        log("📝 Generating summary for \(recentUserMessages.count) messages: \(recentUserMessages)")
        Task {
            let summary = await TaskSummaryService.shared.generateTitle(for: recentUserMessages)
            await MainActor.run {
                self.log("📝 Summary result: \(summary ?? "nil")")
                self.liveActivitySubject = summary
                // Update the Live Activity with the generated subject
                self.pushLiveActivityUpdate(isAISubject: true)
            }
        }

        chatService?.send(text: text)
        log("chatService.send() called")
    }

    func clearMessages() {
        messages.removeAll()
        LocalStorage.deleteMessages()
        log("Chat history cleared")
    }

    // MARK: - ChatServiceDelegate (main chat session)

    func chatServiceDidConnect() {
        log("CONNECTED")
        isConnected = true
        
        // Workspace sync disabled - identity/profile are updated via tool events
        // when the agent writes to IDENTITY.md or USER.md
        log("Using cached identity: \(botIdentity.name)")
        
        // If we reconnected while a run was active, restart polling
        if isLoading {
            log("🔄 Reconnected during active run — restarting history polling")
            chatService?.restartHistoryPolling()
        }
    }

    func chatServiceDidDisconnect() {
        log("DISCONNECTED")
        isConnected = false
    }

    func chatServiceDidReceiveDelta(_ text: String) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        messages[lastIndex].content += text
        hasReceivedAnyDelta = true

        // Light haptic on the first streaming delta of a response
        if !hasPlayedResponseHaptic {
            hasPlayedResponseHaptic = true
            responseHaptic.impactOccurred()
            log("💬 Assistant responding")
            
            // Clear thinking steps immediately when answer starts streaming
            if currentActivity != nil {
                currentActivity?.finishCurrentSteps()
                lastCompletedActivity = currentActivity
                currentActivity = nil
                shimmerStartTime = nil
                // End the Lock Screen Live Activity now that the answer is streaming
                let taskTitle = liveActivitySubject
                Task {
                    let completionSummary = await generateCompletionSummary(from: taskTitle)
                    await MainActor.run {
                        LiveActivityManager.shared.endActivity(completionSummary: completionSummary)
                    }
                }
                log("Cleared activity on first delta")
            }
        }

        // Don't hide the shimmer here — for long agentic tasks the agent alternates
        // between emitting text and using tools. The shimmer and inline steps stay
        // visible until the turn finishes (chatServiceDidFinishMessage).
    }

    func chatServiceDidFinishMessage() {
        log("message.done - isLoading was \(isLoading)")
        
        // Force isLoading false
        isLoading = false
        hasPlayedResponseHaptic = false
        
        log("Set isLoading=false, hasPlayedResponseHaptic=false, hasReceivedAnyDelta=\(hasReceivedAnyDelta)")

        // Mark all remaining in-progress steps as completed
        currentActivity?.finishCurrentSteps()

        // Preserve the activity for the detail card, then clear the shimmer
        if let activity = currentActivity {
            lastCompletedActivity = activity
            log("Preserved activity with \(activity.steps.count) steps")
        }
        
        // End the Lock Screen Live Activity with completion summary
        let taskTitle = liveActivitySubject
        Task {
            let completionSummary = await generateCompletionSummary(from: taskTitle)
            await MainActor.run {
                LiveActivityManager.shared.endActivity(completionSummary: completionSummary)
            }
        }

        // Clear current activity to prevent late history items from appearing
        currentActivity = nil
        shimmerStartTime = nil
        log("Cleared currentActivity for generation \(currentRunGeneration), isLoading=\(isLoading)")

        // If the assistant message is still empty, remove it to avoid a blank bubble.
        // BUT: if no deltas were received, the response might still come via a late
        // history poll. Request one final fetch and defer cleanup.
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            if hasReceivedAnyDelta {
                messages.remove(at: lastIndex)
                log("Removed empty assistant message bubble")
            } else {
                // No response received at all. Do one final history fetch to
                // catch error messages or fast responses the polling missed.
                log("No deltas received — requesting final history fetch")
                let gen = currentRunGeneration
                chatService?.fetchRecentHistory(limit: 10)
                // Safety: remove the empty bubble after 3s if nothing fills it
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                    guard let self, self.currentRunGeneration == gen else { return }
                    if let lastIdx = self.messages.indices.last,
                       self.messages[lastIdx].role == .assistant,
                       self.messages[lastIdx].content.isEmpty {
                        self.messages.remove(at: lastIdx)
                        self.log("Removed empty assistant bubble (final fetch timeout)")
                        LocalStorage.saveMessages(self.messages)
                    }
                }
            }
        }
        
        LocalStorage.saveMessages(messages)
    }

    func chatServiceDidReceiveError(_ error: Error) {
        log("ERROR: \(error.localizedDescription)")
        let friendlyMessage = Self.friendlyErrorMessage(for: error)
        if let lastIndex = messages.indices.last,
           messages[lastIndex].role == .assistant,
           messages[lastIndex].content.isEmpty {
            messages[lastIndex].content = friendlyMessage
        }
        isLoading = false
        currentActivity = nil
        LiveActivityManager.shared.endActivity()
        LocalStorage.saveMessages(messages)
    }

    /// Map raw system errors into short, human-friendly messages.
    private static func friendlyErrorMessage(for error: Error) -> String {
        // Handle our own gateway errors directly
        if let chatError = error as? ChatServiceError {
            switch chatError {
            case .invalidURL:
                return "Couldn't connect — the server address looks wrong. Check your settings."
            case .gatewayError(let msg):
                return "Something went wrong: \(msg)"
            }
        }

        let nsError = error as NSError

        // POSIX network errors (NSPOSIXErrorDomain)
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case 53, 54, 57: // connection abort, reset, not connected
                return "Connection lost — reconnecting automatically. Try sending your message again in a moment."
            case 60: // operation timed out
                return "The connection timed out. Check your network and try again."
            case 61: // connection refused
                return "Couldn't reach the server. Make sure it's running and try again."
            default:
                return "A network error occurred. Reconnecting..."
            }
        }

        // URLSession / NSURLErrorDomain
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
                return "You're offline. Connect to the internet and try again."
            case NSURLErrorTimedOut:
                return "The request timed out. Check your connection and try again."
            case NSURLErrorNetworkConnectionLost:
                return "Connection lost — reconnecting automatically. Try again in a moment."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
                return "Couldn't find the server. Check the address in settings."
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                return "Couldn't establish a secure connection to the server."
            default:
                return "A connection error occurred. Reconnecting..."
            }
        }

        // Fallback
        return "Something went wrong. Reconnecting..."
    }

    func chatServiceDidLog(_ message: String) {
        log("WS: \(message)")
    }

    func chatServiceDidReceiveThinkingDelta(_ text: String) {
        log("🧠 Thinking delta: \(text.count) chars")
        
        if currentActivity == nil {
            log("Creating new currentActivity for thinking")
            currentActivity = AgentActivity()
        }
        currentActivity?.thinkingText += text
        currentActivity?.currentLabel = "Thinking..."

        // Add or update the thinking step — if the last step is already a thinking
        // step, append to it; otherwise mark previous steps complete and start a new one.
        if let lastStep = currentActivity?.steps.last, lastStep.type == .thinking, lastStep.status == .inProgress {
            currentActivity?.steps[currentActivity!.steps.count - 1].detail += text
        } else {
            currentActivity?.finishCurrentSteps()
            currentActivity?.steps.append(
                ActivityStep(type: .thinking, label: "Thinking", detail: text, toolCategory: .thinking)
            )
        }

        // Update the Live Activity on the Lock Screen
        LiveActivityManager.shared.updateIntent("Thinking...")
    }

    func chatServiceDidReceiveToolEvent(name: String, path: String?, args: [String: Any]?) {
        log("🔧 Tool event received: \(name) path: \(path ?? "nil")")
        
        if currentActivity == nil {
            log("Creating new currentActivity for tool event")
            currentActivity = AgentActivity()
        }

        // Mark all previous in-progress steps as completed before adding the new one
        currentActivity?.finishCurrentSteps()

        // Build a human-readable label from the tool name + args
        let label = Self.friendlyLabel(for: name, path: path, args: args)
        let detail = Self.detailString(for: name, path: path, args: args)

        log("Setting shimmer label: '\(label)'")
        currentActivity?.currentLabel = label
        currentActivity?.steps.append(
            ActivityStep(type: .toolCall, label: label, detail: detail)
        )
        log("Activity now has \(currentActivity?.steps.count ?? 0) total steps (\(currentActivity?.completedSteps.count ?? 0) completed)")

        // Update the Live Activity on the Lock Screen
        LiveActivityManager.shared.updateIntent(label)
    }

    // MARK: - Friendly Tool Labels

    /// Map a raw tool name + args into a short, human-readable status line.
    private static func friendlyLabel(for name: String, path: String?, args: [String: Any]?) -> String {
        let fileName = path.map { ($0 as NSString).lastPathComponent }

        switch name {
        // File tools
        case "write", "apply_patch":
            return "Writing \(fileName ?? "file")..."
        case "read":
            return "Reading \(fileName ?? "file")..."
        case "edit":
            return "Editing \(fileName ?? "file")..."
        case "search":
            if let query = args?["query"] as? String, !query.isEmpty {
                let short = query.count > 30 ? String(query.prefix(30)) + "..." : query
                return "Searching for \"\(short)\"..."
            }
            return "Searching files..."

        // Shell / exec
        case "bash", "exec":
            if let cmd = args?["command"] as? String, !cmd.isEmpty {
                let short = cmd.count > 30 ? String(cmd.prefix(30)) + "..." : cmd
                return "Running: \(short)"
            }
            return "Running a command..."

        // Browser / web
        case "browser", "browser.search", "web", "web.search":
            if let query = args?["query"] as? String, !query.isEmpty {
                let short = query.count > 30 ? String(query.prefix(30)) + "..." : query
                return "Searching the web for \"\(short)\"..."
            }
            if let url = args?["url"] as? String, !url.isEmpty {
                return "Browsing the web..."
            }
            return "Searching the web..."
        case "browser.click":
            return "Navigating a webpage..."
        case "browser.fill":
            return "Filling out a form..."
        case "browser.navigate":
            return "Opening a webpage..."

        // Agent / task tools
        case "llm_task":
            return "Running a sub-task..."
        case "agent_send":
            return "Coordinating with another agent..."
        case "message":
            return "Sending a message..."

        // Session tools
        case "sessions_list", "sessions_read":
            return "Checking sessions..."

        // Canvas
        case "canvas":
            return "Working on canvas..."

        // Fallback
        default:
            if let fileName {
                return "\(name) \(fileName)..."
            }
            return "Using \(name)..."
        }
    }

    /// Build a detail string for the activity card (path, URL, or command).
    private static func detailString(for name: String, path: String?, args: [String: Any]?) -> String {
        if let path, !path.isEmpty { return path }
        if let url = args?["url"] as? String, !url.isEmpty { return url }
        if let query = args?["query"] as? String, !query.isEmpty { return query }
        if let cmd = args?["command"] as? String, !cmd.isEmpty { return cmd }
        return ""
    }

    func chatServiceDidUpdateBotIdentity(_ identity: BotIdentity) {
        log("Bot identity updated via tool event — name=\(identity.name)")
        self.botIdentity = identity
        LocalStorage.saveBotIdentity(identity)
    }

    func chatServiceDidUpdateUserProfile(_ profile: UserProfile) {
        log("User profile updated via tool event — name=\(profile.name)")
        self.userProfile = profile
        LocalStorage.saveUserProfile(profile)
    }

    func chatServiceDidReceiveHistoryMessages(_ messages: [[String: Any]]) {
        log("Processing \(messages.count) new history items for generation \(currentRunGeneration)")
        
        if currentActivity != nil {
            // Normal case: activity is running, process items for thinking/tool steps
            for item in messages {
                processHistoryItem(item)
            }
        } else if !isLoading {
            // Post-run: catch responses/errors that polling missed (fast runs).
            // Scan assistant messages from the current run for content or errorMessage.
            for item in messages {
                guard let role = item["role"] as? String, role == "assistant" else { continue }
                
                // Filter by timestamp to only show items from the current run
                if let startTime = currentRunStartTime,
                   let timestampMs = item["timestamp"] as? Double {
                    let itemDate = Date(timeIntervalSince1970: timestampMs / 1000.0)
                    if itemDate < startTime.addingTimeInterval(-10) { continue }
                }
                
                // Check for error message first
                if let errorMsg = item["errorMessage"] as? String, !errorMsg.isEmpty {
                    log("📨 Found error in post-run history: \(errorMsg)")
                    applyPostRunText("Error: \(errorMsg)")
                    return
                }
                
                // Check for normal text content (fast response without streaming)
                if let contentArray = item["content"] as? [[String: Any]] {
                    let textParts = contentArray.compactMap { block -> String? in
                        guard block["type"] as? String == "text" else { return nil }
                        return block["text"] as? String
                    }
                    let joined = textParts.joined()
                    if !joined.isEmpty {
                        log("📨 Found response in post-run history (\(joined.count) chars)")
                        applyPostRunText(joined)
                        return
                    }
                }
            }
        } else {
            log("⚠️ Discarding history items (no activity, still loading)")
        }
    }

    /// Apply text to the assistant bubble after the run has finished.
    /// Used when a final history fetch finds a response that polling missed.
    private func applyPostRunText(_ text: String) {
        if let lastIndex = self.messages.indices.last,
           self.messages[lastIndex].role == .assistant,
           self.messages[lastIndex].content.isEmpty {
            self.messages[lastIndex].content = text
        } else if self.messages.last?.role != .assistant {
            self.messages.append(Message(role: .assistant, content: text))
        } else {
            // Bubble already has content — don't overwrite
            log("📨 Skipping post-run text (bubble already has content)")
            return
        }
        if !hasPlayedResponseHaptic {
            hasPlayedResponseHaptic = true
            responseHaptic.impactOccurred()
        }
        LocalStorage.saveMessages(self.messages)
    }

    /// Parse a single history item and update activity
    private func processHistoryItem(_ item: [String: Any]) {
        guard let role = item["role"] as? String else {
            log("⚠️ History item missing 'role' field, keys: \(Array(item.keys))")
            return
        }
        
        // Filter out items from before this run started (with 10 second buffer for clock skew)
        if let startTime = currentRunStartTime,
           let timestampMs = item["timestamp"] as? Double {
            let itemDate = Date(timeIntervalSince1970: timestampMs / 1000.0)
            // Allow items up to 10 seconds before run start (accounts for clock skew)
            let bufferTime = startTime.addingTimeInterval(-10)
            if itemDate < bufferTime {
                log("⏰ Skipping old item: itemDate=\(itemDate) bufferTime=\(bufferTime)")
                return
            }
        }
        
        // Accumulate usage/cost data if present at the item level
        if let usage = item["usage"] as? [String: Any] {
            if let cost = usage["cost"] as? [String: Any],
               let total = cost["total"] as? Double, total > 0 {
                liveActivityCostAccumulator += total
                liveActivityCost = String(format: "$%.3f", liveActivityCostAccumulator)
                log("💰 Cost accumulated: \(liveActivityCost!) (+\(total))")
            }
        }

        log("📋 Processing history item: role=\(role)")
        
        switch role {
        case "assistant":
            // Check for error messages from the gateway/provider
            if let errorMessage = item["errorMessage"] as? String, !errorMessage.isEmpty {
                log("❌ History: assistant error - \(errorMessage)")
                // Show error in the chat if the current response is empty
                if let lastIndex = messages.indices.last,
                   messages[lastIndex].role == .assistant,
                   messages[lastIndex].content.isEmpty {
                    messages[lastIndex].content = "Error: \(errorMessage)"
                    LocalStorage.saveMessages(messages)
                }
                return
            }
            
            // Assistant messages contain content arrays with thinking and toolCall items
            if let contentArray = item["content"] as? [[String: Any]] {
                log("📝 Assistant message with \(contentArray.count) content items")
                for contentItem in contentArray {
                    processAssistantContentItem(contentItem)
                }
            }
            
        case "toolResult":
            // Tool completion - look up metadata and show completion line
            processToolResultItem(item)
            
        case "user":
            // User messages - we already have these in our local message list
            // Skip silently
            break
            
        default:
            log("⚠️ History: unknown role '\(role)' - item keys: \(Array(item.keys))")
            break
        }
    }
    
    /// Process individual content items from assistant messages (thinking, toolCall)
    private func processAssistantContentItem(_ contentItem: [String: Any]) {
        guard let type = contentItem["type"] as? String else {
            log("⚠️ Content item missing 'type' field, keys: \(Array(contentItem.keys))")
            return
        }
        
        log("🔍 Content item type: \(type)")
        
        switch type {
        case "thinking":
            processThinkingContent(contentItem)
            
        case "toolCall":
            processToolCallContent(contentItem)
            
        default:
            // text, image, etc - ignore for activity tracking
            log("⚠️ Skipping content type: \(type)")
            break
        }
    }
    
    /// Process thinking content items
    private func processThinkingContent(_ contentItem: [String: Any]) {
        log("🧠 processThinkingContent called")
        guard let thinking = contentItem["thinking"] as? String else {
            log("⚠️ No 'thinking' field in content item")
            return
        }
        
        log("🧠 Raw thinking text: \(thinking)")
        
        // Strip markdown ** and trim
        let cleanText = thinking
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanText.isEmpty else {
            log("⚠️ Clean thinking text is empty")
            return
        }
        
        log("🧠 Clean thinking text: \(cleanText)")
        
        // Dedupe by thinkingSignature.id if available, else use hash
        var thinkingId: String?
        if let sigString = contentItem["thinkingSignature"] as? String,
           let sigData = sigString.data(using: .utf8),
           let sig = try? JSONSerialization.jsonObject(with: sigData) as? [String: Any],
           let id = sig["id"] as? String {
            thinkingId = id
            log("🧠 Extracted thinkingId from signature: \(id)")
        } else if let sig = contentItem["thinkingSignature"] as? [String: Any],
                  let id = sig["id"] as? String {
            thinkingId = id
            log("🧠 Extracted thinkingId from dict: \(id)")
        } else {
            thinkingId = String(cleanText.hashValue)
            log("🧠 Using hash as thinkingId: \(thinkingId!)")
        }
        
        if let id = thinkingId, !seenThinkingIds.contains(id) {
            seenThinkingIds.insert(id)

            // Prefer the summary field if the gateway provides it
            let summary = contentItem["summary"] as? String
            let intentLabel = summary ?? cleanText
            log("💭 Thinking: \(intentLabel)")

            // Mark previous steps (including tool calls) as completed
            currentActivity?.finishCurrentSteps()
            
            // Show as one-line progress
            currentActivity?.currentLabel = intentLabel + "..."
            currentActivity?.steps.append(
                ActivityStep(type: .thinking, label: intentLabel, detail: "", toolCategory: .thinking)
            )

            // Update the Live Activity -- thinking steps shift the intent stack AND update bottom
            shiftThinkingIntent(intentLabel)
            liveActivityBottomText = intentLabel + "..."
            liveActivityCurrentIcon = ToolCategory.thinking.iconName
            liveActivityStepNumber = (currentActivity?.steps.count ?? 0)
            pushLiveActivityUpdate()
        } else {
            log("⚠️ Thinking already seen, skipping: \(thinkingId ?? "nil")")
        }
    }
    
    /// Process toolCall content items
    private func processToolCallContent(_ contentItem: [String: Any]) {
        log("🔧 processToolCallContent called")
        guard let toolCallId = contentItem["id"] as? String,
              let toolName = contentItem["name"] as? String else {
            log("⚠️ Missing id or name in toolCall content: \(Array(contentItem.keys))")
            return
        }
        
        log("🔧 Tool call id=\(toolCallId) name=\(toolName)")
        
        // Skip if already seen
        guard !seenToolCallIds.contains(toolCallId) else {
            log("⚠️ Tool call already seen, skipping")
            return
        }
        seenToolCallIds.insert(toolCallId)
        
        let arguments = contentItem["arguments"] as? [String: Any] ?? [:]
        
        // Derive intent and category from tool call
        let intent = deriveIntentFromToolCall(name: toolName, arguments: arguments)
        
        // Store metadata for later use when toolResult arrives
        toolCallMetadata[toolCallId] = ToolCallMeta(
            toolName: toolName,
            arguments: arguments,
            derivedIntent: intent.label,
            category: intent.category
        )
        
        log("🔧 Tool call: \(intent.label) [\(intent.category.rawValue)]")
        
        // Show intent as progress
        currentActivity?.finishCurrentSteps()
        currentActivity?.currentLabel = intent.label
        currentActivity?.steps.append(
            ActivityStep(type: .toolCall, label: intent.label, detail: "", toolCategory: intent.category)
        )

        // Update the Live Activity -- tool events only update the bottom row
        liveActivityBottomText = intent.label
        liveActivityCurrentIcon = intent.category.iconName
        liveActivityStepNumber = (currentActivity?.steps.count ?? 0)
        pushLiveActivityUpdate()
    }
    
    /// Process toolResult items to show completion
    private func processToolResultItem(_ item: [String: Any]) {
        guard let toolCallId = item["toolCallId"] as? String else {
            return
        }
        
        // Accumulate cost from toolResult usage if present
        if let usage = item["usage"] as? [String: Any],
           let cost = usage["cost"] as? [String: Any],
           let total = cost["total"] as? Double, total > 0 {
            liveActivityCostAccumulator += total
            liveActivityCost = String(format: "$%.3f", liveActivityCostAccumulator)
        }

        // Always mark in-progress steps (including the matching tool call) as completed
        currentActivity?.finishCurrentSteps()

        // Skip adding a completion step if we already processed this result
        guard !seenToolResultIds.contains(toolCallId) else {
            return
        }
        seenToolResultIds.insert(toolCallId)
        
        let details = item["details"] as? [String: Any]
        let duration = details?["durationMs"] as? Int ?? 0
        let exitCode = details?["exitCode"] as? Int ?? 0
        let isError = item["isError"] as? Bool ?? false
        let toolName = item["toolName"] as? String ?? "Tool"
        
        // Build completion label
        let completionLabel: String
        if isError || exitCode != 0 {
            completionLabel = "Command failed"
        } else if let meta = toolCallMetadata[toolCallId] {
            let baseIntent = meta.derivedIntent.replacingOccurrences(of: "...", with: "")
            completionLabel = "\(baseIntent) (\(duration)ms)"
        } else {
            completionLabel = "\(toolName) completed (\(duration)ms)"
        }
        
        log("✅ Tool result: \(completionLabel)")
        
        // Add completion step with same category as the original tool call
        let category = toolCallMetadata[toolCallId]?.category ?? .generic
        currentActivity?.steps.append(
            ActivityStep(type: .toolCall, label: completionLabel, detail: "", status: .completed, toolCategory: category)
        )
    }

    /// Result of classifying a tool call — provides both a display label and category for icon selection.
    private struct ToolIntent {
        let label: String
        let category: ToolCategory
    }

    /// Derive a user-friendly intent description and category from a tool call.
    private func deriveIntentFromToolCall(name: String, arguments: [String: Any]) -> ToolIntent {
        let lowName = name.lowercased()

        // ── exec / bash / shell: inspect the command string ──
        if lowName == "exec" || lowName == "bash" || lowName.hasPrefix("shell") {
            guard let command = arguments["command"] as? String else {
                return ToolIntent(label: "Running a command...", category: .terminal)
            }

            // Browser commands (agent-browser open '...')
            if command.contains("agent-browser") {
                let query = extractBrowserQuery(command)
                if let q = query {
                    return ToolIntent(label: "Searching \"\(q)\"...", category: .browser)
                }
                let url = extractBrowserURL(command)
                if let u = url {
                    let host = hostFromURL(u)
                    return ToolIntent(label: "Browsing \(host)...", category: .browser)
                }
                return ToolIntent(label: "Using browser...", category: .browser)
            }

            // Network requests
            if command.contains("curl") || command.contains("wget") || command.contains("http") {
                let host = extractHostFromCurl(command)
                if let h = host {
                    return ToolIntent(label: "Fetching from \(h)...", category: .network)
                }
                return ToolIntent(label: "Fetching data...", category: .network)
            }

            // File redirects (cat >> file.txt, echo > file.txt)
            if let filename = extractFilenameFromRedirect(command) {
                if command.contains(">>") {
                    return ToolIntent(label: "Appending to \(filename)...", category: .fileSystem)
                } else {
                    return ToolIntent(label: "Writing \(filename)...", category: .fileSystem)
                }
            }

            // File reads
            if command.hasPrefix("cat ") && !command.contains(">") {
                let parts = command.split(separator: " ")
                if parts.count >= 2 {
                    let filename = (String(parts[1]) as NSString).lastPathComponent
                    return ToolIntent(label: "Reading \(filename)...", category: .fileSystem)
                }
            }

            // Git
            if command.contains("git ") {
                return ToolIntent(label: "Running git...", category: .terminal)
            }

            // Search tools (grep, rg, find)
            if command.hasPrefix("grep ") || command.hasPrefix("rg ") || command.hasPrefix("find ") {
                return ToolIntent(label: "Searching files...", category: .search)
            }

            // ls, pwd, etc.
            if command.hasPrefix("ls") || command.hasPrefix("pwd") || command.hasPrefix("stat ") {
                return ToolIntent(label: "Checking files...", category: .fileSystem)
            }

            // mkdir, cp, mv, rm
            if command.hasPrefix("mkdir ") || command.hasPrefix("cp ") ||
               command.hasPrefix("mv ") || command.hasPrefix("rm ") {
                return ToolIntent(label: "Managing files...", category: .fileSystem)
            }

            return ToolIntent(label: "Running a command...", category: .terminal)
        }

        // ── Direct tool names (non-exec wrappers) ──

        // File I/O
        if lowName == "read" || lowName.hasPrefix("fs.read") || lowName.hasPrefix("file_read") {
            if let path = arguments["path"] as? String {
                let filename = (path as NSString).lastPathComponent
                return ToolIntent(label: "Reading \(filename)...", category: .fileSystem)
            }
            return ToolIntent(label: "Reading file...", category: .fileSystem)
        }

        if lowName == "write" || lowName.hasPrefix("fs.write") || lowName.hasPrefix("file_write") {
            if let path = arguments["path"] as? String {
                let filename = (path as NSString).lastPathComponent
                return ToolIntent(label: "Writing \(filename)...", category: .fileSystem)
            }
            return ToolIntent(label: "Writing file...", category: .fileSystem)
        }

        if lowName.hasPrefix("fs.") {
            return ToolIntent(label: "Updating files...", category: .fileSystem)
        }

        // Browser
        if lowName.hasPrefix("browser") || lowName == "web" || lowName == "web_browse" {
            if let query = arguments["query"] as? String, !query.isEmpty {
                return ToolIntent(label: "Searching \"\(query)\"...", category: .browser)
            }
            if let url = arguments["url"] as? String, !url.isEmpty {
                let host = hostFromURL(url)
                return ToolIntent(label: "Browsing \(host)...", category: .browser)
            }
            return ToolIntent(label: "Using browser...", category: .browser)
        }

        // Network / HTTP
        if lowName == "web_fetch" || lowName.hasPrefix("http") || lowName == "fetch" {
            if let url = arguments["url"] as? String, !url.isEmpty {
                let host = hostFromURL(url)
                return ToolIntent(label: "Fetching \(host)...", category: .network)
            }
            return ToolIntent(label: "Fetching data...", category: .network)
        }

        // Search
        if lowName == "search" || lowName.hasPrefix("vector") || lowName == "grep" || lowName == "find" {
            if let query = arguments["query"] as? String, !query.isEmpty {
                return ToolIntent(label: "Searching \"\(query)\"...", category: .search)
            }
            return ToolIntent(label: "Searching...", category: .search)
        }

        // Fallback
        return ToolIntent(label: "Using \(name)...", category: .generic)
    }

    // MARK: - URL / Command Parsing Helpers

    /// Extract a search query from an agent-browser command (e.g. DuckDuckGo q= parameter).
    private func extractBrowserQuery(_ command: String) -> String? {
        // Match ?q=... or &q=... in URLs
        guard let range = command.range(of: #"[?&]q=([^&'\"]+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(command[range])
        let query = match.dropFirst(3) // drop "?q=" or "&q="
        return query
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespaces)
    }

    /// Extract the URL from an agent-browser open command.
    private func extractBrowserURL(_ command: String) -> String? {
        guard let range = command.range(of: #"https?://[^\s'\"]+|'https?://[^']+'"#, options: .regularExpression) else {
            return nil
        }
        return String(command[range]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
    }

    /// Extract host from a curl/wget command URL.
    private func extractHostFromCurl(_ command: String) -> String? {
        guard let url = command.range(of: #"https?://[^\s'\"]+|'https?://[^']+'"#, options: .regularExpression) else {
            return nil
        }
        let urlStr = String(command[url]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return hostFromURL(urlStr)
    }

    /// Extract just the hostname from a URL string (e.g. "api.open-meteo.com").
    private func hostFromURL(_ urlString: String) -> String {
        if let components = URLComponents(string: urlString), let host = components.host {
            return host
        }
        return urlString
    }
    
    /// Extract filename from shell redirect (>> or >)
    private func extractFilenameFromRedirect(_ command: String) -> String? {
        let patterns = [#">>\s*([^\s\n]+)"#, #">\s*([^\s\n]+)"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)),
               let range = Range(match.range(at: 1), in: command) {
                let filename = String(command[range])
                // Return just the filename, not the full path
                return (filename as NSString).lastPathComponent
            }
        }
        return nil
    }
    
    /// Extract content from history item (handles various formats)
    private func extractContent(from item: [String: Any]) -> String? {
        if let content = item["content"] as? String {
            return content
        }
        if let text = item["text"] as? String {
            return text
        }
        // Handle structured content blocks
        if let blocks = item["content"] as? [[String: Any]] {
            let texts = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            return texts.joined()
        }
        return nil
    }

    // MARK: - Workspace Data Management

    /// Save workspace data to local cache (used by Settings save).
    func saveWorkspaceData(identity: BotIdentity, profile: UserProfile) {
        self.botIdentity = identity
        self.userProfile = profile
        LocalStorage.saveBotIdentity(identity)
        LocalStorage.saveUserProfile(profile)
        log("Settings saved to local cache")
    }
}
