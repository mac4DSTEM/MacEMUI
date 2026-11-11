# macem-mcp

The one MCP bridge to the agent door of mac4DSTEM and macTEM (`ShellAgentDoor` in MacEMUI). An MCP client (Claude Code,
Codex, any client that speaks the stdio transport) starts it; it asks the app's door on this Mac and passes the answers on.
The tools are the app's own: the bridge lists what the door lists, so it needs no change when an app adds one.

```sh
swift build -c release --package-path AgentBridge
cp AgentBridge/.build/release/macem-mcp /usr/local/bin/    # or anywhere on the PATH
```

Then, in the app: Settings > Agents > turn on "Let agents on this Mac look at open windows", press Copy Connection Command, and
run the copied line in Terminal once. It reads like

```sh
claude mcp add mactem -e MACTEM_AGENT_PORT=47812 -e MACTEM_AGENT_TOKEN=<64 hex digits> -- macem-mcp --app macTEM
```

The door is off until it is turned on, listens on 127.0.0.1 only, and answers only its token. The token stays the same until
New Token in the same pane; a new token needs the command copied again.

Read-only in this version: every tool looks at an open window; none changes the app.

Finding the door: `<APP>_AGENT_PORT` and `<APP>_AGENT_TOKEN` (for example `MACTEM_AGENT_PORT`), as the command sets them. The
apps write no file for the bridge: a sandboxed app's container is closed to other programs.
