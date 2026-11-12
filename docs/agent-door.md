# The agent door

A local API in mac4DSTEM and macTEM through which an agent on the same Mac (Claude, Codex, a script) looks at what the app's
windows show. The app is the MCP server itself (MCP's Streamable HTTP transport at `/mcp`), so nothing is installed beside it
and the App Store build has the whole door. Tools look; a tool that acts runs only behind a second switch.

## The pieces

- `ShellAgentDoor` (this package): the listener (Network.framework, 127.0.0.1 only), who may ask, the token and the connection command, the list of
  open windows, the routes, and the Settings section. It knows no app: an app registers its tools (`AgentTool`) and enrols each
  window with a one-line summary.
- The app: its tools (what a window holds, its pictures from the app's own export code), the preference that keeps the switch,
  and `com.apple.security.network.server` in its entitlements.
- The agent: any MCP client that speaks Streamable HTTP. For Claude Code, Settings > Agents > Copy Connection Command copies
  `claude mcp add --transport http <app> http://127.0.0.1:<port>/mcp --header "Authorization: Bearer <token>"`, pasted into
  Terminal once.

## Connecting Codex

Codex (the ChatGPT desktop app, the Codex CLI and the IDE extension) reads its MCP servers from one file,
`~/.codex/config.toml`, so one entry serves all three. The door is a Streamable HTTP server with a bearer token, which Codex
takes from the config file, not from `codex mcp add` (that documents OAuth only). Settings > Agents > Copy Connection Command
gives the URL and the token; put them in the file by hand:

```toml
[mcp_servers.mac4dstem]
url = "http://127.0.0.1:47811/mcp"
http_headers = { "Authorization" = "Bearer <token from Settings > Agents>" }

[mcp_servers.macem]
url = "http://127.0.0.1:47812/mcp"
http_headers = { "Authorization" = "Bearer <token from Settings > Agents>" }
```

- The token sits in a file only this user reads, like an API key. `bearer_token_env_var = "MAC4DSTEM_TOKEN"` keeps it out of
  the file, but a Mac app started from the Dock does not see variables set in a shell profile, so the desktop app may not find
  it; the CLI started from Terminal does. New Token in the app shuts out the old line; paste the new one.
- If the port in Settings > Agents is not the app's own (another program held it), use the one shown there.
- Acting tools are marked `readOnlyHint: false`; `default_tools_approval_mode = "prompt"` makes Codex ask the person before
  each call, whatever the client's default.
- Codex compacts a tool's input schema above `tool_input_schema_max_bytes` (5,000 bytes by default); the door's largest
  schemas (`set_disk_detection`, `set_phase_mapping`) are the ones to check if a parameter goes missing.
- Not checked yet (MacEMUI#104): whether Codex hands the door's picture answers (MCP image content) to the model, and that it
  takes the door's plain JSON answers without an event stream. If pictures do not reach the model, the agent judges by
  numbers: `get_pattern_values`, `get_detected_disks`, `get_window`.

## Security

- Off by default. The switch is in the app's Settings > Agents and says what an agent can and cannot do.
- Listens on 127.0.0.1 with `acceptLocalOnly`: no other computer reaches it.
- A bearer token, 32 random bytes, made once and kept in the app's preferences until the person presses New Token (which shuts
  out every copy of the old). The person hands it to the agent with Settings > Agents > Copy Connection Command, as sandboxed
  Mac apps hand out an API key. Nothing is written for a helper to find: a sandboxed app's container is closed to other
  programs (macOS answers "Operation not permitted").
- The app's own port first (mac4DSTEM 47811, macTEM 47812), so the command stays good; another when it is taken, shown in the pane.
- A request with an `Origin` header (a web page) is refused, and so is one whose `Host` is not `127.0.0.1:<port>` or
  `localhost:<port>` (DNS rebinding). The token is compared in constant time.
- Tools that act (an app passes `acts: true`) change a window as its own controls do. They run only while the second switch
  ("Let agents run analyses", `AgentDoor.runsAllowed`, off by default) is on, only through `/mcp`, never from a GET, and only
  with inputs that pass their `AgentParameter` schema. MCP lists them with `readOnlyHint: false` and `destructiveHint: false`,
  so the agent's client asks the person before each call. The app keeps one run at a time (it refuses while busy), lets Stop
  cancel it, and never deletes or overwrites a file.
- The `/v1` routes are GETs and `/mcp` takes one JSON-RPC message per POST. One request per connection, headers capped at 16 KB, bodies at 1 MB, chunked
  bodies refused, at most 16 connections, each closed after 20 s.

## Routes

| Path | Answer |
|------|--------|
| `POST /mcp` | MCP, JSON-RPC 2.0, one message per request, one JSON answer: `initialize`, `ping`, `tools/list`, `tools/call` (a picture as image content, a refusal as a result with `isError`); a notification gets 202; `GET` is 405 (no event stream) |
| `GET /v1` | the app, its version, the API version, the tools' names |
| `GET /v1/tools` | the tools in MCP's shape: name, title, description, input schema (with each tool's parameters), annotations (read-only, or acting and not destructive) |
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

## App Store

The store build needs `com.apple.security.network.server` beside the sandbox (an app's store-entitlement check lists it), and
its review notes say what the listener is: loopback only, off by default, for AI agents the person runs on the same Mac. It
collects no data, so the privacy answers do not change.

## A tool that acts (in an app)

```swift
AgentTool(name: "run_disk_detection", title: "Run disk detection", summary: "Detects the Bragg disks ...", input: .window,
          parameters: [AgentParameter("threshold", .number(0...1), summary: "Correlation threshold.", required: true)],
          acts: true) { call in
    // call.arguments["threshold"] is checked text ("0.25"); start the run as the button does, refuse while busy.
}
```

The app sets `door.runsAllowed` from its own preference and passes `runs:` and `canRun:` to `AgentDoorSettingsSection`.
