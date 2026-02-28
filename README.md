# Chowder for iOS

> We are working on a suit of **AI-first patterns** that we believe should be common in mobile chat interfaces. We're starting with Live Activity and thinking steps; we're also planning new ways to input speech, add context and media from the keyboard, use location, and more so chat UIs feel native and transparent instead of opaque.

[hello@newmaterial.co](mailto:hello@newmaterial.co) · **Website:** [newmaterial.co](https://newmaterial.co) · **Follow:** [Chowder on X](https://x.com/chowderhaus) **Discord:** [Chowder on Discord](https://discord.gg/6XruHYx83G)

🚧 *This repo is very early work in progress. We’d love feedback and contributions, please be kind.*

<img width="2141" height="650" alt="Chowder_Banner" src="https://github.com/user-attachments/assets/d90ffa74-371a-415e-9aed-a1d3771d70af" />

**Chowder** is an native iOS chat client that works with [OpenClaw](https://docs.openclaw.ai) leveraging our toolkit. You can talk to your personal AI assistant from your iPhone or iPad over an OpenClaw gateway, using the same sessions and routing as WhatsApp, Telegram, Discord, and other OpenClaw channels. Below is the Chowder + OpenClaw setup and how it works.

## Chowder — iOS client for OpenClaw

Chowder connects to an OpenClaw gateway over WebSocket and implements the first of these — streaming, Live Activity and thinking steps, identity sync, workspace-aware settings — against the OpenClaw Gateway Protocol.


https://github.com/user-attachments/assets/5af73b21-0ec1-4804-8a40-39dbd2f10adb


## Features

- **Real-time chat** with streaming AI responses via WebSocket
- **Persistent chat history** stored locally (survives app kill/relaunch)
- **Agent identity sync** -- dynamically mirrors the bot's IDENTITY.md (name, creature, vibe, emoji) and USER.md (what the bot knows about you) from the OpenClaw workspace
- **Live activity tracking** -- while the agent works, Chowder polls `chat.history` and displays inline thinking steps and tool activity directly in the chat. Each step appears with a light haptic tap and fades out when the answer starts streaming. Examples:
  - "Considering web search options..."
  - "Fetching data..." / "Appending to weather.txt..."
  - "exec completed (859ms)"
- **Custom agent avatar** -- pick a profile photo for the agent from your photo library
- **Settings sync** -- edit the bot's identity or your user profile in Settings and the changes are written back to the OpenClaw workspace files
- **Automatic reconnection** with 3-second backoff after network interruptions
- **Debug log** -- tap the header to view raw WebSocket traffic for troubleshooting
- **Demo mode** -- in Settings, you can run a demo (e.g. Live Activity) to try UI interactions without connecting to OpenClaw

## Prerequisites

- **Mac mini (or any macOS/Linux host)** running OpenClaw gateway
- **Tailscale** installed on both the gateway host and the iOS device (same tailnet), **or** a **Cloudflare Tunnel** (`cloudflared`) exposing the gateway with **Cloudflare Access** protecting it via service token (see step 3b below)
- **Xcode 15+** on a Mac to build and install Chowder
- **iOS 17+** on the target device

> Note: For higher-quality local task/completion summaries in the Live Activity and chat header, enable Apple Intelligence on the iOS device (Settings > Apple Intelligence & Siri). If unavailable or disabled, summaries may be less polished.

## Architecture

```
iPhone (Chowder)                Mac mini (Gateway)
      |                               |
      |  ws://<tailscale-ip>:18789    |
      |------------------------------>|
      |  connect.challenge (nonce)    |
      |<------------------------------|
      |  connect (auth + client info) |
      |------------------------------>|
      |  hello-ok (protocol 3)       |
      |<------------------------------|
      |                               |
      |  /verbose on (invisible)      |  --> enables tool summaries
      |------------------------------>|
      |  sync: read IDENTITY/USER.md  |  --> agent reads workspace files
      |------------------------------>|
      |  chat.final (sync response)   |  --> parsed into BotIdentity/UserProfile
      |<------------------------------|
      |                               |
      |  chat.send (user message)     |  --> Pi agent (RPC)
      |------------------------------>|
      |  agent/lifecycle (phase:start)|  --> start polling chat.history
      |<------------------------------|
      |  chat.history polling (500ms) |  --> extract thinking + toolCall from content[]
      |------------------------------>|
      |  assistant content arrays     |  --> "Appending to weather.txt...", "Updated weather.txt (13ms)"
      |<------------------------------|
      |  agent/assistant (text deltas)|  --> streamed into chat bubble
      |<------------------------------|
      |  agent/lifecycle (phase:end)  |  --> stop polling, message complete
      |<------------------------------|
      |  chat.final (full response)   |
      |<------------------------------|
```

Chowder connects as an `openclaw-ios` / `ui` mode operator client using the OpenClaw Gateway Protocol v3. On connect, it silently enables verbose mode and syncs the agent's workspace files to populate the header name and cached identity/profile data.

## Setup Guide

### 1. Install and Start OpenClaw on the Mac mini

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

The onboarding wizard will generate a gateway token and install the gateway as a background service.

### 2. Configure the Gateway for Tailscale Access

The gateway needs to listen on the Tailscale network interface so your iPhone can reach it. Edit `~/.openclaw/openclaw.json` on the Mac mini:

```json
{
  "gateway": {
    "bind": "tailnet",
    "auth": {
      "mode": "token",
      "token": "your-gateway-token"
    }
  }
}
```

Then restart the gateway:

```bash
openclaw gateway restart
```

Verify it's running:

```bash
openclaw gateway status
openclaw doctor
```

### 3. Install Tailscale on Both Devices

- **Mac mini**: Install Tailscale from [tailscale.com](https://tailscale.com) and sign in
- **iPhone**: Install the Tailscale app from the App Store and sign in to the same tailnet

Confirm connectivity by finding the Mac mini's Tailscale IP:

```bash
# On the Mac mini:
tailscale ip -4
# Example output: 100.104.164.27
```

### 3b. (Alternative) Expose the Gateway via Cloudflare Tunnel + Access

Instead of Tailscale, you can expose the gateway publicly using a **Cloudflare Tunnel** (`cloudflared`) and protect it with **Cloudflare Access** (part of the Zero Trust platform) using a service token for machine-to-machine authentication.

**On the gateway host:**

1. Install and authenticate `cloudflared`:
   ```bash
   brew install cloudflare/cloudflare/cloudflared
   cloudflared tunnel login
   ```
2. Create a tunnel and route it to the gateway:
   ```bash
   cloudflared tunnel create my-gateway
   cloudflared tunnel route dns my-gateway gateway.yourdomain.com
   ```
3. Configure the tunnel to forward to the local gateway port (`~/.cloudflared/config.yml`):
   ```yaml
   tunnel: <tunnel-id>
   credentials-file: ~/.cloudflared/<tunnel-id>.json
   ingress:
     - hostname: gateway.yourdomain.com
       service: http://localhost:18789
     - service: http_status:404
   ```
4. Start the tunnel: `cloudflared tunnel run my-gateway`

**In the Cloudflare Zero Trust dashboard:**

1. Go to **Access → Applications** and create an application for `gateway.yourdomain.com`
2. Add a **Service Auth** policy (not Allow) and attach a service token to it
3. Go to **Access → Service Auth → Service Tokens** and create a token — copy the **Client ID** and **Client Secret**

The gateway URL to use in Chowder will be `wss://gateway.yourdomain.com` (port 443, no explicit port needed).

### 4. Find Your Gateway Token

The gateway token was generated during onboarding. To find it:

```bash
openclaw config get gateway.auth.token
```

Or generate a new one:

```bash
openclaw doctor --generate-gateway-token
```

### 5. Build and Install Chowder

```bash
git clone <this-repo>
cd chowder-iOS/Chowder
open Chowder.xcodeproj
```

In Xcode:
1. Select your iPhone as the build target
2. Update the signing team in the project settings
3. Build and run (Cmd+R)

### 6. Configure Chowder on Your iPhone

1. Open Chowder -- the Settings sheet appears on first launch
2. *(Optional)* To try UI interactions without OpenClaw, use the **demo** in Settings (e.g. Live Activity demo) — no gateway or token required.
3. Fill in the fields:
   - **Gateway**: `ws://<tailscale-ip>:18789` (e.g. `ws://100.104.164.27:18789`), or `wss://gateway.yourdomain.com` if using Cloudflare Zero Trust
   - **Token**: paste the gateway token from step 4
   - **Session**: leave as `agent:main:main` (default) or change to target a specific agent
   - **Cloudflare Zero Trust** *(optional)*: enable the toggle and paste the **Client ID** and **Client Secret** of your service token (from step 3b). These are sent as `CF-Access-Client-ID` / `CF-Access-Client-Secret` headers during the WebSocket upgrade and stored securely in the Keychain.
4. Tap **Save**

Chowder will connect to the gateway, complete the WebSocket handshake, and show **Online** in the header.

## How It Works

### Connection Flow

1. Chowder opens a WebSocket to the gateway
2. The gateway sends a `connect.challenge` with a nonce
3. Chowder responds with a `connect` request containing:
   - Protocol version (v3)
   - Client identity (`openclaw-ios` / `ui` mode)
   - Auth token
   - Operator role and scopes
4. The gateway validates and returns `hello-ok`
5. Chowder silently sends `/verbose on` to enable tool call summaries
6. Chowder sends an invisible sync request asking the bot to read IDENTITY.md and USER.md
7. The response is parsed to populate `BotIdentity` (header name, creature, vibe) and `UserProfile`

### Workspace Sync

Chowder dynamically mirrors the bot's workspace files -- it never hardcodes identity values. On connect, it asks the bot to read `IDENTITY.md` and `USER.md` and return their contents in a delimiter-based format. The response is parsed into structured Swift models (`BotIdentity`, `UserProfile`) and cached locally via `LocalStorage`. When the user edits these in Settings, the changes are written back to the workspace via a chat-driven write request.

### Real-Time Activity Tracking

Chowder polls `chat.history` every 500ms while the agent is running (from `lifecycle:start` to `lifecycle:end`). Each history response returns the most recent messages, which Chowder parses to extract activity and show progress to the user.

#### History Item Schema

The gateway returns two relevant item types:

**Assistant messages** (`role: "assistant"`) contain a `content` array with typed entries:

```json
{
  "role": "assistant",
  "timestamp": 1770929371188,
  "stopReason": "toolUse",
  "content": [
    {
      "type": "thinking",
      "thinking": "**Appending weather summary to file**",
      "thinkingSignature": "{\"id\":\"rs_...\", ...}"
    },
    {
      "type": "toolCall",
      "name": "exec",
      "id": "call_...|fc_...",
      "arguments": { "command": "curl -s ...", "timeout": 120 }
    }
  ]
}
```

**Tool result messages** (`role: "toolResult"`) contain completion details:

```json
{
  "role": "toolResult",
  "toolName": "exec",
  "toolCallId": "call_...|fc_...",
  "isError": false,
  "timestamp": 1770929374921,
  "details": {
    "exitCode": 0,
    "durationMs": 859,
    "status": "completed",
    "cwd": "/Users/.../.openclaw/workspace"
  },
  "content": [{ "type": "text", "text": "..." }]
}
```

Assistant messages may also include an `errorMessage` field when the provider returns an error (e.g., quota exceeded). Chowder detects these and surfaces them in the chat.

#### What Gets Extracted

- **Thinking items** (`type: "thinking"`): The `thinking` field contains a short summary (often wrapped in markdown `**`). Chowder strips the formatting and displays it as a one-line progress label (e.g., "Appending weather summary to file..."). Deduplication uses `thinkingSignature.id` parsed from the JSON string in `thinkingSignature`.

- **Tool calls** (`type: "toolCall"`): The `name` and `arguments` fields are used to derive a user-friendly intent. For `exec` calls, the `command` argument is parsed to detect file operations (e.g., `cat >> weather.txt` becomes "Appending to weather.txt..."), web fetches (`curl` becomes "Fetching data..."), and other patterns. Tool call metadata is stored by `id` for later use when the result arrives.

- **Tool results** (`role: "toolResult"`): Matched to the original tool call via `toolCallId`. Shows completion with timing (e.g., "Updated weather.txt (859ms)") and detects errors via `isError` and `exitCode`.

#### Deduplication

History responses return the last N items each poll, so most items repeat. Chowder deduplicates using:

- `thinkingSignature.id` for thinking items (falls back to content hash)
- `toolCallId` for both tool calls and tool results
- `role + timestamp` combination as a last resort for assistant messages
- A request-in-flight flag prevents concurrent poll requests

#### Timestamp Filtering

Items from previous tasks are filtered by comparing the item's `timestamp` (Unix milliseconds from the gateway) against the local `currentRunStartTime`. A 10-second buffer accounts for clock skew between the iOS device and the gateway host.

#### Lifecycle

Activity steps are cleared from the UI as soon as the first streaming delta arrives (the assistant starts responding). This keeps the transition clean -- thinking steps fade out in 150ms and the streamed answer appears below. If the run ends without any response (e.g., provider error), the empty assistant bubble is removed.

### Sending Messages

Messages are sent as `chat.send` requests with an idempotency key. The gateway acks immediately with a `runId`, then streams the AI response as `agent` events:

- `agent` / `stream: "assistant"` -- text deltas (incremental tokens)
- `agent` / `stream: "lifecycle"` -- start/end of agent run
- `chat` / `state: "delta"` -- verbose tool summaries (parsed for shimmer)
- `chat` / `state: "final"` -- complete message with full text

### Reconnection

Chowder automatically reconnects after network interruptions with a 3-second backoff.

## Troubleshooting

### "Not connected" / stays Offline

- Verify Tailscale is connected on both devices: `tailscale status`
- Confirm the gateway is running: `openclaw gateway status`
- Check the gateway URL includes `ws://` (not `http://`)
- Try pinging the Mac mini's Tailscale IP from the iPhone

### Connection drops immediately

- Verify the token matches: `openclaw config get gateway.auth.token`
- Check gateway logs for rejection reasons: `openclaw logs --follow`

### Connected but no AI response

- Check model auth: `openclaw models status`
- Ensure an API key or OAuth token is configured for your model provider
- Try sending a message from the CLI to verify the agent works: `openclaw agent --message "hello"`

### "INVALID_REQUEST: missing scope: operator.write" (or `operator.read`)

This usually means the gateway accepted the WebSocket connection, but the current session/token was not granted the required operator scopes for RPC methods like `chat.send` and `chat.history`.

- Common after recent OpenClaw upgrades (including `v2026.2.25+`) where gateway auth/pairing checks are stricter
- Not typically an iOS UI bug or message-format issue

Fix steps on the gateway host:

1. Confirm your token and gateway auth mode:
   - `openclaw config get gateway.auth.mode`
   - `openclaw config get gateway.auth.token`
2. Reissue/rotate the gateway token, then update the token in Chowder Settings:
   - `openclaw doctor --generate-gateway-token`
3. If you use device/operator pairing, re-pair the iOS device/session after the upgrade.
4. Restart the gateway:
   - `openclaw gateway restart`
5. Watch logs while reconnecting from iOS:
   - `openclaw logs --follow`

Expected result after fix:

- `chat.send` no longer returns `missing scope: operator.write`
- `chat.history` no longer returns `missing scope: operator.read`

### Header shows "Chowder" instead of the bot's name

- The bot's IDENTITY.md may be empty. Tell the bot to fill it in: "Set your name to OddJob in IDENTITY.md"
- Check the debug log for `Synced IDENTITY.md` or `Sync response could not be parsed` messages

### "Error: You exceeded your current quota"

- This is a provider-side error (e.g., OpenAI billing limit)
- Check your API key balance at [platform.openai.com](https://platform.openai.com)
- Complex agent tasks (browsing, multi-step tool use) can consume 200K+ tokens per run
- Chowder will surface the error message in the chat instead of showing a blank bubble

### Thinking steps not appearing

- Open the debug log (tap the header) and look for `📋 Processing history item` entries
- If you see `⏰ Skipping old item`, there may be clock skew between your iPhone and the gateway host -- the app allows a 10-second buffer but larger drift can cause filtering
- If you see `"Filtered: X by toolCallId, Y by timestamp → 0 new items"` every poll, all items are from a previous run
- If the agent responds very quickly (simple questions), there may not be any thinking or tool steps to show

### Cloudflare Zero Trust — connection hangs or gets a 302 redirect

If the WebSocket connection hangs at "waiting for didOpen" or `curl` returns a `302` redirect to `cloudflareaccess.com`:

- **Check `service_token_status` in the redirect JWT**: decode the `meta` query param — if `"service_token_status": false`, Cloudflare didn't accept the token
- **Verify the Access policy**: the application must have a **Service Auth** policy (not an Allow policy) with the service token explicitly allowed. Identity-based policies (email, IdP groups) do not accept service tokens.
- **Verify the credentials**: go to **Access → Service Auth → Service Tokens** and confirm the Client ID and Secret match what's in Chowder. Regenerating a token invalidates the old secret.
- **Check the port**: Cloudflare only proxies standard HTTPS ports. Use `wss://gateway.yourdomain.com` (port 443) — not `wss://gateway.yourdomain.com:18789`.

### Gateway not reachable over Tailscale

- Ensure `gateway.bind` is set to `"tailnet"` (not `"loopback"`)
- Restart the gateway after config changes: `openclaw gateway restart`
- Check that the gateway port (18789) is not blocked

## Project Structure

```
Chowder/
  ChowderApp.swift              -- App entry point
  Models/
    AgentActivity.swift          -- Thinking/tool step tracking for shimmer
    BotIdentity.swift            -- Parsed IDENTITY.md model + markdown serialization
    ConnectionConfig.swift       -- Gateway URL, token, session key, and Cloudflare Zero Trust credentials (Keychain)
    Message.swift                -- Chat message model (Codable, persisted)
    UserProfile.swift            -- Parsed USER.md model + markdown serialization
  Services/
    ChatService.swift            -- WebSocket connection, protocol handling, chat.history polling
    KeychainService.swift        -- Secure token storage
    LocalStorage.swift           -- File-based persistence (messages, avatar, identity, profile)
  ViewModels/
    ChatViewModel.swift          -- Chat state, history parsing, activity tracking, shimmer logic
  Views/
    ActivityStepRow.swift        -- Compact inline row for completed thinking/tool steps
    AgentActivityCard.swift      -- Detail card showing all thinking/tool steps
    ChatView.swift               -- Main chat screen with shimmer + activity card
    ChatHeaderView.swift         -- Header with dynamic bot name + online/offline
    MessageBubbleView.swift      -- Message bubble with markdown rendering
    SettingsView.swift           -- Gateway config, identity/profile editing, avatar picker
    ThinkingShimmerView.swift    -- Animated "Thinking..." / tool status shimmer line
```

## OpenClaw Protocol Reference

- [Gateway Protocol](https://docs.openclaw.ai/gateway/protocol) -- WebSocket framing and handshake
- [Thinking Levels](https://docs.openclaw.ai/tools/thinking) -- `/verbose`, `/think`, `/reasoning` directives
- [Agent Loop](https://docs.openclaw.ai/concepts/agent-loop) -- How the agent processes messages
- [Tailscale Setup](https://docs.openclaw.ai/gateway/tailscale) -- Network access via Tailscale
- [Configuration](https://docs.openclaw.ai/gateway/configuration) -- All gateway config keys

## License

MIT
