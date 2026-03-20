#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTOLAB="$ROOT/autolab"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() {
  [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"
}
assert_success() {
  "$@" || fail "Command should succeed: $*"
}
assert_failure() {
  ! "$@" || fail "Command should fail: $*"
}

# Create temp directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Test 1: validate passes on well-formed project"
TEST_DIR="$TMP_DIR/test1"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
description: "A test project"
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
EOF

touch artifacts/model.py
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "Test 2: validate fails on missing autolab.yaml"
TEST_DIR="$TMP_DIR/test2"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 3: validate fails on invalid YAML syntax"
TEST_DIR="$TMP_DIR/test3"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
  invalid yaml: [
EOF

assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 4: validate fails on missing required field (project)"
TEST_DIR="$TMP_DIR/test4"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
description: "Missing project field"
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 5: validate fails on missing required field (artifacts)"
TEST_DIR="$TMP_DIR/test5"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
EOF

assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 6: validate fails on empty artifacts list"
TEST_DIR="$TMP_DIR/test6"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts: []
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
EOF

assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 7: validate fails on missing required field (evaluate)"
TEST_DIR="$TMP_DIR/test7"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
metric:
  name: f1
  direction: maximize
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 8: validate fails on missing required field (metric)"
TEST_DIR="$TMP_DIR/test8"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 9: validate fails when metric missing name"
TEST_DIR="$TMP_DIR/test9"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  direction: maximize
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 10: validate fails on invalid metric.direction"
TEST_DIR="$TMP_DIR/test10"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: invalid
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 11: validate passes with default metric.direction (maximize)"
TEST_DIR="$TMP_DIR/test11"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
EOF

touch artifacts/model.py
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "Test 12: validate passes with minimize direction"
TEST_DIR="$TMP_DIR/test12"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: loss
  direction: minimize
EOF

touch artifacts/model.py
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "Test 13: validate passes with optional fields (agent, stages, stop, notify)"
TEST_DIR="$TMP_DIR/test13"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
description: "Test with optional fields"
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
agent:
  command: claude
  flags: "--max-turns 10"
stages:
  - id: baseline
    threshold: 0.6
stop:
  max_rounds: 100
  plateau: 5
notify:
  slack_channel: C0AF9C7J7U4
EOF

touch artifacts/model.py
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "Test 14: validate fails on missing stage id"
TEST_DIR="$TMP_DIR/test14"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
stages:
  - goal: "Some goal"
    threshold: 0.6
EOF

touch artifacts/model.py
assert_failure "$AUTOLAB" validate
echo "  PASS"

echo "Test 15: validate passes with artifacts not in artifacts/ directory (root level)"
TEST_DIR="$TMP_DIR/test15"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test
artifacts:
  - model.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
EOF

touch model.py
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "Test 16: validate reads all config fields correctly"
TEST_DIR="$TMP_DIR/test16"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: comprehensive-test
description: "Comprehensive test project"
artifacts:
  - model.py
  - config.yaml
evaluate: "bash evaluate.sh"
metric:
  name: accuracy
  direction: maximize
agent:
  command: claude
  flags: "--max-turns 20"
stages:
  - id: stage1
    goal: "First goal"
    metric: accuracy
    threshold: 0.8
  - id: stage2
    goal: "Second goal"
    metric: f1
    threshold: 0.85
    requires: stage1
stop:
  max_rounds: 150
  plateau: 10
  time_limit: "8h"
notify:
  slack_channel: C123456
  on:
    - stage_complete
    - error
EOF

touch artifacts/model.py artifacts/config.yaml
assert_success "$AUTOLAB" validate
echo "  PASS"

echo "OK"
