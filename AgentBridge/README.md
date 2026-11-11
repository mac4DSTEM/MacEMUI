# macem-mcp

The one MCP bridge to the agent door of mac4DSTEM and macTEM (`ShellAgentDoor` in MacEMUI). An MCP client (Claude Code,
Codex, any client that speaks the stdio transport) starts it; it asks the app's door on this Mac and passes the answers on.
The tools are the app's own: the bridge lists what the door lists, so it needs no change when an app adds one.

```sh
swift build -c release --package-path AgentBridge
claude mcp add mac4dstem -- "$PWD/AgentBridge/.build/release/macem-mcp" --app mac4DSTEM
claude mcp add mactem -- "$PWD/AgentBridge/.build/release/macem-mcp" --app macTEM
```

Then, in the app: Settings > Agents > "Let agents on this Mac look at open windows". The door is off until then, listens on
127.0.0.1 only, and answers only the token in the file it writes for this user's account.

Read-only in this version: every tool looks at an open window; none changes the app.

Finding the door: `<APP>_AGENT_PORT` and `<APP>_AGENT_TOKEN` (for example `MACTEM_AGENT_PORT`), else the file named by
`<APP>_AGENT_DOOR`, else the file the app writes (inside its sandbox container, then plain Application Support).
