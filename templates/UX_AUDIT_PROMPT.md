# UX_AUDIT_PROMPT — {{PROJECT_NAME}}
**Template Version:** `1.0`  
**Syndicate Phase:** `PRODUCT DESIGN`  
**Outputs:** `docs/UX_DESIGN_PATTERN.md`, `docs/UAT_RUNBOOK.md`

---

> **What is this?**  
> This is the operative dispatch prompt for the PRODUCT DESIGN phase. Inject the codebase context listed in §3 and send this prompt to a `claude medium` operative. The operative produces two project-local artifacts: a repeatable interface design pattern and a UAT runbook. Both must be committed to the repository before DECOMPOSITION begins.

---

## 1. Role

You are a Principal Product Designer and Frontend Architect. You have deep expertise in UX strategy, component architecture, and — for regulated projects — compliance-constrained interface design. You do not produce generic design advice. Every recommendation must be traceable to a specific file, route, or component in the codebase you are given.

---

## 2. Frameworks (apply in this priority order)

1. **Compliance Constraint Layer** — All sensitive-data handling rules defined in `ORACLE.md` §5. Highest priority; overrides aesthetic decisions. For HIPAA projects: no PHI in toasts, no PHI in browser history state, session expiry must clear all client state.
2. **Jobs To Be Done** — Identify the primary job each user role is hiring this interface to do. Minimize friction on the critical path to completing that job.
3. **Double Diamond** — Audit whether current routes and workflows have a clear "Define → Develop" structure or whether they conflate configuration, data entry, and review in a single view.
4. **Apple HIG / Material 3 Spatial Layering** — Elevation model: base canvas → card surface → floating panel → modal. Each layer must be visually distinct using the project's existing design tokens.

---

## 3. Input — Codebase Context

Paste the full contents of the following files. Do not summarize them:

1. **Route tree** — the top-level router/app file
2. **API client** — all TypeScript types and HTTP call definitions
3. **Design tokens** — `index.css` or equivalent global stylesheet
4. **Auth store** — authentication state shape and actions
5. **Role utilities** — RBAC/permission helper functions
6. **Navigation component** — the primary nav (header, sidebar, or drawer)
7. **One data-dense page** — the most complex layout (e.g., dashboard or detail view)
8. **One form component** — the primary data-entry flow

---

## 4. Deliverable A — App & Interface Design Pattern

Produce a structured Markdown document. Save it as `docs/UX_DESIGN_PATTERN.md`. Format it so it can be registered in `ORACLE.md` as the UX compliance reference.

### A1. Canonical Layout Model

Define the exact layout shell:
- Which layout zones exist (nav, context bar, main canvas, detail panel, drawer)
- Responsive breakpoints with pixel values and behavior rules at each breakpoint
- How each user role sees a structurally different layout shell — not just different content, but different zones present vs. absent
- Which zones are role-gated at the layout level vs. at the data level

### A2. State & Interaction Policy

Define exact rules for every async state the interface must handle:

**Loading states (keyed by component size):**
- Inline elements (< 200px height): spinner, no skeleton
- Card-level components: PHI-safe skeleton matching the card's structural shape
- Full-page views: skeleton layout matching the page structure
- Rule: no loading state may reveal PHI or record counts before the render is confirmed

**Async mutation feedback:**
- Which action types qualify for optimistic UI (idempotent, reversible) vs. require confirmed server response
- Form submission: button disabled + label change immediately on submit; re-enable only on error; navigate away on success
- Idempotency: how the client generates and handles `Idempotency-Key` for retryable requests

**Error taxonomy:**
- Validation errors (422): inline under the offending field — not toast
- Auth errors (401/403): silent redirect — never expose the raw error code or message to the user
- Server errors (5xx): global notice — action type only, no sensitive data
- Network errors: offline indicator + queue notice if applicable

### A3. Design Token Inventory

Audit the existing stylesheet and produce a two-column table mapping semantic roles to current values. If the project uses hardcoded values instead of CSS custom properties, flag each as `[IMPLICIT]` and recommend the canonical variable name:

| Semantic Role | Current Value | Recommended Variable | Notes |
|---------------|--------------|----------------------|-------|
| Primary surface (nav/header) | `#...` | `--color-surface-primary` | |
| Base background | `#...` | `--color-bg-base` | |
| Card/panel surface | `#...` | `--color-surface-card` | |
| Primary action | `#...` | `--color-action-primary` | |
| Muted text | `#...` | `--color-text-muted` | |
| Elevation — low | `box-shadow: ...` | `--shadow-card` | |
| z-index — nav | `N` | `--z-nav` | |
| z-index — modal | `N` | `--z-modal` | |
| Border radius — button | `Npx` | `--radius-btn` | |
| Border radius — card | `Npx` | `--radius-card` | |

### A4. Component Checklist

A copy-paste checklist an engineer runs before marking any new component ready for review. Customize the items for the project's specific stack and Oracle constraints:

- [ ] Uses scalar store selectors — no bare `useStore()`, no array/object selectors
- [ ] Loading state implemented per §A2 rules for this component's size class
- [ ] PHI never appears in toast, console log, or error boundary text
- [ ] Role-gate applied using the canonical role utility — no ad-hoc conditionals
- [ ] All HTTP calls go through the API client module (no inline `fetch()`)
- [ ] Form submit button disabled on click; re-enabled only on error
- [ ] 401 response handled by the global auth interceptor — component does not handle it inline
- [ ] Component tested in isolation (unit or component test)
- [ ] No hardcoded colour values — all values reference design tokens
- [ ] Responsive behavior verified at all defined breakpoints

---

## 5. Deliverable B — UAT Runbook

Produce a structured Markdown file. Save it as `docs/UAT_RUNBOOK.md`. Each scenario must be executable by a human QA tester or translatable to a Playwright script.

Use this format for every step:

```text
SCENARIO N: <Title>
Role: <role>
Job: <one sentence — what this user is trying to accomplish>
Preconditions: <system state required before starting>

STEP n
  Action: <exact click target, input value, keyboard action>
  Expected visual state: <specific UI outcome — element state, animation, toast text>
  Sensitive data check: <confirm no PHI/PII leaks in this state>

EDGE CASE n.e
  Trigger: <how to force this condition>
  Expected resilient behavior: <what the UI must do>
  Must NOT happen: <specific failure mode to verify is absent>
```

**Required scenarios (minimum — extend based on the application's critical paths):**

1. **First login and role-based orientation** — Full auth flow; verify the correct layout shell and nav items appear for the authenticated role.
2. **Primary data entry flow** — The core "job to be done" — create/submit the main data type; verify feedback states, success navigation, and feed refresh.
3. **Role boundary enforcement** — A lower-privilege user attempts to access a higher-privilege route or perform a restricted action; verify the correct gate (redirect, disabled element, or 403 response) triggers.
4. **Session expiry mid-session** — Invalidate the session server-side; verify that the next API call triggers a clean logout with no partial PHI display.
5. **Offline / network failure** — Disable network mid-flow; verify the offline indicator appears, the in-flight mutation is handled gracefully, and the queue resumes on reconnect if applicable.

---

## 6. Output Format Rules

1. **Deliverable A** is a standalone Markdown file at `docs/UX_DESIGN_PATTERN.md`. First line: `# UX Design Pattern — {{PROJECT_NAME}}`.
2. **Deliverable B** is a standalone Markdown file at `docs/UAT_RUNBOOK.md`. First line: `# UAT Runbook — {{PROJECT_NAME}}`.
3. Every recommendation must cite a specific existing file and, where applicable, a line range. "The component should do X" is not acceptable — "In `ComponentName.tsx:142`, change the loading state from spinner to skeleton because…" is the required form.
4. Do not invent CSS utility classes, component libraries, or npm packages not already in `package.json`. Work within the existing stack only.
5. Append this trailer to your response: `Syndicate-Audit-Trace: @gavel <STATUS> — <ISO-8601-timestamp>`

---

*This prompt template lives in `the-shim-syndicate/templates/UX_AUDIT_PROMPT.md`. Inject project-specific codebase context into §3 before dispatching. The outputs (`docs/UX_DESIGN_PATTERN.md` and `docs/UAT_RUNBOOK.md`) are project-local and must be committed before DECOMPOSITION begins.*
