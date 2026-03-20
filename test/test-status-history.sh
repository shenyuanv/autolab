#!/usr/bin/env bash
set -euo pipefail

# Test suite for: autolab status and autolab history
# Tests the status and history commands

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
    local haystack="$1"
    local needle="$2"
    local msg="${3:-string not found}"
    if ! echo "$haystack" | grep -q "$needle"; then
        fail "$msg (string not found: '$needle')"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-string should not be found}"
    if echo "$haystack" | grep -q "$needle"; then
        fail "$msg (string found: '$needle')"
    fi
}

# Create temporary directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# ============================================================================
# Test 1: autolab status shows "No experiments run yet" on fresh project
# ============================================================================
echo "Test 1: autolab status shows 'No experiments run yet' on fresh project"
test1_dir="$TMP_DIR/test-1"
mkdir -p "$test1_dir"
cd "$test1_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Run status
status_output=$("$AUTOLAB" status)

# Verify output
assert_contains "$status_output" "No experiments run yet" "Status should show no experiments"
echo "  PASS"

# ============================================================================
# Test 2: autolab history shows "No experiments recorded yet" on fresh project
# ============================================================================
echo "Test 2: autolab history shows 'No experiments recorded yet' on fresh project"
test2_dir="$TMP_DIR/test-2"
mkdir -p "$test2_dir"
cd "$test2_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Run history
history_output=$("$AUTOLAB" history)

# Verify output
assert_contains "$history_output" "No experiments recorded yet" "History should show no experiments"
echo "  PASS"

# ============================================================================
# Test 3: autolab status shows metrics after experiment added
# ============================================================================
echo "Test 3: autolab status shows metrics after experiment added"
test3_dir="$TMP_DIR/test-3"
mkdir -p "$test3_dir"
cd "$test3_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Manually create experiments.jsonl with a test entry
mkdir -p results
cat > results/experiments.jsonl << 'EOF'
{"round": 1, "metric_value": 0.75, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:00:00Z"}
EOF

# Create best metrics file
mkdir -p checkpoints/best
cat > checkpoints/best/.best_metrics.json << 'EOF'
{
  "metric": "f1",
  "value": 0.75,
  "direction": "maximize",
  "round": 1
}
EOF

# Run status
status_output=$("$AUTOLAB" status)

# Verify output contains metric info
assert_contains "$status_output" "Best metric (f1): 0.75" "Status should show best metric"
assert_contains "$status_output" "Total rounds: 1" "Status should show total rounds"
assert_contains "$status_output" "Last round: Round 1" "Status should show last round"
echo "  PASS"

# ============================================================================
# Test 4: autolab history shows experiment entries
# ============================================================================
echo "Test 4: autolab history shows experiment entries"
test4_dir="$TMP_DIR/test-4"
mkdir -p "$test4_dir"
cd "$test4_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Create multiple experiment entries
mkdir -p results
cat > results/experiments.jsonl << 'EOF'
{"round": 1, "metric_value": 0.75, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:00:00Z"}
{"round": 2, "metric_value": 0.78, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:05:00Z"}
{"round": 3, "metric_value": 0.77, "improved": false, "stage": "baseline", "timestamp": "2026-03-20T10:10:00Z"}
EOF

# Run history
history_output=$("$AUTOLAB" history)

# Verify output shows table header
assert_contains "$history_output" "Round" "History should show Round column"
assert_contains "$history_output" "Metric" "History should show Metric column"
assert_contains "$history_output" "Improved" "History should show Improved column"

# Verify all three rounds are shown
assert_contains "$history_output" "1" "History should show round 1"
assert_contains "$history_output" "2" "History should show round 2"
assert_contains "$history_output" "3" "History should show round 3"

# Verify metrics are shown
assert_contains "$history_output" "0.75" "History should show metric value 0.75"
assert_contains "$history_output" "0.78" "History should show metric value 0.78"
assert_contains "$history_output" "0.77" "History should show metric value 0.77"

echo "  PASS"

# ============================================================================
# Test 5: autolab history shows checkmark for improved experiments
# ============================================================================
echo "Test 5: autolab history shows checkmark for improved experiments"
test5_dir="$TMP_DIR/test-5"
mkdir -p "$test5_dir"
cd "$test5_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Create experiments with mixed improvements
mkdir -p results
cat > results/experiments.jsonl << 'EOF'
{"round": 1, "metric_value": 0.75, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:00:00Z"}
{"round": 2, "metric_value": 0.77, "improved": false, "stage": "baseline", "timestamp": "2026-03-20T10:05:00Z"}
EOF

# Run history
history_output=$("$AUTOLAB" history)

# Verify checkmark appears for improved, dash for not improved
# Should have at least 2 rows beyond header (2 data rows)
checkmark_count=$(echo "$history_output" | grep -o "✓" | wc -l)
[[ $checkmark_count -gt 0 ]] || fail "History should show checkmark for improved"

echo "  PASS"

# ============================================================================
# Test 6: autolab status shows plateau count correctly
# ============================================================================
echo "Test 6: autolab status shows plateau count correctly"
test6_dir="$TMP_DIR/test-6"
mkdir -p "$test6_dir"
cd "$test6_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Create experiments with a plateau (no improvement for last 3 rounds)
mkdir -p results
cat > results/experiments.jsonl << 'EOF'
{"round": 1, "metric_value": 0.75, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:00:00Z"}
{"round": 2, "metric_value": 0.74, "improved": false, "stage": "baseline", "timestamp": "2026-03-20T10:05:00Z"}
{"round": 3, "metric_value": 0.73, "improved": false, "stage": "baseline", "timestamp": "2026-03-20T10:10:00Z"}
{"round": 4, "metric_value": 0.74, "improved": false, "stage": "baseline", "timestamp": "2026-03-20T10:15:00Z"}
EOF

# Run status
status_output=$("$AUTOLAB" status)

# Verify plateau count is shown as 3 (rounds 2, 3, 4)
assert_contains "$status_output" "Rounds since improvement: 3" "Status should show 3 rounds without improvement"
echo "  PASS"

# ============================================================================
# Test 7: autolab status handles missing config directory
# ============================================================================
echo "Test 7: autolab status handles missing config gracefully"
test7_dir="$TMP_DIR/test-7"
mkdir -p "$test7_dir"
cd "$test7_dir"

# Try to run status without initializing project
status_error=$("$AUTOLAB" status 2>&1) || true
if echo "$status_error" | grep -q "autolab.yaml"; then
    echo "  PASS"
else
    fail "Status should fail gracefully when autolab.yaml not found"
fi

# ============================================================================
# Test 8: autolab history shows timestamps
# ============================================================================
echo "Test 8: autolab history shows timestamps"
test8_dir="$TMP_DIR/test-8"
mkdir -p "$test8_dir"
cd "$test8_dir"

"$AUTOLAB" init > /dev/null 2>&1

# Create experiments with specific timestamps
mkdir -p results
cat > results/experiments.jsonl << 'EOF'
{"round": 1, "metric_value": 0.75, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:00:00Z"}
{"round": 2, "metric_value": 0.78, "improved": true, "stage": "baseline", "timestamp": "2026-03-20T10:05:00Z"}
EOF

# Run history
history_output=$("$AUTOLAB" history)

# Verify timestamps are shown
assert_contains "$history_output" "2026-03-20T10:00:00Z" "History should show timestamp"
assert_contains "$history_output" "2026-03-20T10:05:00Z" "History should show timestamp"
echo "  PASS"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "OK"
