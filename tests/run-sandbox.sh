#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
: "${MAC_INIT_TEST_DIR:?Set MAC_INIT_TEST_DIR to a writable test directory}"
mkdir -p "$MAC_INIT_TEST_DIR"
test_dir=$(cd "$MAC_INIT_TEST_DIR" && pwd -P)
/usr/bin/sandbox-exec -D "TEST_DIR=$test_dir" -f "$repo_dir/tests/sandbox.sb" \
  env MAC_INIT_TEST_DIR="$test_dir" /bin/bash "$repo_dir/tests/smoke.sh"
