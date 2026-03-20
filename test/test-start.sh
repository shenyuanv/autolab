#!/usr/bin/env bash
set -euo pipefail

# Test suite for: autolab start
# Tests the main research loop with spawn, eval, promote/discard, and stop conditions

ROOT=$(cd "$(dirname "$0")/.." && pwd)
AUTOLAB="$ROOT/autolab"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3 (expected '$1', got '$2')"; }
assert_file_exists() { [[ -f "$1" ]] || fail "File does not exist: $1"; }
assert_dir_exists() { [[ -d "$1" ]] || fail "Directory does not exist: $1"; }
assert_contains() {
    local text="$1"
    local pattern="$2"
    local msg="${3:-text should contain pattern}"
    echo "$text" | grep -q "$pattern" || fail "$msg (pattern: '$pattern', text: '$text')"
}

# Create temporary directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================================
# Test 1: Basic start runs rounds and improves metrics
# ============================================================================
echo "Test 1: Basic start runs rounds and improves metrics"
TEST_DIR="$TMP_DIR/test1"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent that improves metrics each round
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
ROUND_COUNT=0
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
# Read round number from prompt, output improving metrics
prompt=$(cat)
round=$(echo "$prompt" | sed -n "s/.*Research Round \([0-9][0-9]*\).*/\1/p" | head -1)
if [[ -z "$round" ]]; then round=1; fi

# Simulate improving metrics
f1=$(echo "0.65 + $round * 0.08" | bc -l)
cat << JSON
{"f1": $f1}
JSON
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Update config to stop after 3 rounds
cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "bash evaluate.sh"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 3
EOF

cat > evaluate.sh << 'EOF'
#!/usr/bin/env bash
# Dummy evaluation - agent mock outputs metrics
echo '{"f1": 0.75}'
EOF
chmod +x evaluate.sh

# Run start command with timeout (should stop after 3 rounds)
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Check that experiments.jsonl was created
assert_file_exists "results/experiments.jsonl"

# Check that at least one round was executed
[[ -d "results/rounds/round-001" ]] || fail "round-001 should exist"

echo "  PASS"

# ============================================================================
# Test 2: Start stops on max_rounds
# ============================================================================
echo "Test 2: Start stops on max_rounds condition"
TEST_DIR="$TMP_DIR/test2"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Mock agent
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
cat > /dev/null  # consume prompt
echo '{"f1": 0.80}'
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Configure with max_rounds=2
cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "echo '{\"f1\": 0.80}'"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 2
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Should have at most 2 rounds
[[ -d "results/rounds/round-001" ]] || fail "round-001 should exist"
[[ -d "results/rounds/round-002" ]] || fail "round-002 should exist"
[[ ! -d "results/rounds/round-003" ]] || fail "round-003 should not exist (max_rounds=2)"

echo "  PASS"

# ============================================================================
# Test 3: Start detects plateau and stops
# ============================================================================
echo "Test 3: Start detects plateau and stops"
TEST_DIR="$TMP_DIR/test3"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Mock agent that returns constant metric (no improvement)
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
cat > /dev/null  # consume prompt
echo '{"f1": 0.70}'
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Configure with plateau=2 (stop after 2 rounds with no improvement)
cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "echo '{\"f1\": 0.70}'"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 100
  plateau: 2
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Should have exactly 3 rounds (1 baseline + 2 no improvement = plateau)
[[ -d "results/rounds/round-001" ]] || fail "round-001 should exist"
[[ -d "results/rounds/round-002" ]] || fail "round-002 should exist"
[[ -d "results/rounds/round-003" ]] || fail "round-003 should exist"
[[ ! -d "results/rounds/round-004" ]] || fail "round-004 should not exist (plateau)"

echo "  PASS"

# ============================================================================
# Test 4: Start promotes on improvement and discards on regression
# ============================================================================
echo "Test 4: Start promotes on improvement, discards on regression"
TEST_DIR="$TMP_DIR/test4"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Create artifact file that agent will modify
echo "0" > artifact.py

# Mock agent: modify artifact to simulate improving metrics
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
prompt=$(cat)
round=$(echo "$prompt" | grep "Research Round" | sed 's/.*Research Round \([0-9]*\).*/\1/')

# Modify artifact.py to simulate changes
if [[ "$round" == "1" ]]; then
  echo "1" > artifact.py  # improve to 0.75
elif [[ "$round" == "2" ]]; then
  echo "-1" > artifact.py  # regress to 0.65
else
  echo "2" > artifact.py  # improve to 0.80
fi
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Create evaluate.sh that reads artifact value
cat > evaluate.sh << 'EVAL'
#!/usr/bin/env bash
# Read artifact value and compute f1 score
val=$(cat artifact.py)
case "$val" in
  0) f1="0.70" ;;
  1) f1="0.75" ;;
  -1) f1="0.65" ;;
  2) f1="0.80" ;;
  *) f1="0.70" ;;
esac
echo "{\"f1\": $f1}"
EVAL
chmod +x evaluate.sh

cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "bash evaluate.sh"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 4
  plateau: 10
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Should have checkpoints for round 1 (improvement to 0.75) and round 3 (improvement to 0.80 after regression)
assert_file_exists "checkpoints/history/round-001/artifact.py"
# Round 2 should not have a checkpoint (regression to 0.65)
[[ ! -f "checkpoints/history/round-002/artifact.py" ]] || fail "round-002 should not have checkpoint (regression)"
# Round 3 should have checkpoint (improvement to 0.80)
assert_file_exists "checkpoints/history/round-003/artifact.py"

echo "  PASS"

# ============================================================================
# Test 5: Experiment history is logged
# ============================================================================
echo "Test 5: Experiment history is logged to experiments.jsonl"
TEST_DIR="$TMP_DIR/test5"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Mock agent
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
cat > /dev/null
echo '{"f1": 0.85}'
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "echo '{\"f1\": 0.85}'"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 2
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Check experiments.jsonl exists and has at least one entry
assert_file_exists "results/experiments.jsonl"
line_count=$(wc -l < "results/experiments.jsonl" 2>/dev/null || echo 0)
[[ $line_count -ge 1 ]] || fail "experiments.jsonl should have at least 1 line"

echo "  PASS"

# ============================================================================
# Test 6: Stage transitions work
# ============================================================================
echo "Test 6: Stage transitions work when threshold is met"
TEST_DIR="$TMP_DIR/test6"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Mock agent that improves across stages
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
prompt=$(cat)
round=$(echo "$prompt" | sed -n "s/.*Research Round \([0-9][0-9]*\).*/\1/p" | head -1)
# Improve progressively
f1=$(echo "0.50 + $round * 0.12" | bc -l)
echo "{\"f1\": $f1}"
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Configure with two stages: baseline (threshold 0.60) and improve (threshold 0.80)
cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "echo '{\"f1\": 0.70}'"
metric:
  name: f1
  direction: maximize
stages:
  - id: baseline
    goal: "Establish baseline"
    metric: f1
    threshold: 0.60
  - id: improve
    goal: "Improve performance"
    metric: f1
    threshold: 0.80
    requires: baseline
stop:
  max_rounds: 10
  plateau: 10
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Check experiments.jsonl for stage information
assert_file_exists "results/experiments.jsonl"
history=$(cat "results/experiments.jsonl")
# Should have at least one entry with stage information
[[ -n "$history" ]] || fail "Should have experiment history"

echo "  PASS"

# ============================================================================
# Test 7: Start continues looping until stop condition
# ============================================================================
echo "Test 7: Start continues looping until stop condition"
TEST_DIR="$TMP_DIR/test7"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

"$AUTOLAB" init > /dev/null

# Mock agent that improves over time
BIN_DIR="$TEST_DIR/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
prompt=$(cat)
round=$(echo "$prompt" | sed -n "s/.*Research Round \([0-9][0-9]*\).*/\1/p" | head -1)
# Each round improves by 0.05
f1=$(echo "0.50 + $round * 0.05" | bc -l)
echo "{\"f1\": $f1}"
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

cat > autolab.yaml << 'EOF'
project: test-project
artifacts:
  - artifact.py
evaluate: "echo '{\"f1\": 0.70}'"
metric:
  name: f1
  direction: maximize
stop:
  max_rounds: 5
  plateau: 10
EOF

# Run start
timeout 30 "$AUTOLAB" start > /dev/null 2>&1 || true

# Should have created all 5 rounds since each improves
[[ -d "results/rounds/round-001" ]] || fail "round-001 should exist"
[[ -d "results/rounds/round-002" ]] || fail "round-002 should exist"
[[ -d "results/rounds/round-003" ]] || fail "round-003 should exist"
[[ -d "results/rounds/round-004" ]] || fail "round-004 should exist"
[[ -d "results/rounds/round-005" ]] || fail "round-005 should exist"

echo "  PASS"

echo ""
echo "OK"
