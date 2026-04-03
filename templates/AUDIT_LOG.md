# AUDIT LOG
**Project:** `{{PROJECT_NAME}}`  
**Syndicate Version:** `v{{SYNDICATE_VERSION}}`  
**Log Initialized:** `{{HYDRATION_DATE}}`

---

> **Operational Rule:** This log is append-only. Entries are never edited or deleted. Every agent (Lead, Ledger, Gavel) must append an entry at the end of every session. The last entry in any session must include a session close marker. This file is the permanent, tamper-evident record of all architectural decisions, audit findings, and research actions taken on this project by The Shim Syndicate.

---

## Log Format Reference

### Architectural Decision Record (ADR)
```
---
[DATE] [LEAD] ADR-{N}: <Decision Title>
CONTEXT: <Why this decision was needed — what problem or constraint drove it>
CHOICE: <What was decided>
ALTERNATIVES_REJECTED:
  - <Option A>: <Why rejected>
  - <Option B>: <Why rejected>
RISK: <Known risks of this choice>
DEBT: <Any technical debt accepted — or "None">
SYNDICATE_VERSION: <Version of Syndicate that made this decision>
---
```

### Gavel Audit Report
```
---
[DATE] [GAVEL] AUDIT-{N}: <Audit Scope Description>
TYPE: [security | quality | architecture | full]
STATUS: [PASS | FAIL | CONDITIONAL PASS]
FINDINGS:
  - [SEVERITY] <Finding Title>
    LOCATION: <file:line or component name>
    DESCRIPTION: <What the issue is>
    EVIDENCE: <Code reference or observation>
    REMEDIATION: <Specific required action>
    RESOLVED: [YES | NO | DEFERRED — <condition and date>]
SUMMARY: <Overall assessment in 1–3 sentences>
SIGN-OFF: The Gavel — v{version} — {date}
---
```

### Ledger Research Record
```
---
[DATE] [LEDGER] RESEARCH-{N}: <Research Query Title>
REQUESTED_BY: [lead | gavel | operator]
TYPE: [codebase | external | historical | standard]
FINDINGS: <Summary of findings with citations>
CONFIDENCE: [HIGH | MEDIUM | LOW | INFERRED]
FLAGS: <Anomalies or contradictions found — or "None">
ACTION_TAKEN: <What was done with this research>
---
```

### Session Close Marker
```
---
[DATE] [SYNDICATE] SESSION-CLOSE
AGENTS_ACTIVE: [lead | ledger | gavel | all]
DECISIONS_MADE: <Count of ADR entries added>
AUDITS_COMPLETED: <Count of AUDIT entries added>
RESEARCH_CONDUCTED: <Count of RESEARCH entries added>
OPEN_ITEMS: <List of unresolved items or "None">
NEXT_SESSION_NOTES: <Context to preserve for the next session>
---
```

---

## Log Entries

<!-- 
  ↓ BEGIN APPENDING ENTRIES BELOW THIS LINE ↓
  Do NOT modify entries above this line.
  Do NOT edit existing entries.
  Append new entries in chronological order.
-->

---
[{{HYDRATION_DATE}}] [SYNDICATE] SESSION-CLOSE
AGENTS_ACTIVE: none
DECISIONS_MADE: 0
AUDITS_COMPLETED: 0
RESEARCH_CONDUCTED: 0
OPEN_ITEMS: None
NEXT_SESSION_NOTES: Project initialized via syndicate-init.sh. ORACLE.md requires operator completion before first active session. All three agents must read ORACLE.md before beginning work.
---
