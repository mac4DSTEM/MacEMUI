// The extension's server against a stand-in door: what it forwards, what it writes back, and what it says when the door is off
// or the token is wrong. `node --test DesktopExtension/test`.

'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const { PassThrough } = require('node:stream');
const test = require('node:test');
const { doorFrom, serve } = require('../server/index.js');

const token = 'ab'.repeat(32);

/// A door that answers like the app's: 401 without the token, 202 for a notification, else the method echoed back.
function standInDoor() {
  const seen = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.on('data', (chunk) => (body += chunk));
    request.on('end', () => {
      seen.push({ headers: request.headers, body });
      if (request.headers.authorization !== `Bearer ${token}`) {
        response.writeHead(401).end('{"error":"token"}');
        return;
      }
      const message = JSON.parse(body);
      if (message.id === undefined) {
        response.writeHead(202).end();
        return;
      }
      response.writeHead(200, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ jsonrpc: '2.0', id: message.id, result: { method: message.method } }, null, 2));
    });
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve({ server, seen, port: server.address().port })));
}

/// Sends the lines through the server and returns what it wrote, one parsed message per line.
async function exchange(door, lines) {
  const input = new PassThrough();
  const output = new PassThrough();
  let written = '';
  output.on('data', (chunk) => (written += chunk));
  const done = serve(door, input, output);
  for (const line of lines) input.write(`${line}\n`);
  input.end();
  await done;
  return written.split('\n').filter(Boolean).map((line) => JSON.parse(line));
}

test('the pasted connection command gives the port and the token', () => {
  const command = `claude mcp add --transport http macem http://127.0.0.1:47999/mcp --header "Authorization: Bearer ${token.toUpperCase()}"`;
  assert.deepEqual(doorFrom(command, '47812'), { token, port: 47999 });
  assert.deepEqual(doorFrom(` ${token} `, '47812'), { token, port: 47812 });
  assert.deepEqual(doorFrom('', '47812'), { token: null, port: 47812 });
});

test('messages go to the door in order and the answers come back one per line', async () => {
  const { server, seen, port } = await standInDoor();
  const answers = await exchange({ token, port }, [
    JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
    JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }),
    JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    JSON.stringify({ jsonrpc: '2.0', id: 'c', method: 'tools/call', params: { name: 'list_windows' } }),
  ]);
  server.close();
  assert.deepEqual(answers.map((a) => [a.id, a.result.method]), [[1, 'initialize'], [2, 'tools/list'], ['c', 'tools/call']]);
  assert.equal(seen.length, 4, 'the notification is forwarded too');
  assert.equal(seen[0].headers.host, `127.0.0.1:${port}`);
  assert.equal(seen[0].headers.origin, undefined, 'no Origin, which the door refuses');
});

test('a wrong token, a closed door and no connection each answer with what to do', async () => {
  const { server, port } = await standInDoor();
  const [refused] = await exchange({ token: 'cd'.repeat(32), port }, [JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' })]);
  server.close();
  assert.match(refused.error.message, /refused the token.*Copy Connection Command/);

  const [closed] = await exchange({ token, port }, [JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' })]);
  assert.match(closed.error.message, /not answering on port \d+.*Settings > Agents/);
  assert.equal(closed.id, 2);

  const [unset] = await exchange({ token: null, port }, [JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'initialize' })]);
  assert.match(unset.error.message, /No connection set/);

  const quiet = await exchange({ token, port }, [JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' })]);
  assert.deepEqual(quiet, [], 'a notification gets no answer, even when the door is closed');
});

test('a line that is not JSON gets a parse error', async () => {
  const [garbled] = await exchange({ token, port: 1 }, ['{not json']);
  assert.equal(garbled.error.code, -32700);
});

test('each app has a manifest Claude desktop can install, pointing at its own port', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  for (const [app, port] of [['macEM', '47812'], ['mac4DSTEM', '47811']]) {
    const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, '..', app, 'manifest.json'), 'utf8'));
    for (const key of ['manifest_version', 'name', 'version', 'description', 'author', 'server']) assert.ok(manifest[key], `${app}: ${key}`);
    assert.equal(manifest.server.type, 'node');
    assert.equal(manifest.server.entry_point, 'server/index.js');
    assert.deepEqual(manifest.server.mcp_config.args, ['${__dirname}/server/index.js']);
    assert.deepEqual(manifest.server.mcp_config.env, {
      MACEM_DOOR_APP: app, MACEM_DOOR_PORT: port, MACEM_DOOR_CONNECTION: '${user_config.connection}',
    });
    assert.equal(manifest.user_config.connection.sensitive, true);
    assert.deepEqual(manifest.compatibility.platforms, ['darwin']);
    assert.ok(manifest.tools.some((tool) => tool.name === 'list_windows'));
  }
});

test('started as Claude desktop starts it, the server carries a session through', async () => {
  const { spawn } = require('node:child_process');
  const path = require('node:path');
  const { server, port } = await standInDoor();
  const child = spawn(process.execPath, [path.join(__dirname, '..', 'server', 'index.js')], {
    env: { MACEM_DOOR_APP: 'macEM', MACEM_DOOR_PORT: String(port), MACEM_DOOR_CONNECTION: `x Bearer ${token} y` },
  });
  let written = '';
  child.stdout.on('data', (chunk) => (written += chunk));
  child.stdin.end(`${JSON.stringify({ jsonrpc: '2.0', id: 7, method: 'ping' })}\n`);
  const code = await new Promise((resolve) => child.on('close', resolve));
  server.close();
  assert.equal(code, 0);
  assert.deepEqual(JSON.parse(written), { jsonrpc: '2.0', id: 7, result: { method: 'ping' } });
});
