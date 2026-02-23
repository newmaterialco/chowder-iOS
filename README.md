# Chowder for iOS

> We are working on a suit of **AI-first patterns** that we believe should be common in mobile chat interfaces. We're starting with Live Activity and thinking steps; we're also planning new ways to input speech, add context and media from the keyboard, use location, and more so chat UIs feel native and transparent instead of opaque.

[hello@newmaterial.co](mailto:hello@newmaterial.co) · **Website:** [newmaterial.co](https://newmaterial.co) · **Follow:** [New Material on X](https://x.com/newmaterialco)

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

- **A server** running OpenClaw gateway (Mac mini, cloud VM, etc.)
- **A domain name** pointing to the server (for TLS)
- **Caddy** (or another reverse proxy) for automatic HTTPS
- **Xcode 15+** on a Mac to build and install Chowder
- **iOS 17+** on the target device

## Architecture

```
iPhone (Chowder)                  Server (Reverse Proxy + Gateway)
      |                                     |
      |  wss://your-domain.com              |
      |------------------------------------>|  Caddy terminates TLS
      |  connect.challenge (nonce)          |
      |<------------------------------------|
      |  connect (auth + client info)       |
      |------------------------------------>|
      |  hello-ok (protocol 3)             |
      |<------------------------------------|
      |                                     |
      |  /verbose on (invisible)            |  --> enables tool summaries
      |------------------------------------>|
      |  sync: read IDENTITY/USER.md        |  --> agent reads workspace files
      |------------------------------------>|
      |  chat.final (sync response)         |  --> parsed into BotIdentity/UserProfile
      |<------------------------------------|
      |                                     |
      |  chat.send (user message)           |  --> Pi agent (RPC)
      |------------------------------------>|
      |  agent/lifecycle (phase:start)      |  --> start polling chat.history
      |<------------------------------------|
      |  chat.history polling (500ms)       |  --> extract thinking + toolCall from content[]
      |------------------------------------>|
      |  assistant content arrays           |  --> "Appending to weather.txt...", "Updated weather.txt (13ms)"
      |<------------------------------------|
      |  agent/assistant (text deltas)      |  --> streamed into chat bubble
      |<------------------------------------|
      |  agent/lifecycle (phase:end)        |  --> stop polling, message complete
      |<------------------------------------|
      |  chat.final (full response)         |
      |<------------------------------------|
```

Chowder connects as an `openclaw-ios` / `ui` mode operator client using the OpenClaw Gateway Protocol v3 over WSS (WebSocket Secure). A reverse proxy (Caddy) handles TLS termination with automatic Let's Encrypt certificates. On connect, Chowder silently enables verbose mode and syncs the agent's workspace files to populate the header name and cached identity/profile data.

## Setup Guide

### 1. Install and Start OpenClaw on the Server

```bash
npm install -g openclaw@latest
openclaw onboard --install-daemon
```

The onboarding wizard will generate a gateway token and install the gateway as a background service.

### 2. Configure the Gateway

The gateway binds to localhost — the reverse proxy handles public-facing connections. Edit `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "bind": "loopback",
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

### 3. Set Up the Reverse Proxy (Caddy)

[Caddy](https://caddyserver.com) provides automatic HTTPS via Let's Encrypt with zero configuration. Install it on your server:

```bash
# macOS
brew install caddy

# Ubuntu/Debian
sudo apt install -y caddy

# Or download from https://caddyserver.com/download
```

Create a `Caddyfile`:

```
your-domain.com {
    reverse_proxy localhost:18789
}
```

Start Caddy:

```bash
caddy start
```

Caddy will automatically obtain and renew TLS certificates. Ensure your domain's DNS points to the server's public IP and port 443 is open.

#### Alternative: Cloudflare Tunnel (No Open Ports)

If you can't open ports or don't have a static IP, use [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/):

```bash
# Install cloudflared
brew install cloudflared  # or see https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/

# Quick tunnel (temporary URL)
cloudflared tunnel --url http://localhost:18789

# Or set up a persistent tunnel with your domain
cloudflared tunnel create chowder
```

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

1. Open Chowder — the Settings sheet appears on first launch
2. *(Optional)* To try UI interactions without OpenClaw, use the **demo** in Settings (e.g. Live Activity demo) — no gateway or token required.
3. Fill in the fields:
   - **Server URL**: `wss://your-domain.com` (or `ws://localhost:18789` for local development)
   - **Token**: paste the gateway token from step 4
   - **Session**: leave as `agent:main:main` (default) or change to target a specific agent
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

- Confirm the gateway is running: `openclaw gateway status`
- Check the server URL uses `wss://` (not `http://`)
- Verify your domain resolves correctly: `nslookup your-domain.com`
- Check that Caddy is running and certificates are valid: `caddy validate`

### Connection drops immediately

- Verify the token matches: `openclaw config get gateway.auth.token`
- Check gateway logs for rejection reasons: `openclaw logs --follow`
- Check Caddy logs for TLS or proxy errors

### TLS / certificate errors

- Ensure your domain DNS points to the correct IP
- Check that port 443 is open on your server
- Verify Caddy obtained certificates: `caddy list-certs`
- If using Cloudflare Tunnel, check `cloudflared tunnel info`

### Connected but no AI response

- Check model auth: `openclaw models status`
- Ensure an API key or OAuth token is configured for your model provider
- Try sending a message from the CLI to verify the agent works: `openclaw agent --message "hello"`

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

### Local development with ws://

- For local development, `ws://localhost:18789` works without TLS
- Set `gateway.bind` to `"loopback"` in `openclaw.json`
- The app allows local networking via ATS exceptions

## Project Structure

```
Chowder/
  ChowderApp.swift              -- App entry point
  Models/
    AgentActivity.swift          -- Thinking/tool step tracking for shimmer
    BotIdentity.swift            -- Parsed IDENTITY.md model + markdown serialization
    ConnectionConfig.swift       -- Gateway URL, token, session key storage
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

## Security

- **Transport**: All remote connections use WSS (WebSocket over TLS). Certificates are issued automatically by Let's Encrypt via Caddy.
- **Authentication**: Token-based auth via the OpenClaw Gateway Protocol handshake. Tokens are stored in the iOS Keychain.
- **ATS**: App Transport Security enforces TLS for remote connections. Local networking (`ws://localhost`) is allowed for development.
- **No custom certificate trust**: Unlike the Tailscale-based setup, this version relies entirely on the system trust chain with CA-signed certificates.

## OpenClaw Protocol Reference

- [Gateway Protocol](https://docs.openclaw.ai/gateway/protocol) -- WebSocket framing and handshake
- [Thinking Levels](https://docs.openclaw.ai/tools/thinking) -- `/verbose`, `/think`, `/reasoning` directives
- [Agent Loop](https://docs.openclaw.ai/concepts/agent-loop) -- How the agent processes messages
- [Configuration](https://docs.openclaw.ai/gateway/configuration) -- All gateway config keys

## License

MIT
