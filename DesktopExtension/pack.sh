#!/bin/sh
# Packs the Claude desktop extensions, one per app: <out>/macEM.mcpb and <out>/mac4DSTEM.mcpb (default out: ./build).
# An .mcpb is a zip of manifest.json and the server (the format of github.com/modelcontextprotocol/mcpb); Claude desktop
# installs one on a double click. The server uses Node's standard library only, so nothing else goes in.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-"$here/build"}
mkdir -p "$out"
for app in macEM mac4DSTEM; do
  stage=$(mktemp -d)
  cp "$here/$app/manifest.json" "$stage/manifest.json"
  mkdir "$stage/server"
  cp "$here/server/index.js" "$stage/server/index.js"
  rm -f "$out/$app.mcpb"
  (cd "$stage" && zip -q -X -r "$out/$app.mcpb" manifest.json server)
  rm -r "$stage"
  echo "$out/$app.mcpb"
done
