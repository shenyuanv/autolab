# Autolab — Design Document

**Automated Research Harness**

Like lasso orchestrates dev agents (issue → PR → CI → merge), autolab orchestrates research agents (program → experiment → evaluate → converge).

---

## 1. Problem Statement

Running iterative research experiments with AI agents currently requires:
- Manual spawning of agents
- Manual monitoring of progress (tail logs)
- No structured experiment tracking
- No baseline management (easy to regress)
- No roadmap enforcement (agents wander)
- Single long session → context pollution, path dependency

**Autolab solves this by:**
- Spawning a fresh sub-agent per experiment round (clean context)
- Automatically evaluating results against defined metrics
- Promoting improvements, discarding regressions
- Enforcing a staged roadmap
- Recording complete evidence for every round

---

## 2. Core Concepts

### Project
A directory containing a research problem. Minimal structure:

```
my-research/
├── autolab.yaml       ← project config (roadmap, metrics, stop conditions)
├── program.md         ← instructions for the research agent
├── evaluate.sh        ← evaluation script (returns metrics as JSON)
├── artifacts/         ← files the agent modifies
│   └── model.py       
├── data/              ← read-only input data
│   └── dataset.jsonl  
├── checkpoints/       ← auto-managed by autolab
│   ├── best/          ← current best artifact snapshot
│   └── history/       ← all promoted checkpoints
└── results/
    ├── experiments.jsonl  ← one line per round
    └── rounds/            ← per-round evidence
        ├── round-001/
        │   ├── agent.log
        │   ├── eval-output.txt
        │   └── diff.patch
        └── round-002/
            └── ...
```

### Stage
A phase in the research roadmap with:
- A goal (human-readable)
- A metric + threshold (machine-checkable)
- Required evidence
- Prerequisite stages

### Round
One sub-agent invocation. The agent:
1. Reads program.md + current artifact + recent experiment history
2. Makes changes to artifact(s)
3. Runs evaluate.sh
4. Exits

The orchestrator then:
1. Parses eval output (JSON metrics)
2. Compares to current best
3. Promotes or discards
4. Decides: next round, stage transition, or stop

### Artifact
The file(s) the agent is allowed to modify. Everything else is read-only.
Artifacts are version-controlled via checkpoints.

### Checkpoint
A snapshot of artifacts + eval metrics at a point where metrics improved.
Only created on improvement (promoted). Never on regression.

---

## 3. Configuration (autolab.yaml)

```yaml
project: spers-detection
description: "Optimize SPERS detection rules for AI agent behavior monitoring"

# What the agent modifies
artifacts:
  - detection_rules.py

# How to evaluate (must output JSON to stdout)
evaluate: "python3 evaluate.py --json"

# Primary metric to optimize
metric:
  name: f1
  direction: maximize  # or minimize (e.g., val_loss)
  
# Agent configuration
agent:
  command: claude  # or codex, gemini, etc.
  flags: "--dangerously-skip-permissions --max-turns 30"
  # Each round gets max 30 turns (enough for 1-3 changes + eval)

# Roadmap
stages:
  - id: baseline
    goal: "Establish detection baseline"
    metric: f1
    threshold: 0.60
    
  - id: reduce-fp
    goal: "Reduce false positives on real traces to <5%"
    metric: fp_rate_real
    threshold: 0.05
    direction: minimize
    requires: baseline
    
  - id: high-recall
    goal: "Detect >90% of attacks"
    metric: recall
    threshold: 0.90
    requires: reduce-fp
    
  - id: convergence
    goal: "Achieve F1 >= 0.95"
    metric: f1
    threshold: 0.95
    requires: high-recall

# Stop conditions
stop:
  max_rounds: 100
  plateau: 5          # stop after N rounds with no improvement
  time_limit: "4h"    # wall clock limit

# Notifications
notify:
  slack_channel: C0AF9C7J7U4  # #work
  on:
    - stage_complete
    - plateau
    - target_reached
    - error
```

---

## 4. Data Flow

```
                    ┌─────────────────────┐
                    │   autolab.yaml      │
                    │   (config)          │
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │  autolab poll       │
                    │  (bash orchestrator) │
                    │  ZERO LLM tokens    │
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
        ┌───────────┐  ┌───────────┐  ┌───────────┐
        │ Round 1   │  │ Round 2   │  │ Round 3   │
        │ sub-agent │  │ sub-agent │  │ sub-agent │
        │ (claude)  │  │ (claude)  │  │ (codex)   │
        └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
              │               │               │
              ▼               ▼               ▼
        ┌───────────────────────────────────────────┐
        │              evaluate.sh                   │
        │         (fixed, deterministic)             │
        │   outputs: {"f1": 0.87, "recall": 0.84}   │
        └───────────────────┬───────────────────────┘
                            │
                            ▼
              ┌─────────────────────────┐
              │  Promote or Discard     │
              │  (bash: compare floats) │
              └─────────────────────────┘
              │                         │
    improved  │                         │ regressed
              ▼                         ▼
    ┌─────────────────┐     ┌─────────────────┐
    │ Checkpoint       │     │ Revert artifact │
    │ git commit       │     │ to last best    │
    │ update best/     │     │                 │
    └─────────────────┘     └─────────────────┘
```

---

## 5. Sub-Agent Prompt Template

Each round, the sub-agent receives:

```markdown
# Research Round {N}

## Your Task
Read program.md for the full research context. You are in stage: {stage_id}.
Goal: {stage_goal}
Target: {metric_name} {direction} {threshold} (current best: {current_value})

## Current State
- Round: {N} of max {max_rounds}
- Stage: {stage_id} ({stage_index}/{total_stages})
- Best {metric}: {best_value} (achieved in round {best_round})
- Rounds since improvement: {plateau_count}

## Recent Experiment History
{last 5-10 experiment summaries from experiments.jsonl}

## Instructions
1. Read program.md for detailed research instructions
2. Examine the current artifact(s): {artifact_list}
3. Make ONE focused improvement
4. Run the evaluation: {evaluate_command}
5. Report the results

Do NOT try multiple changes in one round. One change, one eval.
```

---

## 6. CLI Interface

```bash
# Project management
autolab init                    # Initialize project in current dir
autolab validate                # Check autolab.yaml + evaluate.sh work

# Running experiments
autolab start                   # Begin research loop (foreground)
autolab spawn                   # Start research loop (background, daemonized)
autolab stop                    # Gracefully stop after current round

# Monitoring
autolab status                  # Current stage, round, best metric, ETA
autolab log                     # Tail current round's agent log
autolab history                 # Show all experiments as table
autolab chart                   # ASCII chart of metric over rounds

# Baseline management
autolab checkpoint              # Force checkpoint current state
autolab restore [round]         # Restore artifact to specific checkpoint
autolab diff [round1] [round2]  # Show artifact diff between checkpoints

# Evidence
autolab evidence [stage]        # Show evidence for stage completion
autolab export                  # Export full experiment record (JSON/CSV)

# Advanced
autolab resume                  # Resume from last checkpoint
autolab rerun [round]           # Re-run a specific round
autolab config set key value    # Modify config
```

---

## 7. Orchestrator Design (autolab poll)

Like lasso poll — pure bash, zero LLM tokens, runs as cron or loop.

```bash
autolab_poll() {
    # 1. Check if sub-agent is still running
    if agent_running; then
        check_timeout
        return
    fi
    
    # 2. Agent finished — read eval results
    metrics=$(parse_eval_output "$round_dir/eval-output.txt")
    
    # 3. Compare to best
    if metric_improved "$metrics" "$best_metrics"; then
        promote_checkpoint "$round"
        update_best "$metrics"
        reset_plateau_counter
    else
        revert_artifact
        increment_plateau_counter
    fi
    
    # 4. Check stop conditions
    if should_stop; then
        notify_slack "Research complete" "$final_summary"
        return
    fi
    
    # 5. Check stage transition
    if stage_threshold_met; then
        advance_stage
        notify_slack "Stage complete: $stage_id"
    fi
    
    # 6. Spawn next round
    spawn_sub_agent "$((round + 1))"
}
```

Poll interval: 30 seconds (sub-agents typically run 2-10 minutes per round).

---

## 8. Key Design Decisions

### Why sub-agent per round (not single long session)?
- **Clean context**: No path dependency from previous attempts
- **Agent-agnostic**: Can rotate between Claude/Codex/Gemini per round
- **Unlimited rounds**: Not bounded by context window
- **Natural evidence**: Each round is a complete, self-contained record
- **Fault tolerant**: Agent crash = just one lost round, not entire experiment

### Why bash orchestrator (not LLM)?
- **Zero marginal cost**: Poll/compare/checkpoint costs nothing
- **Deterministic**: Float comparison, file copy — no hallucination risk
- **Fast**: <100ms per poll cycle
- **Auditable**: Every decision is traceable to a threshold check

### Why local git (not GitHub)?
- **Speed**: No network latency, no API rate limits
- **Privacy**: Research artifacts stay local until ready to share
- **Simplicity**: `git commit` + `git tag` is all we need
- Research doesn't need PRs, code review, or CI — the evaluate.sh IS the CI

### Why fixed evaluate.sh (agent can't modify)?
- **Prevents gaming**: Agent optimizes the metric, not the measurement
- **Reproducibility**: Same eval across all rounds
- **Trust**: Human controls what "good" means

---

## 9. Comparison with Lasso

| Aspect | Lasso | Autolab |
|--------|-------|---------|
| Domain | Software development | Iterative research |
| Unit of work | GitHub issue | Research round |
| Agent lifetime | One session per issue | One session per round |
| Feedback signal | CI pass/fail, PR review | Eval metric (float) |
| State tracking | sessions.json | experiments.jsonl |
| Version control | GitHub (branch/PR) | Local git (commit/tag) |
| Stop condition | PR merged or escalate | Metric converged or plateau |
| Orchestrator | lasso poll (bash) | autolab poll (bash) |
| Notifications | Slack | Slack |
| Monitoring | lasso status | autolab status |
| Knowledge | knowledge/*.md per repo | experiment history per project |

**Shared DNA:**
- Zero-LLM orchestrator
- Sub-agent per unit of work
- Slack notifications
- Bash-first, cron-compatible
- Evidence-first (everything logged)

---

## 10. Implementation Roadmap

### Phase 1: Core Loop (MVP)
- [ ] `autolab init` — create project structure
- [ ] `autolab.yaml` parser
- [ ] Sub-agent spawn with prompt template
- [ ] Eval output parsing (JSON)
- [ ] Metric comparison (promote/discard)
- [ ] Local git checkpoint on improvement
- [ ] `autolab start` (foreground loop)
- [ ] `autolab status` / `autolab history`
- **Dogfood**: Run on spers-detection project

### Phase 2: Production Features
- [ ] `autolab spawn` (background daemon)
- [ ] `autolab poll` (cron-compatible)
- [ ] Slack notifications
- [ ] Stage/roadmap enforcement
- [ ] Plateau detection + auto-stop
- [ ] Time limit
- [ ] `autolab chart` (ASCII metric graph)
- [ ] `autolab restore` / `autolab diff`

### Phase 3: Advanced
- [ ] Multi-agent per round (parallel exploration)
- [ ] Agent rotation (round-robin Claude/Codex/Gemini)
- [ ] Evidence export (JSON/CSV/HTML report)
- [ ] MLflow integration (optional)
- [ ] Cross-project comparison
- [ ] `autolab run` batch mode (like lasso run)

---

## 11. First Dogfood Case

Migrate the current manual spers-detection autolab to the new system:

```yaml
project: spers-detection
artifacts:
  - detection_rules.py
evaluate: "python3 evaluate.py --json"
metric:
  name: f1
  direction: maximize
stages:
  - id: baseline
    threshold: 0.60
  - id: low-fp
    metric: fp_rate_real
    threshold: 0.05
    direction: minimize
  - id: high-f1
    threshold: 0.95
```

This validates the entire pipeline end-to-end with real data.
