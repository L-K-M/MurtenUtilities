#!/bin/bash
# Coreography's C bridge contract tests, moved with CoreographySystem from
# Coreography@f9820e6 (tools/tests). `swift test` does not run them; run
# this on macOS (native contracts) or Linux (unsupported-platform
# contracts). The process test also exercises a raise when run with sudo.
#
#   scripts/coreography-bridge-tests/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TESTS="$ROOT/scripts/coreography-bridge-tests"
SYSTEM="$ROOT/Sources/CoreographySystem"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

frameworks=()
[ "$(uname -s)" = Darwin ] && frameworks=(-framework IOKit)

for bridge in process thermal smc network; do
  cc -std=c11 -Wall -Wextra -Werror -I "$SYSTEM/include" -I "$SYSTEM" \
    "$TESTS/test_${bridge}_bridge.c" "$SYSTEM/$bridge.c" ${frameworks[@]+"${frameworks[@]}"} \
    -o "$OUT/test_${bridge}_bridge"
  "$OUT/test_${bridge}_bridge"
  echo "${bridge} bridge: ok"
done
