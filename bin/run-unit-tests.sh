#!/bin/sh
# Tests unitaires : LuaJIT (ou Lua 5.x) suffit, Kong et Docker ne sont pas nécessaires.
exec "$(dirname "$0")/../test/unit/run.sh"
