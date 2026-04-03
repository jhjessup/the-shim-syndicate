# The Shim Syndicate

**An independent, portable AI development team — deployable to any project.**

The Shim Syndicate is a structured, version-controlled system for deploying a multi-agent AI development team into any software project. It defines three specialized agent identities, a backend routing layer (the "shim"), and a hydration mechanism that installs a lightweight project stub without contaminating the host repository.

---

## The Team

| Agent | Handle | Default Model | Responsibility |
|-------|--------|---------------|----------------|
| **The Lead** | `@lead` | Claude (Sonnet 4.6+) | Principal Architect. Technical authority. Decision maker. |
| **The Ledger** | `@ledger` | Gemini (2.5 Pro+) | Context Librarian. Research. Institutional memory. |
| **The Gavel** | `@gavel` | Local (Qwen2.5-Coder / OpenCode) | Independent Auditor. Security. Code quality. Compliance. |

Each agent operates from a system instruction defined in `identities/`. These identities are abstract — they contain no project-specific logic. Project context is injected via the `ORACLE.md` file generated at hydration time.

---

## Repository Structure

```
the-shim-syndicate/
│
├── README.md                    # This file
├── manifest.json                # Version registry and deployment log
│
├── identities/
│   ├── THE_LEAD.md              # Lead identity — architecture and decision authority
│   ├── THE_LEDGER.md            # Ledger identity — context and research authority
│   └── THE_GAVEL.md             # Gavel identity — audit and compliance authority
│
├── shims/
│   ├── routing.schema.json      # JSON Schema for all shim configurations
│   ├── claude.shim.json         # Claude-primary routing (recommended default)
│   ├── gemini.shim.json         # Gemini-primary routing (Google Cloud native projects)
│   └── local.shim.json          # Air-gapped local-only routing (regulated environments)
│
├── templates/
│   ├── ORACLE.md                # Project override template (filled in per project)
│   └── AUDIT_LOG.md             # Permanent audit trail template
│
└── scripts/
    └── syndicate-init.sh        # Project hydration script
```

---

## Deploying the Team to a New Project

### Prerequisites

- `git` and `jq` installed (required)
- At least one of `claude`, `gemini`, `ollama`, or `opencode` CLI available (required for agent operation)
- This repository cloned to a known path on your machine

### Step 1: Clone the Syndicate Core

```bash
git clone https://github.com/jhjessup/the-shim-syndicate.git ~/syndicate
```

### Step 2: Navigate to Your Project

```bash
cd /path/to/your-project
git init  # if not already a git repo
```

### Step 3: Run the Hydration Script

```bash
bash ~/syndicate/scripts/syndicate-init.sh \
  --core ~/syndicate \
  --operator "Your Name" \
  --project "YourProjectName" \
  --shim claude \
  --mode symlink
```

**Options:**

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--core` | path | `$SYNDICATE_CORE_PATH` env | Path to the cloned Syndicate Core |
| `--operator` | string | `git config user.name` | Your name for audit records |
| `--project` | string | current directory name | Project identifier |
| `--shim` | `claude`, `gemini`, `local` | `claude` | Which routing config to activate |
| `--mode` | `symlink`, `subtree` | `symlink` | How to link the Core to the project |
| `--dry-run` | — | false | Preview all actions without executing |

**Mode selection guide:**

- `symlink` — The `.syndicate/core` directory is a symlink to your local Syndicate Core. Fast, space-efficient. Requires the Core path to remain stable. Best for personal machines.
- `subtree` — The Syndicate Core is embedded into the project repo via `git subtree`. Fully portable. Best for team environments, CI/CD, or when you want the project to be self-contained.

### Step 4: Complete the Oracle

The hydration script generates `.syndicate/ORACLE.md` from a template. **This file must be completed before any agent can operate.** Open it and fill in all `{{placeholder}}` values:

```bash
$EDITOR .syndicate/ORACLE.md
```

The Oracle defines:
- Project domain, tech stack, and repository layout
- Architectural constraints and prohibited patterns
- Test coverage thresholds
- Compliance and regulatory requirements
- Approved dependencies and security exceptions

The Lead will refuse to operate without a complete Oracle.

### Step 5: Commit the Syndicate Stub

```bash
git add .syndicate/
git commit -m "chore: hydrate Shim Syndicate v1.0.0"
```

The `.syndicate/` directory is a project asset. It is committed to the project repository so that all team members and CI/CD pipelines have access to the Oracle, routing config, and audit log.

---

## Operating the Team

### Starting The Lead (Claude)

Load `THE_LEAD.md` as the system prompt in your Claude session. Provide the Oracle:

```
System: [contents of .syndicate/core/identities/THE_LEAD.md]

Project Oracle: [contents of .syndicate/ORACLE.md]
Audit Log: [contents of .syndicate/logs/AUDIT_LOG.md]

Begin your session.
```

Via the Claude CLI:
```bash
claude --system-prompt "$(cat .syndicate/core/identities/THE_LEAD.md)" \
       --append "$(cat .syndicate/ORACLE.md)"
```

### Starting The Ledger (Gemini)

The Ledger is designed for large-context windows. Load the full codebase alongside its identity:

```bash
gemini --system "$(cat .syndicate/core/identities/THE_LEDGER.md)" \
       --context "$(cat .syndicate/ORACLE.md)" \
       --files "src/**/*.ts"
```

### Starting The Gavel (Local / OpenCode)

The Gavel runs locally for security-sensitive, air-gapped, or cost-controlled audits:

```bash
# Via OpenCode
opencode --system "$(cat .syndicate/core/identities/THE_GAVEL.md)"

# Via Ollama directly
cat .syndicate/core/identities/THE_GAVEL.md | ollama run qwen2.5-coder:32b
```

Direct The Gavel to the changed files and the audit log. It will produce a structured findings report that must be appended to `.syndicate/logs/AUDIT_LOG.md`.

---

## The Audit Log

`.syndicate/logs/AUDIT_LOG.md` is the **permanent, append-only** record of all decisions and findings made by The Syndicate on this project.

**Rules:**
1. Every agent must append an entry at the end of every session.
2. The last entry in every session must be a `SESSION-CLOSE` marker.
3. Entries are never edited or deleted — only appended.
4. This file is committed to the project repository after every session.

The audit log serves as the chain of custody for all architectural decisions. If a future engineer — human or AI — asks "why was this built this way?", the answer is in the log.

---

## The Shim Layer

The shim configurations in `shims/` define how tasks are routed to specific model backends. The active shim for a project is copied to `.syndicate/routing.json` at hydration time.

Three pre-built shims are provided:

- **`claude.shim.json`** — Lead on Claude, Ledger on Gemini, Gavel on local Ollama. The standard configuration.
- **`gemini.shim.json`** — Lead and Ledger on Gemini, Gavel on Claude. Best for Google Cloud-native projects.
- **`local.shim.json`** — All agents on local models via Ollama/OpenCode. Air-gapped operation for regulated environments.

Custom shims can be created by conforming to `shims/routing.schema.json`.

---

## Versioning

The Syndicate is semantically versioned. The active version is tracked in `manifest.json`.

| Version bump | Trigger |
|-------------|---------|
| **MAJOR** | Breaking changes to identity files or shim schema |
| **MINOR** | New agents, new shims, new template features |
| **PATCH** | Fixes to existing files without behavioral change |

Every project records its hydration version in `.syndicate/config.json`. This allows retroactive auditing — you can always determine which version of The Syndicate was active when a given architectural decision was made.

The `manifest.json` `deployment_registry` records every project that has been hydrated, creating a full deployment history.

---

## Security Model

- **The Gavel runs locally by default.** Security audits never cross a network boundary unless the operator explicitly selects a cloud-backed shim.
- **No secrets are stored in this repository.** API keys are always referenced by environment variable name, never by value.
- **The `.syndicate/` directory is committed to the project repo.** This is intentional — the Oracle, routing config, and audit log are project assets, not secrets.
- **Identity files are immutable in project context.** Never modify `THE_LEAD.md`, `THE_LEDGER.md`, or `THE_GAVEL.md` in a project. Use `ORACLE.md` overrides instead.

---

## Quick Reference

```
# Hydrate a new project
bash ~/syndicate/scripts/syndicate-init.sh --core ~/syndicate --operator "Name" --shim claude

# Start The Lead
claude --system-prompt "$(cat .syndicate/core/identities/THE_LEAD.md)"

# Run a Gavel audit
opencode --system "$(cat .syndicate/core/identities/THE_GAVEL.md)"

# Check the active Syndicate version
jq '.active_version' .syndicate/core/manifest.json

# Review deployment history
jq '.deployment_registry.entries' ~/syndicate/manifest.json
```

---

*The Shim Syndicate — Version 1.0.0*  
*Professional-grade AI development, deployable anywhere.*
