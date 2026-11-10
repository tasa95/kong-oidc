#!/bin/sh
# Lance les tests unitaires depuis la racine du dépôt (LuaJIT si présent, comme Kong).
set -eu
cd "$(dirname "$0")/../.."
./bin/fetch-test-deps.sh
LUA=$(command -v luajit || command -v lua)
export LUA_PATH="./?.lua;./test/lib/?.lua;;"
status=0
for f in test/unit/test_*.lua; do
  echo "== $f"
  "$LUA" "$f" -o text || status=1
done
exit $status
