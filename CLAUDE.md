# CLAUDE.md — Autolab Development Guide

## What is Autolab?
Automated research harness. Like lasso orchestrates dev agents (issue → PR → CI → merge), autolab orchestrates research agents (program → experiment → evaluate → converge).

## Architecture
- **Single bash script**: `autolab` (like lasso — one file, no build step)
- **Zero LLM in orchestrator**: All decisions are threshold comparisons on floats
- **Sub-agent per round**: Fresh context each experiment, no path dependency
- **Local git**: Checkpoints via git commit/tag, no GitHub PRs needed

## Key Files
- `autolab` — main CLI script (bash)
- `DESIGN.md` — full design document
- `test/` — test scripts (bash, `test/test-*.sh` pattern)

## Development Rules
1. **No direct pushes to main** — everything through PR + CI
2. **Tests required** — each PR must include tests matching the issue's Test Criteria
3. **PR descriptions** must document changes, approach, and test evidence
4. **Bash style**: Use `set -euo pipefail`, quote all variables, use `local` in functions
5. **Dependencies**: Minimize. `yq` for YAML, `jq` for JSON, `git` for version control. All must be checked at startup.

## Testing
```bash
# Run all tests
bash test/run-tests.sh

# Run specific test
bash test/test-init.sh
```

## Config Format
See `DESIGN.md` section 3 for `autolab.yaml` specification.

## Eval Script Contract
The evaluate command (configured in `autolab.yaml`) must:
- Output valid JSON to stdout
- Include at least the primary metric field
- Exit 0 on success, non-zero on failure
- Be deterministic (same artifacts → same metrics)

Example: `python3 evaluate.py --json` → `{"f1": 0.87, "precision": 0.91, "recall": 0.84}`
