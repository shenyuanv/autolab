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
assert_json_field() {
  local json="$1"
  local field="$2"
  local expected="$3"
  local actual
  actual=$(echo "$json" | jq -r "$field" 2>/dev/null) || fail "Failed to parse JSON: $json"
  assert_eq "$expected" "$actual" "JSON field $field"
}

# Create temp directory for tests
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Test 1: eval parses JSON correctly with single metric"
TEST_DIR="$TMP_DIR/test1"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: f1
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "f1": 0.87,
  "precision": 0.91,
  "recall": 0.84
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.metric' "f1" "metric name"
assert_json_field "$output" '.value' "0.87" "metric value"
assert_json_field "$output" '.direction' "maximize" "metric direction"
echo "  PASS"

echo "Test 2: eval parses JSON with integer metric"
TEST_DIR="$TMP_DIR/test2"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: count
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "count": 42
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.value' "42" "integer metric value"
echo "  PASS"

echo "Test 3: eval fails when metric not in JSON output"
TEST_DIR="$TMP_DIR/test3"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: missing_metric
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "f1": 0.87
}
EOF
touch artifacts/model.py

assert_failure "$AUTOLAB" eval "."
echo "  PASS"

echo "Test 4: eval handles maximize direction correctly"
TEST_DIR="$TMP_DIR/test4"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: accuracy
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "accuracy": 0.95
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.direction' "maximize" "maximize direction"
echo "  PASS"

echo "Test 5: eval handles minimize direction correctly"
TEST_DIR="$TMP_DIR/test5"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: loss
  direction: minimize
EOF
cat > evaluate_output.json <<'EOF'
{
  "loss": 0.12
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.direction' "minimize" "minimize direction"
echo "  PASS"

echo "Test 6: eval defaults to maximize when direction not specified"
TEST_DIR="$TMP_DIR/test6"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: f1
EOF
cat > evaluate_output.json <<'EOF'
{
  "f1": 0.85
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.direction' "maximize" "default to maximize"
echo "  PASS"

echo "Test 7: eval fails when evaluate command exits non-zero"
TEST_DIR="$TMP_DIR/test7"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "exit 1"
metric:
  name: f1
  direction: maximize
EOF
touch artifacts/model.py

assert_failure "$AUTOLAB" eval "."
echo "  PASS"

echo "Test 8: eval fails when evaluate command returns invalid JSON"
TEST_DIR="$TMP_DIR/test8"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "echo 'not valid json'"
metric:
  name: f1
  direction: maximize
EOF
touch artifacts/model.py

assert_failure "$AUTOLAB" eval "."
echo "  PASS"

echo "Test 9: eval handles negative metric values"
TEST_DIR="$TMP_DIR/test9"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: loss
  direction: minimize
EOF
cat > evaluate_output.json <<'EOF'
{
  "loss": -0.5
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.value' "-0.5" "negative metric value"
echo "  PASS"

echo "Test 10: eval handles very small decimal values"
TEST_DIR="$TMP_DIR/test10"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: precision
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "precision": 0.00001
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.value' "0.00001" "very small decimal value"
echo "  PASS"

echo "Test 11: eval fails when autolab.yaml is missing"
TEST_DIR="$TMP_DIR/test11"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

assert_failure "$AUTOLAB" eval "."
echo "  PASS"

echo "Test 12: eval with evaluate script as bash script"
TEST_DIR="$TMP_DIR/test12"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "bash evaluate.sh"
metric:
  name: f1
  direction: maximize
EOF
cat > evaluate.sh <<'EOF'
#!/usr/bin/env bash
echo '{"f1": 0.92}'
EOF
chmod +x evaluate.sh
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.value' "0.92" "bash script evaluation"
echo "  PASS"

echo "Test 13: eval with complex evaluate command"
TEST_DIR="$TMP_DIR/test13"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "python3 -c 'import json; print(json.dumps({\"f1\": 0.88}))'"
metric:
  name: f1
  direction: maximize
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
assert_json_field "$output" '.value' "0.88" "python inline command"
echo "  PASS"

echo "Test 14: eval outputs valid JSON"
TEST_DIR="$TMP_DIR/test14"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: f1
  direction: maximize
EOF
cat > evaluate_output.json <<'EOF'
{
  "f1": 0.75
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
echo "$output" | jq empty || fail "eval output is not valid JSON"
echo "  PASS"

echo "Test 15: eval includes all required fields in output"
TEST_DIR="$TMP_DIR/test15"
mkdir -p "$TEST_DIR/artifacts"
cd "$TEST_DIR"
cat > autolab.yaml <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: accuracy
  direction: minimize
EOF
cat > evaluate_output.json <<'EOF'
{
  "accuracy": 0.05
}
EOF
touch artifacts/model.py

output=$("$AUTOLAB" eval ".")
# Check all three required fields exist
echo "$output" | jq -e '.metric' > /dev/null || fail "missing metric field"
echo "$output" | jq -e '.value' > /dev/null || fail "missing value field"
echo "$output" | jq -e '.direction' > /dev/null || fail "missing direction field"
echo "  PASS"

echo "Test 16: eval works with directory argument"
TEST_DIR="$TMP_DIR/test16"
mkdir -p "$TEST_DIR/artifacts"
cat > "$TEST_DIR/autolab.yaml" <<'EOF'
project: test-project
artifacts:
  - model.py
evaluate: "cat evaluate_output.json"
metric:
  name: f1
  direction: maximize
EOF
cat > "$TEST_DIR/evaluate_output.json" <<'EOF'
{
  "f1": 0.82
}
EOF
touch "$TEST_DIR/artifacts/model.py"

# Run from different directory
output=$("$AUTOLAB" eval "$TEST_DIR")
assert_json_field "$output" '.value' "0.82" "eval with directory argument"
echo "  PASS"

echo "OK"
