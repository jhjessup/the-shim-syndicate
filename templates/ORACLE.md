# ORACLE — Project Configuration
**Project:** `{{PROJECT_NAME}}`  
**Hydrated From:** The Shim Syndicate `v{{SYNDICATE_VERSION}}`  
**Hydration Date:** `{{HYDRATION_DATE}}`  
**Active Shim:** `{{SHIM_FILE}}`  
**Operator:** `{{OPERATOR_NAME}}`

---

> **What is the Oracle?**  
> The Oracle is the project-specific configuration layer that overrides and extends the Master Syndicate identities. Every agent (Lead, Ledger, Gavel) reads this file at session start. Directives here take precedence over Master identity defaults for this project only. Changes to this file are permanent for the project — they do not propagate back to the Syndicate Core.

---

## 1. Project Context

### 1.1 Domain & Purpose
```
DOMAIN: {{e.g., FinTech / HealthTech / SaaS / Internal Tooling / etc.}}
PURPOSE: {{One or two sentences describing what this project does and who it serves.}}
STAGE: {{e.g., Greenfield / MVP / Production / Legacy Modernization}}
```

### 1.2 Technology Stack
```
PRIMARY_LANGUAGE: {{e.g., TypeScript, Python, Go, Rust}}
FRAMEWORK: {{e.g., Next.js 14, FastAPI, Gin, Axum}}
DATABASE: {{e.g., PostgreSQL 16, DynamoDB, SQLite}}
INFRASTRUCTURE: {{e.g., AWS ECS, GCP Cloud Run, self-hosted K8s}}
CI_CD: {{e.g., GitHub Actions, GitLab CI, CircleCI}}
PACKAGE_MANAGER: {{e.g., pnpm, poetry, cargo, go modules}}
```

### 1.3 Repository Layout
```
SRC_ROOT: {{e.g., src/ or app/}}
TEST_ROOT: {{e.g., tests/ or __tests__/}}
INFRA_ROOT: {{e.g., infra/ or terraform/}}
DOCS_ROOT: {{e.g., docs/}}
```

---

## 2. Lead Overrides (Architecture & Decision Authority)

### 2.1 Architectural Constraints
<!--
List any hard constraints The Lead must operate within.
Examples: "Must be deployable to an air-gapped environment."
          "No third-party SaaS dependencies for data processing."
          "All services must be stateless — no local file system writes."
-->
- CONSTRAINT_1: {{description}}
- CONSTRAINT_2: {{description}}

### 2.2 Approved Design Patterns
<!--
Patterns explicitly approved for use in this project.
-->
- PATTERN_1: {{e.g., Repository pattern for all database access}}
- PATTERN_2: {{e.g., CQRS for event-driven modules}}

### 2.3 Prohibited Patterns
<!--
Patterns explicitly banned in this project.
-->
- PROHIBITED_1: {{e.g., ORM usage in hot-path queries — use raw SQL}}
- PROHIBITED_2: {{e.g., Global state — all state must be passed explicitly}}

### 2.4 Technical Debt Register
<!--
Acknowledged debt accepted at project start. New debt must be added here
by The Lead with operator sign-off.
-->
| Debt ID | Description | Accepted On | Resolution Condition | Risk Level |
|---------|-------------|-------------|----------------------|------------|
| DEBT-001 | {{description}} | {{date}} | {{condition}} | {{LOW/MED/HIGH}} |

---

## 3. Ledger Overrides (Research & Context Authority)

### 3.1 Approved External Sources
<!--
Ledger is only permitted to cite from these sources for this project.
Prevents hallucinated or unverifiable research.
-->
- Official language/framework documentation
- Project internal ADR directory (`/docs/adr/`)
- CVE/NVD databases for security research
- {{ADDITIONAL_SOURCE_1}}
- {{ADDITIONAL_SOURCE_2}}

### 3.2 Blocked Topics
<!--
Topics Ledger must not research or surface (e.g., competitor analysis,
proprietary data patterns outside project scope).
-->
- BLOCKED_1: {{topic and reason}}

### 3.3 Session Context Anchors
<!--
Pre-loaded context Ledger must treat as foundational for all sessions.
-->
- ANCHOR_1: {{e.g., "The authentication system uses JWT with RS256 signing. Refresh tokens are rotated on each use."}}
- ANCHOR_2: {{e.g., "The primary data model is event-sourced. Never query the aggregate table directly."}}

---

## 4. Gavel Overrides (Audit Authority)

### 4.1 Test Coverage Thresholds
```
CRITICAL_PATH_COVERAGE: {{e.g., 90%}}   # Authentication, payments, data mutations
STANDARD_COVERAGE: {{e.g., 80%}}         # All other business logic
UTILITY_COVERAGE: {{e.g., 60%}}          # Helpers, formatters, non-critical utilities
INFRASTRUCTURE_COVERAGE: {{e.g., N/A}}  # IaC — covered by integration tests
```

### 4.2 Approved Dependencies
<!--
Pre-approved dependencies that do not require Gavel re-review on each update.
Updates to MAJOR versions still require a full dependency audit.
-->
| Package | Approved Version Range | Approval Date | Notes |
|---------|------------------------|---------------|-------|
| {{package}} | {{e.g., ^4.0.0}} | {{date}} | {{notes}} |

### 4.3 Security Exception Register
<!--
Documented exceptions to Gavel's standard security checklist.
Every exception requires an operator signature and a remediation plan.
-->
| Exception ID | Checklist Item | Reason | Operator Sign-Off | Expiry |
|-------------|----------------|--------|-------------------|--------|
| SEC-EX-001 | {{item}} | {{reason}} | {{name — date}} | {{date or "None"}} |

### 4.4 Severity Threshold Overrides
<!--
Adjust default severity thresholds if the project's risk profile requires it.
Example: A medical device project might escalate all MED findings to HIGH.
-->
- DEFAULT THRESHOLDS APPLY (modify below as needed)
- OVERRIDE_1: {{e.g., "All [MED] findings related to PII handling are elevated to [HIGH]"}}

---

## 5. Compliance & Regulatory Requirements

### 5.1 Applicable Standards
<!--
List all regulatory or compliance frameworks that apply to this project.
Gavel must check all audit findings against these standards.
-->
- [ ] GDPR
- [ ] HIPAA
- [ ] SOC 2 Type II
- [ ] PCI DSS
- [ ] ISO 27001
- [ ] {{OTHER}}

### 5.2 Data Classification
```
SENSITIVE_DATA_TYPES: {{e.g., PII, PHI, PCI, Trade Secrets, None}}
DATA_RESIDENCY: {{e.g., EU-only, US-only, No restriction}}
RETENTION_POLICY: {{e.g., 90 days for logs, 7 years for financial records}}
```

---

## 6. Operational Rules for This Project

### 6.1 Branching Strategy
```
MAIN_BRANCH: {{e.g., main}}
DEVELOPMENT_BRANCH: {{e.g., develop}}
FEATURE_PREFIX: {{e.g., feat/}}
HOTFIX_PREFIX: {{e.g., hotfix/}}
RELEASE_PREFIX: {{e.g., release/}}
```

### 6.2 Commit Message Convention
```
FORMAT: {{e.g., Conventional Commits (feat/fix/chore/docs/refactor)}}
MAX_SUBJECT_LENGTH: {{e.g., 72 characters}}
```

### 6.3 Deployment Gate Requirements
<!--
Conditions that must be met before any deployment.
-->
- [ ] All Gavel audit findings resolved (Critical/High are hard blockers)
- [ ] Test coverage thresholds met (see 4.1)
- [ ] AUDIT_LOG.md updated for the session
- [ ] {{ADDITIONAL_GATE_1}}

### 6.4 Session Resource Budget
<!--
Thresholds governing context hygiene and sub-agent delegation for this project.
These are operator-defined per project — defaults below are recommendations.
-->
```
CONTEXT_HYGIENE_THRESHOLD: {{e.g., 60%}}   # Trigger snapshot + /compact at this context load
OPERATIVE_DELEGATION_THRESHOLD: {{e.g., 3 files}}  # Spawn sub-agent when research spans more files than this
OPERATIVE_SYNTHESIS_FORMAT: delta_only     # Sub-agents return actionable delta only — no raw content
SUB_AGENT_MODEL_RESEARCH: {{e.g., claude-haiku-3 | gemini-flash}}  # Model for log/doc analysis operatives
SUB_AGENT_MODEL_IMPLEMENTATION: {{e.g., claude-sonnet-4-6}}       # Model for code-writing operatives
```

---

## 7. Oracle Version History

| Version | Changed By | Date | Summary |
|---------|------------|------|---------|
| 1.0 | {{operator}} | {{HYDRATION_DATE}} | Initial Oracle created by syndicate-init.sh |

---

*This Oracle file is project-local and lives in `.syndicate/ORACLE.md`. It is never committed to the Syndicate Core. All overrides here are scoped to this project exclusively.*
