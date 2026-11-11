#!/usr/bin/env node
// The Claude desktop extension's server: it carries MCP between Claude desktop and the agent door of a running app.
//
// Claude desktop starts this script over stdio (one JSON-RPC message per line). The app is the MCP server, over HTTP on this
// Mac (POST http://127.0.0.1:<port>/mcp with the door's token), so this script only forwards each message and writes back the
// app's answer. It does nothing else: it keeps no state, adds no tools and talks to no other computer.
//
// Settings come from the extension's manifest as environment variables:
//   MACEM_DOOR_APP         the app's name, for messages ("macEM", "mac4DSTEM")
//   MACEM_DOOR_PORT        the app's own port (macEM 47812, mac4DSTEM 47811)
//   MACEM_DOOR_CONNECTION  what Settings > Agents > Copy Connection Command copied, or the token alone
//
// Node's standard library only (Claude desktop brings its own Node), so the extension needs no packages.

'use strict';

const http = require('node:http');
const readline = require('node:readline');

const app = process.env.MACEM_DOOR_APP || 'the app';

/// The door's address and token from what the person pasted: the whole connection command (its URL and Bearer token), or the
/// token alone, with the app's own port.
function doorFrom(pasted, port) {
  const text = String(pasted || '');
  const token = (text.match(/Bearer\s+([0-9a-f]{64})/i) || text.match(/\b([0-9a-f]{64})\b/i) || [])[1];
  const url = text.match(/http:\/\/127\.0\.0\.1:(\d+)\/mcp/);
  return { token: token ? token.toLowerCase() : null, port: url ? Number(url[1]) : Number(port) || 0 };
}

/// One JSON-RPC message POSTed to the door; resolves to the HTTP status and body, or to an error when nothing answers.
function post(door, body) {
  return new Promise((resolve) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port: door.port,
        path: '/mcp',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${door.token}`,
          'Content-Type': 'application/json',
          Accept: 'application/json, text/event-stream',
          'Content-Length': Buffer.byteLength(body),
        },
        timeout: 60000,
      },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => resolve({ status: response.statusCode, body: Buffer.concat(chunks).toString('utf8') }));
      },
    );
    request.on('timeout', () => request.destroy(new Error('timeout')));
    request.on('error', (error) => resolve({ status: 0, error }));
    request.end(body);
  });
}

function rpcError(id, message) {
  return { jsonrpc: '2.0', id, error: { code: -32000, message } };
}

/// What to write back for one message the client sent: a JSON-RPC answer, or null (a notification, or the client's response).
async function answer(door, line) {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } };
  }
  const id = message && Object.prototype.hasOwnProperty.call(message, 'id') ? message.id : undefined;
  const expectsAnswer = id !== undefined && id !== null && typeof message.method === 'string';
  if (!door.token) {
    return expectsAnswer
      ? rpcError(id, `No connection set: in ${app}, Settings > Agents, press Copy Connection Command and paste it into this extension's settings in Claude.`)
      : null;
  }
  const reply = await post(door, line);
  if (!expectsAnswer) return null;
  if (reply.status === 0) {
    return rpcError(id, `${app} is not answering on port ${door.port}: open ${app} and turn on Settings > Agents.`);
  }
  if (reply.status === 401) {
    return rpcError(id, `${app} refused the token. In ${app}, Settings > Agents, press Copy Connection Command and paste it into this extension's settings in Claude again (New Token changes it).`);
  }
  try {
    return JSON.parse(reply.body);
  } catch {
    return rpcError(id, `${app} answered with status ${reply.status}.`);
  }
}

/// Reads messages from `input` one line at a time, in order, and writes each answer to `output` as one line.
function serve(door, input, output) {
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let queue = Promise.resolve();
  lines.on('line', (line) => {
    if (!line.trim()) return;
    queue = queue.then(async () => {
      const reply = await answer(door, line);
      if (reply) output.write(`${JSON.stringify(reply)}\n`);
    });
  });
  return new Promise((resolve) => lines.on('close', () => queue.then(resolve)));
}

module.exports = { doorFrom, answer, serve };

if (require.main === module) {
  const door = doorFrom(process.env.MACEM_DOOR_CONNECTION, process.env.MACEM_DOOR_PORT);
  serve(door, process.stdin, process.stdout).then(() => process.exit(0));
}
