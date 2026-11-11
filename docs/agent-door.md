# The agent door

A local API in mac4DSTEM and macTEM through which an agent on the same Mac (Claude, Codex, a script) looks at what the app's
windows show, and the MCP bridge that hands it to an agent. Read-only in this version.

## The pieces

- `ShellAgentDoor` (this package): the listener (Network.framework, 127.0.0.1 only), who may ask, the token and the connection command, the list of
  open windows, the routes, and the Settings section. It knows no app: an app registers its tools (`AgentTool`) and enrols each
  window with a one-line summary.
- The app: its tools (what a window holds, its pictures from the app's own export code), the preference that keeps the switch,
  and `com.apple.security.network.server` in its entitlements.
- `macem-mcp` (`AgentBridge/`): one binary for both apps, a copy per app (`--app macTEM`). It lists the door's tools as the door
  describes them and runs each as one GET, so a new tool needs no bridge change.

## Security

- Off by default. The switch is in the app's Settings > Agents and says what an agent can and cannot do.
- Listens on 127.0.0.1 with `acceptLocalOnly`: no other computer reaches it.
- A bearer token, 32 random bytes, made once and kept in the app's preferences until the person presses New Token (which shuts
  out every copy of the old). The person hands it to the bridge with Settings > Agents > Copy Connection Command, a
  `claude mcp add ... -e <APP>_AGENT_PORT=... -e <APP>_AGENT_TOKEN=... -- macem-mcp --app <App>` line pasted into Terminal once,
  as sandboxed Mac apps hand out an API key. Nothing is written for a helper to find: a sandboxed app's container is closed to
  other programs (macOS answers "Operation not permitted").
- The app's own port first (mac4DSTEM 47811, macTEM 47812), so the command stays good; another when it is taken, shown in the pane.
- A request with an `Origin` header (a web page) is refused, and so is one whose `Host` is not `127.0.0.1:<port>` or
  `localhost:<port>` (DNS rebinding). The token is compared in constant time.
- Every route is a GET; tools change nothing. One request per connection, headers capped at 16 KB, bodies at 1 MB, chunked
  bodies refused, at most 16 connections, each closed after 20 s.

## Routes

| Path | Answer |
|------|--------|
| `GET /v1` | the app, its version, the API version, the tools' names |
| `GET /v1/tools` | the tools in MCP's shape: name, title, description, input schema, read-only annotations |
| `GET /v1/tools/<name>?window=w1&scale=2` | one tool's answer: JSON, or a PNG; a refusal is `{"error": "..."}` with 404 (nothing yet), 409 (name a window) |

`list_windows` is the door's own tool. Windows are named `w1`, `w2`, ... in the order they opened; a name is never reused. A tool
that takes a window uses the only open one when none is named.

## Adding a tool (in an app)

```swift
door.register([
    AgentTool(name: "get_image", title: "Image", summary: "The displayed image as the app exports it.", input: .windowPicture) { call in
        guard let state = call.window?.state as? AppState else { return .refusal(status: 500, message: "Not a window.") }
        return AgentJSON.picture(state.exportImage(scale: call.scale))
    },
])
```

A picture comes from the code that exports it, never a second renderer, so what an agent judges is what the person sees.
