#!/bin/sh
# Télécharge luaunit (seule dépendance des tests unitaires) dans test/lib.
set -eu
cd "$(dirname "$0")/.."
LUAUNIT_TAG=LUAUNIT_V3_5
mkdir -p test/lib
if [ ! -f test/lib/luaunit.lua ]; then
  curl -fsSL "https://raw.githubusercontent.com/bluebird75/luaunit/${LUAUNIT_TAG}/luaunit.lua" -o test/lib/luaunit.lua
fi
