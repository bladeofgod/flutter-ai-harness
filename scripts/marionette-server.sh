#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

exec bash "$ROOT/scripts/dart-tool.sh" pub global run marionette_mcp:marionette_mcp "$@"
