#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

bash "$ROOT/scripts/dart-tool.sh" test \
  test/harness_fixture_inventory_test.dart \
  test/harness_fixture_catalog_test.dart \
  test/harness_validator_test.dart
