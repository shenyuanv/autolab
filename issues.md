# Autolab — GitHub Issues (Phase 1 MVP)

## Issue #1: autolab init — create project structure
**Labels:** phase-1

Implement `autolab init` that creates project directory structure:
- `autolab.yaml` with defaults + comments
- `program.md` template
- `evaluate.sh` skeleton (outputs JSON)
- Directories: `artifacts/`, `data/`, `checkpoints/best/`, `checkpoints/history/`, `results/rounds/`
- Local git init + `.gitignore`

### Test Criteria
- [ ] `autolab init` in empty dir creates all expected files/dirs
- [ ] `autolab init` in existing dir does not overwrite existing files
- [ ] Generated `evaluate.sh` is executable and outputs valid JSON
- [ ] Running `autolab init` twice is idempotent

---

## Issue #2: autolab.yaml parser and validation
**Labels:** phase-1

Parse all config fields: project, artifacts, evaluate, metric, agent, stages, stop, notify.
`autolab validate` checks config + file existence + stage DAG.

### Test Criteria
- [ ] `autolab validate` passes on well-formed project
- [ ] Fails with clear error on missing autolab.yaml
- [ ] Fails on missing artifact files
- [ ] Parser correctly reads all config fields

---

## Issue #3: Sub-agent spawn with prompt template
**Labels:** phase-1

Spawn a research sub-agent for one round:
- Build prompt from template (round number, stage, best metric, recent history)
- Launch `claude -p "..."` (or configured agent command)
- Capture stdout/stderr to `results/rounds/round-NNN/agent.log`
- Track PID for monitoring

### Test Criteria
- [ ] Sub-agent launches with correct prompt containing round/stage/metric info
- [ ] Agent log is saved to correct round directory
- [ ] PID is tracked in state file
- [ ] Prompt includes last 5 experiment summaries

---

## Issue #4: Eval output parsing + metric comparison
**Labels:** phase-1

After sub-agent completes:
- Run `evaluate` command from config
- Parse JSON output for metrics
- Compare primary metric to current best (respecting direction: maximize/minimize)
- Return promote/discard decision

### Test Criteria
- [ ] Parses valid JSON eval output correctly
- [ ] Correctly identifies improvement for maximize metrics
- [ ] Correctly identifies improvement for minimize metrics
- [ ] Handles eval script failure (non-zero exit, invalid JSON)

---

## Issue #5: Checkpoint management (promote/discard/restore)
**Labels:** phase-1

On metric improvement:
- Copy artifact(s) to `checkpoints/best/`
- Save snapshot to `checkpoints/history/round-NNN/`
- `git commit` with message including round + metrics

On regression:
- Restore artifact(s) from `checkpoints/best/`

CLI: `autolab restore [round]` to manually restore a checkpoint.

### Test Criteria
- [ ] Improvement triggers checkpoint creation
- [ ] Regression triggers artifact revert to last best
- [ ] `autolab restore <round>` restores correct checkpoint
- [ ] Git commit is created with correct message on promotion

---

## Issue #6: Core loop (autolab start)
**Labels:** phase-1

Tie everything together in a foreground loop:
1. Read config
2. Determine current state (round, stage, best metric)
3. Spawn sub-agent
4. Wait for completion
5. Run eval + compare
6. Promote or discard
7. Check stop conditions (max_rounds, plateau, time_limit)
8. Check stage transitions
9. Loop or stop

### Test Criteria
- [ ] Loop runs from init to convergence on a simple test project
- [ ] Stops on max_rounds
- [ ] Stops on plateau (N rounds with no improvement)
- [ ] Stage transitions when threshold met
- [ ] State survives restart (autolab start resumes from last round)

---

## Issue #7: autolab status + autolab history
**Labels:** phase-1

`autolab status`: Show current round, stage, best metric, rounds since improvement, ETA.
`autolab history`: Show table of all experiments (round, metric, promoted/discarded, timestamp).

### Test Criteria
- [ ] `autolab status` shows correct current state
- [ ] `autolab history` lists all experiments with metrics
- [ ] Works on empty project (no experiments yet)
- [ ] Works mid-run (active sub-agent)
