#!/usr/bin/env bash
set -euo pipefail

# Test suite for: autolab spawn
# Tests the sub-agent spawning with prompt template generation

ROOT=$(cd "$(dirname "$0")/.." && pwd)
AUTOLAB="$ROOT/autolab"

# Helper functions
fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-assertion failed}"
    [[ "$expected" == "$actual" ]] || fail "$msg (expected '$expected', got '$actual')"
}

assert_contains() {
    local text="$1"
    local pattern="$2"
    local msg="${3:-text should contain pattern}"
    echo "$text" | grep -q "$pattern" || fail "$msg (pattern: '$pattern', text: '$text')"
}

assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || fail "File does not exist: $file"
}

assert_dir_exists() {
    local dir="$1"
    [[ -d "$dir" ]] || fail "Directory does not exist: $dir"
}

assert_valid_json() {
    local json="$1"
    local msg="${2:-JSON validation failed}"
    if ! echo "$json" | jq . > /dev/null 2>&1; then
        fail "$msg"
    fi
}

# Create temporary directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================================
# Test 1: Spawn creates round directory
# ============================================================================
echo "Test 1: Spawn creates round directory and prompt"
test1_dir="$TMP_DIR/test-1"
mkdir -p "$test1_dir"
cd "$test1_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Mock the claude command
BIN_DIR="$test1_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
# Mock claude agent
echo "Mock agent started"
sleep 0.05
echo "Work completed"
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn agent for round 1
"$AUTOLAB" spawn 1 > /dev/null 2>&1

# Wait for agent to finish
sleep 0.2

# Check that round directory was created
assert_dir_exists "results/rounds/round-001"
echo "  PASS"

# ============================================================================
# Test 2: Agent log is saved to round directory
# ============================================================================
echo "Test 2: Agent log is saved to round directory"
test2_dir="$TMP_DIR/test-2"
mkdir -p "$test2_dir"
cd "$test2_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent
BIN_DIR="$test2_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
# Read and echo the prompt
cat
echo "Agent work completed"
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn agent for round 1
"$AUTOLAB" spawn 1 > /dev/null 2>&1

# Wait for background process
sleep 0.5

# Check log was created
assert_file_exists "results/rounds/round-001/agent.log"

echo "  PASS"

# ============================================================================
# Test 3: Prompt template includes required fields
# ============================================================================
echo "Test 3: Prompt template includes required fields"
test3_dir="$TMP_DIR/test-3"
mkdir -p "$test3_dir"
cd "$test3_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create a config file with stages
cat >> autolab.yaml << 'EOF'

stages:
  - id: baseline
    goal: "Establish baseline"
    metric: f1
    threshold: 0.60
EOF

# Create mock agent
BIN_DIR="$test3_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn agent
"$AUTOLAB" spawn 1 > /dev/null 2>&1
sleep 0.1

# Check prompt was created
assert_file_exists "results/rounds/round-001/prompt.txt"

# Check prompt contains required fields
prompt=$(cat results/rounds/round-001/prompt.txt)
assert_contains "$prompt" "Research Round" "Prompt should have Research Round header"
assert_contains "$prompt" "baseline" "Prompt should reference stage"
assert_contains "$prompt" "f1" "Prompt should reference metric"
assert_contains "$prompt" "Instructions" "Prompt should have Instructions section"

echo "  PASS"

# ============================================================================
# Test 4: PID is tracked for spawned agent
# ============================================================================
echo "Test 4: PID is tracked for spawned agent"
test4_dir="$TMP_DIR/test-4"
mkdir -p "$test4_dir"
cd "$test4_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent
BIN_DIR="$test4_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
sleep 0.05
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn agent
"$AUTOLAB" spawn 1 > /dev/null 2>&1

# Wait briefly for PID to be written
sleep 0.1

# Check PID file exists
assert_file_exists "results/rounds/round-001/agent.pid"

# Check PID is a valid number
pid=$(cat results/rounds/round-001/agent.pid)
[[ "$pid" =~ ^[0-9]+$ ]] || fail "agent.pid should contain a valid process ID"

echo "  PASS"

# ============================================================================
# Test 5: Prompt includes program.md content reference
# ============================================================================
echo "Test 5: Prompt generation references program.md"
test5_dir="$TMP_DIR/test-5"
mkdir -p "$test5_dir"
cd "$test5_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Verify program.md exists and has content
assert_file_exists "program.md"
program_content=$(cat program.md)
assert_contains "$program_content" "Objective" "program.md should have Objective section"
assert_contains "$program_content" "Task" "program.md should have Task section"

echo "  PASS"

# ============================================================================
# Test 6: Agent config is read from autolab.yaml
# ============================================================================
echo "Test 6: Agent config is read from autolab.yaml"
test6_dir="$TMP_DIR/test-6"
mkdir -p "$test6_dir"
cd "$test6_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Verify agent config exists
config=$(yq eval '.agent' autolab.yaml)
[[ -n "$config" && "$config" != "null" ]] || fail "autolab.yaml should have agent config"

agent_command=$(yq eval '.agent.command' autolab.yaml)
assert_eq "claude" "$agent_command" "agent.command should be 'claude'"

echo "  PASS"

# ============================================================================
# Test 7: Evaluate command is available in prompt context
# ============================================================================
echo "Test 7: Evaluate command is available in prompt context"
test7_dir="$TMP_DIR/test-7"
mkdir -p "$test7_dir"
cd "$test7_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent
BIN_DIR="$test7_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn agent
"$AUTOLAB" spawn 1 > /dev/null 2>&1
sleep 0.1

# Check evaluate command is in prompt
prompt=$(cat results/rounds/round-001/prompt.txt)
eval_cmd=$(yq eval '.evaluate' autolab.yaml)
assert_contains "$prompt" "$eval_cmd" "Prompt should include the evaluate command"

echo "  PASS"

# ============================================================================
# Test 8: Spawn multiple rounds creates separate directories
# ============================================================================
echo "Test 8: Spawn multiple rounds creates separate directories"
test8_dir="$TMP_DIR/test-8"
mkdir -p "$test8_dir"
cd "$test8_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent
BIN_DIR="$test8_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn multiple rounds
"$AUTOLAB" spawn 1 > /dev/null 2>&1
"$AUTOLAB" spawn 2 > /dev/null 2>&1
"$AUTOLAB" spawn 3 > /dev/null 2>&1

sleep 0.1

# Check all round directories exist
assert_dir_exists "results/rounds/round-001"
assert_dir_exists "results/rounds/round-002"
assert_dir_exists "results/rounds/round-003"

# Check each has a prompt
assert_file_exists "results/rounds/round-001/prompt.txt"
assert_file_exists "results/rounds/round-002/prompt.txt"
assert_file_exists "results/rounds/round-003/prompt.txt"

echo "  PASS"

# ============================================================================
# Test 9: Prompt includes correct round number
# ============================================================================
echo "Test 9: Prompt includes correct round number"
test9_dir="$TMP_DIR/test-9"
mkdir -p "$test9_dir"
cd "$test9_dir"

# Initialize project
"$AUTOLAB" init > /dev/null

# Create mock agent
BIN_DIR="$test9_dir/bin"
mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/claude" << 'CLAUDE'
#!/usr/bin/env bash
exit 0
CLAUDE
chmod +x "$BIN_DIR/claude"
export PATH="$BIN_DIR:$PATH"

# Spawn round 5
"$AUTOLAB" spawn 5 > /dev/null 2>&1
sleep 0.1

# Check prompt has round 5
prompt=$(cat results/rounds/round-005/prompt.txt)
assert_contains "$prompt" "Research Round 5" "Prompt should reference round 5"

echo "  PASS"

# ============================================================================
# Test 10: Spawn fails gracefully when autolab.yaml is missing
# ============================================================================
echo "Test 10: Spawn fails gracefully when autolab.yaml is missing"
test10_dir="$TMP_DIR/test-10"
mkdir -p "$test10_dir"
cd "$test10_dir"

# Don't initialize - missing autolab.yaml

# Try to spawn (should fail)
if "$AUTOLAB" spawn 1 > /dev/null 2>&1; then
    fail "Spawn should fail when autolab.yaml is missing"
fi

echo "  PASS"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "OK"
