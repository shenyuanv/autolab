#!/usr/bin/env bash
set -euo pipefail

# Test suite for: autolab init
# Tests the initialization of a new autolab project

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

assert_file_exists() {
    local file="$1"
    [[ -f "$file" ]] || fail "File does not exist: $file"
}

assert_dir_exists() {
    local dir="$1"
    [[ -d "$dir" ]] || fail "Directory does not exist: $dir"
}

assert_file_executable() {
    local file="$1"
    [[ -x "$file" ]] || fail "File is not executable: $file"
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
# Test 1: Init in empty directory creates all expected files and directories
# ============================================================================
echo "Test 1: Init in empty directory creates all expected files/dirs"
test1_dir="$TMP_DIR/test-1"
mkdir -p "$test1_dir"
cd "$test1_dir"

"$AUTOLAB" init

# Check files exist
assert_file_exists "autolab.yaml"
assert_file_exists "program.md"
assert_file_exists "evaluate.sh"
assert_file_exists ".gitignore"

# Check directories exist
assert_dir_exists "artifacts"
assert_dir_exists "data"
assert_dir_exists "checkpoints/best"
assert_dir_exists "checkpoints/history"
assert_dir_exists "results/rounds"

# Check git was initialized
assert_dir_exists ".git"

echo "  PASS"

# ============================================================================
# Test 2: Init in existing directory does not overwrite existing files
# ============================================================================
echo "Test 2: Init in existing dir does not overwrite existing files"
test2_dir="$TMP_DIR/test-2"
mkdir -p "$test2_dir"
cd "$test2_dir"

# Create custom autolab.yaml
cat > autolab.yaml << 'EOF'
project: custom-project
EOF

original_content=$(cat autolab.yaml)

# Run init
"$AUTOLAB" init

# Verify autolab.yaml was not overwritten
current_content=$(cat autolab.yaml)
assert_eq "$original_content" "$current_content" "autolab.yaml should not be overwritten"

# But other files should be created
assert_file_exists "program.md"
assert_file_exists "evaluate.sh"

echo "  PASS"

# ============================================================================
# Test 3: Generated evaluate.sh is executable and outputs valid JSON
# ============================================================================
echo "Test 3: Generated evaluate.sh is executable and outputs valid JSON"
test3_dir="$TMP_DIR/test-3"
mkdir -p "$test3_dir"
cd "$test3_dir"

"$AUTOLAB" init

# Check executable
assert_file_executable "evaluate.sh"

# Run evaluate.sh and check output
output=$("$test3_dir/evaluate.sh")
assert_valid_json "$output" "evaluate.sh should output valid JSON"

# Verify it has at least the f1 metric (from template)
f1_value=$(echo "$output" | jq '.f1')
[[ -n "$f1_value" ]] || fail "evaluate.sh output should include 'f1' metric"

echo "  PASS"

# ============================================================================
# Test 4: Running autolab init twice is idempotent
# ============================================================================
echo "Test 4: Running autolab init twice is idempotent"
test4_dir="$TMP_DIR/test-4"
mkdir -p "$test4_dir"
cd "$test4_dir"

# First init
"$AUTOLAB" init

# Capture state after first init
files_after_first=$(find . -type f ! -path './.git/*' ! -path './.claude/*' | sort)
dirs_after_first=$(find . -type d ! -path './.git/*' ! -path './.claude/*' | sort)

# Second init
"$AUTOLAB" init

# Capture state after second init
files_after_second=$(find . -type f ! -path './.git/*' ! -path './.claude/*' | sort)
dirs_after_second=$(find . -type d ! -path './.git/*' ! -path './.claude/*' | sort)

# Verify same files and directories
assert_eq "$files_after_first" "$files_after_second" "Files should be same after second init"
assert_eq "$dirs_after_first" "$dirs_after_second" "Directories should be same after second init"

echo "  PASS"

# ============================================================================
# Test 5: autolab.yaml contains required fields
# ============================================================================
echo "Test 5: autolab.yaml contains required fields"
test5_dir="$TMP_DIR/test-5"
mkdir -p "$test5_dir"
cd "$test5_dir"

"$AUTOLAB" init

# Check required fields using yq
project=$(yq eval '.project' autolab.yaml)
[[ -n "$project" ]] || fail "autolab.yaml should have 'project' field"

artifacts=$(yq eval '.artifacts' autolab.yaml)
[[ -n "$artifacts" ]] || fail "autolab.yaml should have 'artifacts' field"

evaluate=$(yq eval '.evaluate' autolab.yaml)
[[ -n "$evaluate" ]] || fail "autolab.yaml should have 'evaluate' field"

metric=$(yq eval '.metric' autolab.yaml)
[[ -n "$metric" ]] || fail "autolab.yaml should have 'metric' field"

echo "  PASS"

# ============================================================================
# Test 6: Git initialized with initial commit
# ============================================================================
echo "Test 6: Git initialized with initial commit"
test6_dir="$TMP_DIR/test-6"
mkdir -p "$test6_dir"
cd "$test6_dir"

"$AUTOLAB" init

# Verify git has a commit
if ! git rev-parse HEAD &>/dev/null; then
    fail "Git should have an initial commit"
fi

# Verify initial commit message contains "setup"
commit_msg=$(git log -1 --pretty=%B)
[[ "$commit_msg" =~ setup ]] || fail "Initial commit should mention setup"

echo "  PASS"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "OK"
