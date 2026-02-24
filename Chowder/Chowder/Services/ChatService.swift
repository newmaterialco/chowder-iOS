import Foundation

protocol ChatServiceDelegate: AnyObject {
    func chatServiceDidConnect()
    func chatServiceDidDisconnect()
    func chatServiceDidReceiveDelta(_ text: String)
    func chatServiceDidFinishMessage()
    func chatServiceDidReceiveError(_ error: Error)
    func chatServiceDidLog(_ message: String)
    func chatServiceDidReceiveThinkingDelta(_ text: String)
    func chatServiceDidReceiveToolEvent(name: String, path: String?, args: [String: Any]?)
    func chatServiceDidUpdateBotIdentity(_ identity: BotIdentity)
    func chatServiceDidUpdateUserProfile(_ profile: UserProfile)
    func chatServiceDidReceiveHistoryMessages(_ messages: [[String: Any]])
}

final class ChatService: NSObject {

    weak var delegate: ChatServiceDelegate?

    private let gatewayURL: String
    private let token: String
    private let sessionKey: String
    private let clientId = "openclaw-ios"
    private let clientMode = "ui"
    private let role = "operator"
    private let scopes = ["operator.read", "operator.write"]

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var shouldReconnect = true
    private var isReconnecting = false
    private var hasSentConnectRequest = false

    /// Monotonically increasing request ID counter.
    private var nextRequestId: Int = 1

    /// Active agent run tracking for history polling
    private var activeRunId: String?
    private var historyPollTimer: Timer?
    private var historyRequestInFlight: Bool = false  // Prevent concurrent polling
    private var seenSequenceNumbers: Set<Int> = []
    private var seenToolCallIds: Set<String> = []  // Dedupe by toolCallId
    private var seenTimestamps: Set<String> = []   // Fallback dedupe by timestamp
    private let historyPollInterval: TimeInterval = 1.0  // 1 second

    init(gatewayURL: String, token: String, sessionKey: String = "agent:main:main") {
        self.gatewayURL = gatewayURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
        self.sessionKey = sessionKey

        super.init()
        log("[INIT] gatewayURL=\(self.gatewayURL) sessionKey=\(self.sessionKey) tokenLength=\(token.count)")
    }

    private func log(_ msg: String) {
        print("🔌 \(msg)")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.chatServiceDidLog(msg)
        }
    }

    /// Produce a one-line summary for incoming WebSocket frames instead of dumping raw JSON.
    /// Only logs important events (errors, lifecycle, connection) to reduce noise.
    private func logCompactRecv(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("[RECV] (unparseable \(text.count) chars)")
            return
        }
        let frameType = json["type"] as? String ?? "?"
        switch frameType {
        case "event":
            let event = json["event"] as? String ?? "?"
            let payload = json["payload"] as? [String: Any]
            
            // Skip noisy events entirely (tick, health, normal agent activity)
            if event == "tick" || event == "health" { return }
            if event == "agent" {
                let stream = payload?["stream"] as? String
                // Only log lifecycle events, skip thinking/assistant/tool (too noisy)
                if stream == "lifecycle" {
                    let phase = (payload?["data"] as? [String: Any])?["phase"] as? String
                    log("[RECV] lifecycle/\(phase ?? "?")")
                }
                return
            }
            
            // Log other events (chat, error, connect)
            let stream = (payload?["stream"] as? String).map { "/\($0)" } ?? ""
            let state = (payload?["state"] as? String).map { "/\($0)" } ?? ""
            log("[RECV] \(event)\(stream)\(state)")
        case "res":
            // Only log response errors, skip successful acks
            let ok = json["ok"] as? Bool ?? false
            if !ok {
                let id = json["id"] as? String ?? "?"
                log("[RECV] res error id=\(id)")
            }
        default:
            log("[RECV] \(frameType) (\(text.count) chars)")
        }
    }

    /// Generate a unique request ID for outbound `type:"req"` frames.
    private func makeRequestId() -> String {
        let id = nextRequestId
        nextRequestId += 1
        return "req-\(id)"
    }

    // MARK: - Connection

    func connect() {
        guard webSocketTask == nil else {
            log("[CONNECT] Skipped — webSocketTask already exists")
            return
        }
        shouldReconnect = true
        hasSentConnectRequest = false
        nextRequestId = 1

        // Build URL — only append ?client= if not already present
        let urlString: String
        if gatewayURL.contains("?") {
            urlString = gatewayURL
        } else {
            urlString = "\(gatewayURL)/?client=chowder-ios"
        }
        log("[CONNECT] Building URL from: \(urlString)")

        guard let url = URL(string: urlString) else {
            log("[CONNECT] ❌ Failed to create URL from: \(urlString)")
            delegate?.chatServiceDidReceiveError(ChatServiceError.invalidURL)
            return
        }

        log("[CONNECT] URL scheme=\(url.scheme ?? "nil") host=\(url.host ?? "nil") port=\(url.port ?? -1)")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.urlSession = session

        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        log("[CONNECT] Calling task.resume() ...")
        task.resume()
        log("[CONNECT] task.resume() called — waiting for didOpen")
    }

    func disconnect() {
        log("[DISCONNECT] Manual disconnect")
        shouldReconnect = false
        stopHistoryPolling()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
    }

    // MARK: - Sending Messages

    func send(text: String) {
        guard isConnected else {
            log("[SEND] ⚠️ Not connected — dropping message")
            return
        }

        let requestId = makeRequestId()
        let idempotencyKey = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.send",
            "params": [
                "message": text,
                "sessionKey": sessionKey,
                "idempotencyKey": idempotencyKey,
                "deliver": true
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        log("[SEND] Sending chat.send id=\(requestId) (\(text.count) chars)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[SEND] ❌ Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.delegate?.chatServiceDidReceiveError(error)
                }
            } else {
                self?.log("[SEND] ✅ chat.send sent OK")
            }
        }
    }

    /// Request chat history for the current session (for polling during active runs)
    private func requestChatHistory() {
        guard isConnected, activeRunId != nil, !historyRequestInFlight else {
            return
        }
        
        historyRequestInFlight = true
        let requestId = makeRequestId()
        log("[HISTORY] 🔄 Polling chat.history")
        
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": 10
            ]
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else {
            historyRequestInFlight = false
            return
        }
        
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[HISTORY] ❌ Error: \(error.localizedDescription)")
                self?.historyRequestInFlight = false
            }
        }
    }

    /// Start polling chat.history (no runId needed - gateway doesn't provide it)
    private func startHistoryPolling() {
        // Stop any existing timer
        stopHistoryPolling()
        
        activeRunId = "polling"  // Marker that polling is active
        historyRequestInFlight = false  // Reset in-flight flag (critical after reconnects)
        seenSequenceNumbers.removeAll()
        seenToolCallIds.removeAll()
        seenTimestamps.removeAll()
        
        log("[HISTORY] Starting poll (500ms interval)")
        
        // Poll immediately, then every 500ms
        requestChatHistory()
        
        historyPollTimer = Timer.scheduledTimer(
            withTimeInterval: historyPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.requestChatHistory()
        }
    }

    /// Restart polling after a reconnection during an active run.
    /// Called from the ViewModel when it detects isLoading is still true after reconnect.
    func restartHistoryPolling() {
        log("[HISTORY] 🔄 Restarting polling after reconnect")
        startHistoryPolling()
    }
    
    /// Stop polling chat.history
    private func stopHistoryPolling() {
        historyPollTimer?.invalidate()
        historyPollTimer = nil
        activeRunId = nil
        historyRequestInFlight = false  // Reset in-flight flag
        seenSequenceNumbers.removeAll()
        seenToolCallIds.removeAll()
        seenTimestamps.removeAll()
        log("[HISTORY] Stopped polling")
    }

    /// Fetch recent message history to get tool summary messages that verbose mode created.
    func fetchRecentHistory(limit: Int = 20) {
        guard isConnected else {
            log("[HISTORY] ⚠️ Not connected")
            return
        }

        let requestId = makeRequestId()
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "chat.history",
            "params": [
                "sessionKey": sessionKey,
                "limit": limit
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        log("[HISTORY] Requesting last \(limit) messages")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[HISTORY] ❌ Error: \(error.localizedDescription)")
            } else {
                self?.log("[HISTORY] ✅ Request sent")
            }
        }
    }

    // MARK: - Private: Connect Handshake

    /// Send the `connect` request after receiving the gateway's challenge nonce.
    /// Protocol: https://docs.openclaw.ai/gateway/protocol
    private func sendConnectRequest(nonce: String) {
        let authToken = DeviceIdentityService.loadDeviceToken() ?? token
        let authSource = authToken == token ? "gatewayToken" : "deviceToken"

        let identity: DeviceIdentity
        do {
            identity = try DeviceIdentityService.loadOrCreateIdentity()
        } catch {
            log("[AUTH] ❌ Failed to load/create device identity: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.chatServiceDidReceiveError(error)
            }
            return
        }

        let signedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        let signature: DeviceSignature
        do {
            signature = try DeviceIdentityService.signConnectPayload(
                identity: identity,
                clientId: clientId,
                clientMode: clientMode,
                role: role,
                scopes: scopes,
                signedAtMs: signedAtMs,
                token: authToken,
                nonce: nonce
            )
        } catch {
            log("[AUTH] ❌ Failed to sign device payload: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.chatServiceDidReceiveError(error)
            }
            return
        }

        let requestId = makeRequestId()
        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": clientId,
                    "version": "1.0.0",
                    "platform": "ios",
                    "mode": clientMode
                ],
                "role": role,
                "scopes": scopes,
                "auth": [
                    "token": authToken
                ],
                "device": [
                    "id": identity.id,
                    "publicKey": identity.publicKey,
                    "signature": signature.signature,
                    "signedAt": signature.signedAt,
                    "nonce": nonce
                ],
                "locale": Locale.current.identifier,
                "userAgent": "chowder-ios/1.0.0"
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: frame),
              let jsonString = String(data: data, encoding: .utf8) else {
            log("[AUTH] ❌ Failed to serialize connect request")
            return
        }

        log("[AUTH] Sending connect request id=\(requestId) auth=\(authSource) deviceId=\(identity.id.prefix(12))... signedAt=\(signedAtMs)")
        webSocketTask?.send(.string(jsonString)) { [weak self] error in
            if let error {
                self?.log("[AUTH] ❌ Error sending connect: \(error.localizedDescription)")
            } else {
                self?.log("[AUTH] ✅ Connect request sent — waiting for hello-ok")
            }
        }
    }

    // MARK: - Private: Receive Loop

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Compact log: just event type + stream (full payload available in Xcode console)
                    self.logCompactRecv(text)
                    self.handleIncomingMessage(text)
                case .data(let data):
                    self.log("[RECV] Data frame (\(data.count) bytes)")
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleIncomingMessage(text)
                    }
                @unknown default:
                    self.log("[RECV] ⚠️ Unknown frame type")
                }
                self.listenForMessages()

            case .failure(let error):
                let nsError = error as NSError
                self.log("[RECV] ❌ Error: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.delegate?.chatServiceDidDisconnect()
                    self.delegate?.chatServiceDidReceiveError(error)
                }
                // didCloseWith may not fire after some errors (e.g. code 53 connection abort),
                // so trigger reconnect here as a safety net.
                self.attemptReconnect()
            }
        }
    }

    // MARK: - Private: Message Routing

    private func handleIncomingMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log("[PARSE] ⚠️ Could not parse: \(String(text.prefix(200)))")
            return
        }

        // OpenClaw Gateway protocol uses three frame types:
        //   "event"  — server push   {"type":"event","event":"...","payload":{...}}
        //   "res"    — response       {"type":"res","id":"...","ok":true/false,"payload/error":{...}}
        //   "req"    — (server->client, rare)
        let frameType = json["type"] as? String ?? "unknown"

        switch frameType {
        case "event":
            handleEvent(json)
        case "res":
            handleResponse(json)
        default:
            log("[HANDLE] Unhandled frame type: \(frameType)")
        }
    }

    /// Handle `type:"event"` frames from the gateway.
    private func handleEvent(_ json: [String: Any]) {
        let event = json["event"] as? String ?? "unknown"
        let payload = json["payload"] as? [String: Any]

        // connect.challenge must be handled immediately (not on main queue)
        if event == "connect.challenge" {
            guard !hasSentConnectRequest else {
                log("[AUTH] ⚠️ Ignoring duplicate connect.challenge")
                return
            }
            let nonce = payload?["nonce"] as? String
            if let nonce {
                log("[AUTH] Received connect.challenge — nonce=\(nonce.prefix(8))...")
                hasSentConnectRequest = true
                sendConnectRequest(nonce: nonce)
            } else {
                log("[AUTH] ⚠️ connect.challenge missing nonce")
            }
            return
        }

        // Filter session-scoped events BEFORE dispatching to main — the gateway
        // broadcasts to ALL connected WebSocket clients, so skip events whose
        // sessionKey doesn't match ours. This avoids unnecessary main-thread work.
        let eventSessionKey = payload?["sessionKey"] as? String
        if (event == "agent" || event == "chat"),
           let eventSessionKey,
           eventSessionKey != self.sessionKey {
            // This event belongs to a different session — ignore it silently.
            return
        }

        // Skip periodic keepalive and health events before touching the main thread.
        if event == "tick" || event == "health" {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch event {

            // ── Agent streaming events (primary source for text deltas) ──
            // payload.stream = "assistant" | "lifecycle" | "tool" | "thinking" | ...
            // For "assistant": data.delta = incremental text, data.text = cumulative text
            case "agent":
                let stream = payload?["stream"] as? String
                let agentData = payload?["data"] as? [String: Any]
                switch stream {
                case "assistant":
                    // Use data.delta (incremental) — NOT data.text (cumulative)
                    if let delta = agentData?["delta"] as? String, !delta.isEmpty {
                        self.delegate?.chatServiceDidReceiveDelta(delta)
                    }

                case "thinking":
                    self.log("[HANDLE] 🧠 thinking event - delta length: \(agentData?["delta"] as? String ?? "")")
                    if let delta = agentData?["delta"] as? String, !delta.isEmpty {
                        self.delegate?.chatServiceDidReceiveThinkingDelta(delta)
                    }

                case "tool":
                    // Log full payload for debugging the exact structure
                    self.log("[HANDLE] 🔧 tool event data keys: \(Array((agentData ?? [:]).keys))")

                    // Try multiple possible field names for tool name and args
                    let toolName = agentData?["name"] as? String
                                ?? agentData?["toolName"] as? String
                                ?? agentData?["tool"] as? String
                                ?? "tool"
                    let args = agentData?["args"] as? [String: Any]
                             ?? agentData?["params"] as? [String: Any]
                             ?? agentData?["input"] as? [String: Any]
                    let path = args?["path"] as? String

                    self.log("[HANDLE] 🔧 tool: \(toolName) path: \(path ?? "nil")")

                    // Notify delegate about tool usage (for shimmer + inline steps display)
                    self.delegate?.chatServiceDidReceiveToolEvent(
                        name: toolName,
                        path: path,
                        args: args
                    )

                    // Detect writes to identity/user files (for workspace sync)
                    if toolName == "write",
                       let filePath = path,
                       let content = args?["content"] as? String {
                        if filePath.hasSuffix("IDENTITY.md") {
                            let identity = BotIdentity.from(markdown: content)
                            self.log("[SYNC] Detected write to IDENTITY.md — name=\(identity.name)")
                            self.delegate?.chatServiceDidUpdateBotIdentity(identity)
                        } else if filePath.hasSuffix("USER.md") {
                            let profile = UserProfile.from(markdown: content)
                            self.log("[SYNC] Detected write to USER.md — name=\(profile.name)")
                            self.delegate?.chatServiceDidUpdateUserProfile(profile)
                        }
                    }

                case "lifecycle":
                    let phase = agentData?["phase"] as? String
                    
                    if phase == "start" {
                        self.log("[HANDLE] 🚀 lifecycle start — starting polling")
                        self.startHistoryPolling()
                    } else if phase == "end" || phase == "done" {
                        self.log("[HANDLE] ✅ agent lifecycle: \(phase ?? "")")
                        self.stopHistoryPolling()
                        self.delegate?.chatServiceDidFinishMessage()
                    } else {
                        self.log("[HANDLE] ⚠️ lifecycle unknown phase: \(phase ?? "nil")")
                    }
                default:
                    break
                }

            // ── Chat events (used for error/abort only; deltas handled via agent events above) ──
            case "chat":
                let state = payload?["state"] as? String
                switch state {
                case "delta":
                    // Verbose mode tool summaries come as chat deltas with emoji prefix
                    // (e.g. "📄 read: IDENTITY.md") for OpenAI models that don't emit
                    // structured agent/tool events
                    if let message = payload?["message"] as? [String: Any],
                       let text = self.extractText(from: message),
                       !text.isEmpty {
                        let parsed = Self.parseVerboseToolSummary(text)
                        if let (toolName, toolPath) = parsed {
                            self.log("[HANDLE] 📋 verbose tool summary: \(toolName) \(toolPath ?? "")")
                            self.delegate?.chatServiceDidReceiveToolEvent(name: toolName, path: toolPath, args: nil)
                        }
                    }
                case "final":
                    // chat/final is a signal that the turn is complete.
                    // Payload is typically [runId, seq, sessionKey, state] — no message text.
                    self.log("[HANDLE] 📨 chat/final")
                case "aborted":
                    self.log("[HANDLE] ⚠️ chat aborted")
                    self.delegate?.chatServiceDidFinishMessage()
                case "error":
                    let msg = payload?["errorMessage"] as? String ?? "Chat error"
                    self.log("[HANDLE] ❌ Chat error: \(msg)")
                    self.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError(msg))
                default:
                    self.log("[HANDLE] chat state: \(state ?? "nil")")
                    break
                }

            case "error":
                let msg = payload?["message"] as? String ?? "Unknown gateway error"
                self.log("[HANDLE] ❌ Gateway error: \(msg)")
                self.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError(msg))

            default:
                self.log("[HANDLE] Event: \(event)")
            }
        }
    }

    /// Handle `type:"res"` frames (responses to our requests).
    private func handleResponse(_ json: [String: Any]) {
        let id = json["id"] as? String ?? "?"
        let ok = json["ok"] as? Bool ?? false
        let payload = json["payload"] as? [String: Any]
        let error = json["error"] as? [String: Any]

        if ok {
            let payloadType = payload?["type"] as? String

            if payloadType == "hello-ok" {
                let proto = payload?["protocol"] as? Int ?? 0
                log("[AUTH] ✅ hello-ok — protocol=\(proto) id=\(id)")
                if let auth = payload?["auth"] as? [String: Any],
                   let deviceToken = auth["deviceToken"] as? String,
                   !deviceToken.isEmpty {
                    DeviceIdentityService.saveDeviceToken(deviceToken)
                    log("[AUTH] Stored device token from hello-ok")
                }

                DispatchQueue.main.async { [weak self] in
                    self?.isConnected = true
                    self?.delegate?.chatServiceDidConnect()
                }
                return
            }

            // Handle chat.history response
            if payloadType == "chat-history" || payloadType == "history" {
                if let messages = payload?["messages"] as? [[String: Any]] {
                    self.log("[HISTORY] ✅ Received \(messages.count) history items")
                    // Log first few items for debugging
                    if messages.count > 0 {
                        self.log("[HISTORY] Sample item keys: \(Array(messages[0].keys))")
                        if let role = messages[0]["role"] as? String {
                            self.log("[HISTORY] First item role: \(role)")
                        }
                        if let runId = messages[0]["runId"] as? String {
                            self.log("[HISTORY] First item runId: \(runId)")
                        }
                    }
                    self.processHistoryItems(messages)
                } else {
                    self.log("[HISTORY] ⚠️ Response has no messages array")
                    self.log("[HISTORY] Payload keys: \(Array((payload ?? [:]).keys))")
                }
                return
            }

            // Check if this might be a history response without a type field
            if payload != nil {
                let payloadKeys = Array((payload ?? [:]).keys)
                log("[HANDLE] ✅ res ok id=\(id) payloadType=\(payloadType ?? "nil") payloadKeys=\(payloadKeys)")
                
                // Try to find messages array even without type field
                if let messages = payload?["messages"] as? [[String: Any]] {
                    self.log("[HISTORY] 🎯 Found messages array in response without type! Count: \(messages.count)")
                    if messages.count > 0 {
                        self.log("[HISTORY] First item keys: \(Array(messages[0].keys))")
                    }
                    self.processHistoryItems(messages)
                    return
                }
            } else {
                log("[HANDLE] ✅ res ok id=\(id) payloadType=\(payloadType ?? "nil") payload=nil")
            }
        } else {
            // Error response
            let code = error?["code"] as? String ?? "unknown"
            let message = error?["message"] as? String ?? json["error"] as? String ?? "Request failed"
            log("[HANDLE] ❌ res error id=\(id) code=\(code) message=\(message)")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.chatServiceDidReceiveError(ChatServiceError.gatewayError("\(code): \(message)"))
            }
        }
    }

    /// Process history items, deduplicate, and notify delegate of new activity
    private func processHistoryItems(_ items: [[String: Any]]) {
        // Reset request-in-flight flag to allow next poll
        historyRequestInFlight = false
        
        // Always forward items to delegate — they handle filtering.
        // (Previously we gated on activeRunId, but post-run fetches need to get through.)
        
        log("[HISTORY] Processing \(items.count) items")
        
        // Log first 2 items as full JSON for debugging
        for (index, item) in items.prefix(2).enumerated() {
            if let jsonData = try? JSONSerialization.data(withJSONObject: item, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                log("[HISTORY] Item[\(index)] JSON:\n\(jsonString)")
            }
        }
        
        var newItems: [[String: Any]] = []
        var filteredBySeq = 0
        var filteredByToolCallId = 0
        var filteredByTimestamp = 0
        
        for (index, item) in items.enumerated() {
            let itemRole = item["role"] as? String ?? "?"
            let itemSeq = item["seq"] as? Int
            let itemToolCallId = item["toolCallId"] as? String
            
            // Timestamp might be String or Number - try both
            var timestampStr: String? = nil
            if let ts = item["timestamp"] as? String {
                timestampStr = ts
            } else if let ts = item["timestamp"] as? Double {
                timestampStr = String(ts)
            } else if let ts = item["timestamp"] as? Int {
                timestampStr = String(ts)
            }
            
            // For assistant messages, use content hash for deduplication
            var contentHash: String? = nil
            if itemRole == "assistant", let content = item["content"] as? String {
                contentHash = String(content.prefix(100).hashValue)
            }
            
            // Log first few items for debugging
            if index < 3 {
                log("[HISTORY] Item[\(index)]: role=\(itemRole) toolCallId=\(itemToolCallId ?? "nil") timestamp=\(timestampStr?.prefix(20) ?? "nil") contentHash=\(contentHash ?? "nil")")
            }
            
            // Deduplicate by sequence number (if available)
            if let seq = itemSeq, seq > 0 {
                if seenSequenceNumbers.contains(seq) {
                    filteredBySeq += 1
                    continue
                }
                seenSequenceNumbers.insert(seq)
            }
            
            // Deduplicate by toolCallId (for toolResult items)
            if let toolCallId = itemToolCallId {
                if seenToolCallIds.contains(toolCallId) {
                    filteredByToolCallId += 1
                    continue
                }
                seenToolCallIds.insert(toolCallId)
            }
            
            // Deduplicate assistant messages by content hash
            if let hash = contentHash {
                if seenTimestamps.contains(hash) {
                    filteredByTimestamp += 1
                    continue
                }
                seenTimestamps.insert(hash)
            }
            
            // Deduplicate by timestamp as last resort
            if let timestamp = timestampStr {
                let key = "\(itemRole)_\(timestamp)"
                if seenTimestamps.contains(key) {
                    filteredByTimestamp += 1
                    continue
                }
                seenTimestamps.insert(key)
            }
            
            newItems.append(item)
        }
        
        log("[HISTORY] Filtered: \(filteredBySeq) by seq, \(filteredByToolCallId) by toolCallId, \(filteredByTimestamp) by timestamp → \(newItems.count) new items")
        
        if !newItems.isEmpty {
            log("[HISTORY] 📤 Sending \(newItems.count) new items to ViewModel")
            for (index, item) in newItems.prefix(3).enumerated() {
                let role = item["role"] as? String ?? "?"
                log("[HISTORY] New[\(index)]: role=\(role)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.chatServiceDidReceiveHistoryMessages(newItems)
            }
        } else {
            log("[HISTORY] No new items to send")
        }
    }

    // MARK: - Private: Text Extraction

    /// Extract displayable text from a message payload that could be:
    ///   - A plain String
    ///   - A dictionary with "text", "delta", or "content" key
    ///   - A structured message with content blocks [{type:"text", text:"..."}]
    private func extractText(from value: Any?) -> String? {
        if let str = value as? String, !str.isEmpty {
            return str
        }
        if let dict = value as? [String: Any] {
            if let t = dict["text"] as? String, !t.isEmpty { return t }
            if let d = dict["delta"] as? String, !d.isEmpty { return d }
            if let c = dict["content"] as? String, !c.isEmpty { return c }
            // Anthropic-style content blocks: [{type:"text", text:"..."}]
            if let blocks = dict["content"] as? [[String: Any]] {
                let texts = blocks.compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                let joined = texts.joined()
                return joined.isEmpty ? nil : joined
            }
        }
        return nil
    }

    // MARK: - Private: Verbose Tool Summary Parsing

    /// Known tool names the agent can use (matched case-insensitively).
    private static let knownTools: Set<String> = [
        "read", "write", "edit", "apply_patch", "search",
        "bash", "exec", "browser", "web", "canvas",
        "llm_task", "agent_send", "sessions_list",
        "sessions_read", "message"
    ]

    /// Try to parse a verbose tool summary like "📄 read: IDENTITY.md" or "🔧 bash: ls -la".
    /// Returns (toolName, path/arg?) or nil if the text isn't a tool summary.
    static func parseVerboseToolSummary(_ text: String) -> (String, String?)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Verbose tool summaries follow the pattern: <emoji> <toolName>: <arg>
        // The emoji is optional (1–2 Unicode scalars), then a known tool name, then ": ".
        var working = trimmed

        // Strip leading emoji (any character that is NOT alphanumeric or whitespace, up to 4 chars)
        while let first = working.unicodeScalars.first,
              !first.properties.isAlphabetic && !first.properties.isWhitespace,
              working.count > 1 {
            working = String(working.dropFirst())
        }
        working = working.trimmingCharacters(in: .whitespaces)

        // Now expect "toolName:" or "toolName: arg"
        guard let colonIndex = working.firstIndex(of: ":") else { return nil }
        let toolName = working[working.startIndex..<colonIndex]
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard knownTools.contains(toolName) else { return nil }

        let arg = working[working.index(after: colonIndex)...]
            .trimmingCharacters(in: .whitespaces)

        return (toolName, arg.isEmpty ? nil : arg)
    }

    // MARK: - Private: Reconnect

    private func attemptReconnect() {
        guard shouldReconnect, !isReconnecting else { return }
        isReconnecting = true
        log("[RECONNECT] Will retry in 3s ...")
        stopHistoryPolling()  // Stop polling timer before reconnecting
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.isReconnecting = false
            self?.log("[RECONNECT] Retrying now")
            self?.connect()
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ChatService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        log("[SOCKET] ✅ didOpen — protocol=\(`protocol` ?? "none")")
        // Only listen — do NOT send anything. Wait for the gateway's connect.challenge event.
        listenForMessages()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
        log("[SOCKET] ⚠️ didClose — code=\(closeCode.rawValue) reason=\(reasonStr)")
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
            self?.delegate?.chatServiceDidDisconnect()
        }
        attemptReconnect()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let nsError = error as NSError
            log("[SOCKET] ❌ didCompleteWithError: domain=\(nsError.domain) code=\(nsError.code) desc=\(nsError.localizedDescription)")
        }
    }

    // Trust Tailscale's .ts.net TLS certificates
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host
        log("[TLS] Challenge for host=\(host) method=\(challenge.protectionSpace.authenticationMethod)")

        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           host.hasSuffix(".ts.net"),
           let trust = challenge.protectionSpace.serverTrust {
            log("[TLS] Trusting .ts.net certificate for \(host)")
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }

}

// MARK: - Errors

enum ChatServiceError: LocalizedError {
    case invalidURL
    case gatewayError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid gateway URL."
        case .gatewayError(let msg): return msg
        }
    }
}
