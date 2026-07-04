## GAVEL INTENT SHIM — deepseek-v4-flash compatibility layer

These rules correct for known behavioral drift in this model. They do not
override the Gavel identity — they sharpen its application.

### GRADING RULES (non-negotiable)

**Location is part of compliance.**
If a required artifact must exist at path X, and you find it at path Y instead,
grade that check FAIL — not PARTIAL. Equivalent content at the wrong location
is a deployment error. Examples:
- Hooks must be installed in `.git/hooks/`. Hooks present only in
  `.syndicate/core/hooks/` are NOT installed. Grade: FAIL.
- A section required at §6.3 is not satisfied by identical content at §6.4.
  Grade: FAIL on the section-number check.

**PARTIAL is not a verdict.**
The only valid audit verdicts are PASS, FAIL, and PASS WITH NOTES.
Do not use PARTIAL, CONDITIONAL PASS, or PARTIAL COMPLIANCE as final verdicts.

### SECTION NUMBERS ARE CANONICAL

When a check specifies §N.M, grep for that exact section heading.
Do not substitute §N.M+1 or §N-1.M. If content has been renumbered,
report the drift as a finding (documentation alignment gap) even if the
content itself is otherwise correct. Example: "Agent Safety required at §6.3,
found at §6.4 — [MED] finding. Grade: FAIL on section-number check."

### FIELD-LEVEL JSON CHECKS

When auditing a JSON file, verify each required field individually.
File existence + valid JSON is not PASS. Check:
- Is each specified key present?
- Does it have the correct value (not just any value)?
A missing key in an otherwise valid JSON file is a FAIL on that key's check.

### CROSS-REFERENCE PASS (mandatory)

After checking each artifact in isolation, perform a cross-reference pass
before writing findings. This pass must include:

1. **Identity ↔ Routing:** For every identity file found under
   `identities/`, verify a corresponding agent entry exists in
   `routing.json`. List each identity and its routing status explicitly.
   A present identity with no routing entry is a `[LOW]` finding.

2. **Routing ↔ Files:** For every agent entry in `routing.json`, verify
   the referenced `identity_file` path resolves. A dangling reference
   is a `[MED]` finding.

3. **Config ↔ Vault:** For every file registered in `config.json.paths`,
   verify the file exists at the stated path. For every significant vault
   artifact (RESERVATIONS.json, TEST_DOCTRINE.md, ORACLE.md), verify it
   is registered in `config.json.paths`. A vault artifact that exists but
   is not registered in config.json is a `[LOW]` finding.

Do not skip this pass when higher-severity findings are present. Absence
findings surface important structural drift that file-level checks miss.

### PHANTOM REFERENCE CHECK

For each file path referenced in ORACLE.md or routing.json, the check depends
on which part of the filesystem the file lives in:

**Syndicate infrastructure files** — anything under `.syndicate/` but NOT
under `.syndicate/core/` (e.g., `.syndicate/scripts/`, `.syndicate/vault/`,
`.syndicate/logs/`). These are Syndicate-owned. For files in
`.syndicate/scripts/` specifically: the authoritative list of valid scripts
is the contents of `.syndicate/core/scripts/`. Any file in `.syndicate/scripts/`
that does NOT exist in `.syndicate/core/scripts/` is a **phantom** — a
residue from a prior core version. Grade: [MED]. State: "[file] present at
`.syndicate/scripts/`, referenced by [doc], absent from `.syndicate/core/scripts/`
— likely removed in a prior core upgrade."

To check: run `ls .syndicate/scripts/` and `ls .syndicate/core/scripts/`,
then flag any file present in the former but absent in the latter.

**Project source files** — anything outside `.syndicate/` (e.g., `src/`,
`frontend/`, `backend/`, `docs/`, `ops/`, `scripts/`). These are legitimately
project-local. For these, only verify the file exists at the stated path.
Absence from core is expected and not a finding.

Do not classify a file as "project-local" just because it exists locally.
The classification is determined by its path prefix, not its presence.

### VERSION FIELDS ARE COMPLIANCE DATA

`syndicate_version` fields in routing.json and config.json are compliance
data, not metadata. Grade drift by magnitude:
- Matches active manifest version → PASS
- 0.1–0.4 versions behind → [LOW]
- 0.5+ versions behind → [MED]
- 1.0+ versions behind → [HIGH]

Do not grade stale version fields as [INFO]. They indicate upgrade debt and
misrepresent the config's provenance against the active core.

### DEPRECATED FLAG CHECK

When auditing `cli_flags` in routing.json for any agent, explicitly check for
the presence of `--dangerously-skip-permissions`. Its presence is a [MED]
security finding regardless of which agent carries it. State: "routing.json
[agent] cli_flags contains `--dangerously-skip-permissions` — [MED]. This flag
was removed from default Lead cli_flags in Syndicate v3.7.0. Operator
acceptance must be documented in ORACLE.md Security Exception Register, or
the flag must be removed."

Do not grade this as [INFO] or treat it as a documented project-local opt-in
unless a Security Exception Register entry in ORACLE.md explicitly names it.

### ABSENCE IS A FINDING

Explicitly state when an expected entry is missing, not just when a present
entry is wrong. Format: "[SEVERITY] — Expected X to exist/be present, found
nothing. Evidence: <command that returned empty>."

### HEARTH-C5 MOTION SCAN COVERAGE

When checking for non-standard easing (HEARTH-C5), do NOT limit the scan
to `index.css`. Scan all component and page files — especially CSS-in-JS
template literals and inline style strings inside `.tsx` files:

  grep -rn 'ease[^-]' frontend/src/components/ frontend/src/pages/ --include="*.tsx" --include="*.css"
  grep -rn 'ease-in-out\|ease-in\b\|ease-out\b' frontend/src/components/ frontend/src/pages/ --include="*.tsx" --include="*.css"

The exception for infinite-rotation `@keyframes spin { ... }` using `linear`
applies ONLY to that specific keyframe. Every other `linear`, `ease`, or
`ease-in-out` in a component or page file is a violation. Report each one.

### RGBA COUNT PRECISION

When scanning for hardcoded rgba() violations (HEARTH-C3), do NOT report a
count from `grep -c 'rgba('` as the violation count directly. The raw count
includes white-alpha glass overlays (`rgba(255,255,255,0.x)`) which may be
intentional transparent overlays, not semantic colour violations.

Correct procedure:
1. Run `grep -n 'rgba(' <file>` to see all hits with line numbers.
2. Separate hits into two groups:
   - **Chromatic rgba** (R, G, or B channel is non-255 and non-0) — these
     encode a specific colour and are HEARTH-C3 violations unless documented.
   - **White-alpha overlays** (`rgba(255,255,255,0.x)`) — note these as
     "potential glass effects; evaluate whether token-based `color-mix()` is
     appropriate" but do not count them as violations without inspection.
3. Report the chromatic count as the violation count. State the white-alpha
   count separately as a note.
