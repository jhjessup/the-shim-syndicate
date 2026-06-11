# SOP — Operative Launch Protocol
**Document Type:** Shared Agent Protocol  
**Version:** 1.0  
**Applies To:** `@lead`, `@ledger`, `@gavel` (any agent dispatching an `@operative`)  
**Introduced:** Syndicate v3.5.0

---

## Policy

1. Select the lowest-cost tier capable of satisfying the task. Do not over-provision.
2. ALL operative launches MUST go through `scripts/launch-operative.sh`. Direct `claude --model` or `gemini --model` calls bypass the resource governor and are prohibited — no exceptions, including Gavel-dispatched remediation work.
3. Governor holds (exit code 2) are never retried.

---

## Tier Selection

| Target | When to Use |
| :--- | :--- |
| `claude high` | Multi-step reasoning, security-sensitive analysis, architecture decisions requiring deep synthesis |
| `claude medium` | Code implementation, test writing, refactoring, general analysis |
| `claude low` | Log analysis, research synthesis, documentation search, housekeeping |
| `gemini high` | Long-context ingestion (100k+), architecture review requiring extended context window |
| `gemini medium` | Code implementation, moderate-context analysis |
| `gemini low` | Fast retrieval, summarization, documentation |
| `pi` | Quota-controlled execution, headless/air-gapped environments, opencode/openrouter backends |

---

## Tier-to-Model Mapping

| Target | CLI Invocation | Model |
| :--- | :--- | :--- |
| `claude high` | `claude --model claude-opus-4-7 --print` | Claude Opus 4.7 |
| `claude medium` | `claude --model claude-sonnet-4-6 --print` | Claude Sonnet 4.6 |
| `claude low` | `claude --model claude-haiku-4-5-20251001 --print` | Claude Haiku 4.5 |
| `gemini high` | `gemini --model gemini-2.5-pro` | Gemini 2.5 Pro |
| `gemini medium` | `gemini --model gemini-2.5-flash` | Gemini 2.5 Flash |
| `gemini low` | `gemini --model gemini-2.0-flash-lite` | Gemini 2.0 Flash Lite |
| `pi` | `pi --print` | Pre-configured via `pi.shim.json` |

---

## Invocation Syntax

All operative launches **must** go through `scripts/launch-operative.sh`. Direct `claude --model` calls bypass the resource governor and are prohibited.

```bash
# All tiers — claude, gemini, and pi
scripts/launch-operative.sh <tier> \
  --system-prompt "$(cat .syndicate/core/identities/THE_OPERATIVE.md)" \
  --append-system-prompt "$(cat .syndicate/ORACLE.md)" \
  "<prompt>"

# Examples:
scripts/launch-operative.sh claude-medium \
  --system-prompt "$(cat .syndicate/core/identities/THE_OPERATIVE.md)" \
  --append-system-prompt "$(cat .syndicate/ORACLE.md)" \
  "Execute TASK-012 per the dispatch package."

scripts/launch-operative.sh gemini-high \
  --system "$(cat .syndicate/core/identities/THE_OPERATIVE.md)" \
  "Analyze the full codebase dependency graph."

scripts/launch-operative.sh pi \
  --system-prompt "$(cat .syndicate/core/identities/THE_OPERATIVE.md)" \
  --append-system-prompt "$(cat .syndicate/ORACLE.md)" \
  "Execute housekeeping task TASK-031 in headless mode."
```

---

## Governor Behavior on Hold (Exit Code 2)

When `launch-operative.sh` exits with code 2, the operative was blocked by the capacity governor. Example hold output:

```text
[GOVERNOR] CAPACITY HOLD — 75% threshold active (78.3%:47m_remaining).
[GOVERNOR] Operative blocked. Resume in final 60 minutes of the reset window.
```

A hold is never retried. Role-specific responses:

- `@lead` — Inform the operator of the hold and the time remaining. Do not retry.
- `@ledger` — Pause the task queue. Do not dispatch a substitute. Report the hold and time remaining to `@lead`.
- `@gavel` — Defer the remediation dispatch and note the hold in the audit report.

---

## Calibration & Status

Set `SYNDICATE_COST_CAP_USD` in `.env` or edit `~/.claude/syndicate-governor.json` with the USD cost at which your 5-hour window is exhausted. Check current status:

```bash
python3 scripts/update_usage.py --status
```

---

## Dispatch Command Syntax

When generating a dispatch package or issuing a dispatch command, include the target tier:

```text
@operative [claude medium], execute TASK-012 per dispatch package. Report completion to @ledger.
@operative [gemini low], analyze logs/build.log and return the actionable error delta only.
@operative [pi], execute housekeeping task TASK-031 in headless mode. Report completion to @ledger.
```

---

*Document Version: 1.0. Canonical source for all tier definitions — identity files reference this SOP and must not duplicate its tables.*
