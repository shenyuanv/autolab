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
assert_file_exists() {
  [[ -f "$1" ]] || fail "File should exist: $1"
}
assert_dir_exists() {
  [[ -d "$1" ]] || fail "Directory should exist: $1"
}

# Create temp directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Test 1: promote creates checkpoint on improvement"
TEST_DIR="$TMP_DIR/test1"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
echo "code" > model.py
echo '{"f1": 0.80}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

assert_success "$AUTOLAB" promote 1 0.80 "f1"
assert_file_exists "checkpoints/best/model.py"
assert_dir_exists "checkpoints/history/round-001"
echo "  PASS"

echo "Test 2: promote creates git commit with round and metrics"
TEST_DIR="$TMP_DIR/test2"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: accuracy
  direction: maximize
EOF
echo "code" > model.py
echo '{"accuracy": 0.75}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

assert_success "$AUTOLAB" promote 2 0.75 "accuracy"
git log -1 --pretty=%B | grep -q "Round 2" || fail "Git commit should contain 'Round 2'"
git log -1 --pretty=%B | grep -q "accuracy" || fail "Git commit should contain metric name"
echo "  PASS"

echo "Test 3: discard reverts artifact to last best"
TEST_DIR="$TMP_DIR/test3"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
echo "best_code" > model.py
mkdir -p checkpoints/best
echo "best_code" > checkpoints/best/model.py
echo '{"f1": 0.85}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

# Modify artifact to simulate regression
echo "bad_code" > model.py

assert_success "$AUTOLAB" discard
assert_eq "best_code" "$(cat model.py)" "artifact should be reverted"
echo "  PASS"

echo "Test 4: restore restores checkpoint from specific round"
TEST_DIR="$TMP_DIR/test4"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: loss
  direction: minimize
EOF
echo "code_round_1" > model.py
echo '{"loss": 0.5}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

mkdir -p checkpoints/history/round-001
cp model.py checkpoints/history/round-001/model.py

echo "code_round_2" > model.py

assert_success "$AUTOLAB" restore 1
assert_eq "code_round_1" "$(cat model.py)" "artifact should be restored to round 1"
echo "  PASS"

echo "Test 5: promote with multiple artifacts"
TEST_DIR="$TMP_DIR/test5"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
  - config.yaml
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
echo "model_code" > model.py
echo "config_content" > config.yaml
echo '{"f1": 0.90}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

assert_success "$AUTOLAB" promote 1 0.90 "f1"
assert_file_exists "checkpoints/best/model.py"
assert_file_exists "checkpoints/best/config.yaml"
assert_eq "model_code" "$(cat checkpoints/best/model.py)" "model.py should be in checkpoint"
assert_eq "config_content" "$(cat checkpoints/best/config.yaml)" "config.yaml should be in checkpoint"
echo "  PASS"

echo "Test 6: restore with multiple artifacts"
TEST_DIR="$TMP_DIR/test6"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
  - config.yaml
evaluate: "cat metrics.json"
metric:
  name: accuracy
  direction: maximize
EOF
echo "model_v1" > model.py
echo "config_v1" > config.yaml
echo '{"accuracy": 0.70}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

mkdir -p checkpoints/history/round-001
echo "model_v1" > checkpoints/history/round-001/model.py
echo "config_v1" > checkpoints/history/round-001/config.yaml

echo "model_v2" > model.py
echo "config_v2" > config.yaml

assert_success "$AUTOLAB" restore 1
assert_eq "model_v1" "$(cat model.py)" "model.py should be restored"
assert_eq "config_v1" "$(cat config.yaml)" "config.yaml should be restored"
echo "  PASS"

echo "Test 7: restore fails with invalid round number"
TEST_DIR="$TMP_DIR/test7"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
touch model.py

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

assert_failure "$AUTOLAB" restore 999
echo "  PASS"

echo "Test 8: promote updates best checkpoint"
TEST_DIR="$TMP_DIR/test8"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
echo "first_version" > model.py
echo '{"f1": 0.75}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

"$AUTOLAB" promote 1 0.75 "f1" > /dev/null

echo "second_version" > model.py
echo '{"f1": 0.85}' > metrics.json
"$AUTOLAB" promote 2 0.85 "f1" > /dev/null

assert_eq "second_version" "$(cat checkpoints/best/model.py)" "best checkpoint should have second version"
echo "  PASS"

echo "Test 9: discard with non-existent checkpoint"
TEST_DIR="$TMP_DIR/test9"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF
echo "some_code" > model.py
echo '{"f1": 0.80}' > metrics.json

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"
git add .
git commit -m "Initial" > /dev/null

"$AUTOLAB" discard 2>/dev/null || true
echo "  PASS"

echo "Test 10: promote maintains history"
TEST_DIR="$TMP_DIR/test10"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat metrics.json"
metric:
  name: f1
  direction: maximize
EOF

git init > /dev/null
git config user.email "test@test.com"
git config user.name "Test User"

for round in 1 2 3; do
  echo "version_$round" > model.py
  echo "{\"f1\": 0.$((70 + round * 5))}" > metrics.json

  if [[ $round -eq 1 ]]; then
    git add .
    git commit -m "Initial" > /dev/null
  fi

  "$AUTOLAB" promote "$round" "0.$((70 + round * 5))" "f1" > /dev/null
done

assert_dir_exists "checkpoints/history/round-001"
assert_dir_exists "checkpoints/history/round-002"
assert_dir_exists "checkpoints/history/round-003"
echo "  PASS"

echo "OK"
