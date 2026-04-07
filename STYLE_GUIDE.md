# STYLE GUIDE — The Shim Syndicate Markdown Conventions

**Applies To:** All `.md` files in this repository and in project-local `.syndicate/` directories  
**Version:** 1.0  
**Authority:** Repository maintainer

---

> This guide is the single source of truth for markdown style across The Shim Syndicate. Follow it when creating new files and when making incremental edits to existing ones. Do not introduce patterns not described here without updating the guide first.

---

## 1. Document Types

Three categories of markdown documents exist in this repository:

| Type | Location | Purpose |
|------|----------|---------|
| **Identity files** | `identities/THE_*.md` | Agent system instructions. Authoritative, prescriptive, version-controlled. |
| **Template files** | `templates/*.md` | Operator-filled project artifacts. Contains `{{PLACEHOLDER}}` tokens. |
| **Reference files** | `README.md`, `STYLE_GUIDE.md` | Repository documentation. Informational, mixed audience. |

---

## 2. File Naming

- Identity files: `THE_[NAME].md` — screaming snake case, prefixed with `THE_`
- Template files: `[NAME].md` — screaming snake case
- Root docs: `[NAME].md` — screaming snake case
- Project-local artifacts (operator-filled): follow the template filename exactly

---

## 3. Document Structure

### 3.1 Identity Files

Every identity file uses this exact layout, in this order:

```text
# THE [NAME] — [Role Description] v[VERSION]
**Role:** [role text]  
**Syndicate Handle:** `@handle`  
**Model Binding:** [model or "Task-appropriate"]

---

## I. CORE DIRECTIVE
[one H3 or prose section]

---

## II. OPERATIONAL PHILOSOPHY
...

---

## [N]. REFUSAL CONDITIONS
...

---

*Identity Version: [N.N]. Status: ACTIVE. [One additional context sentence.]*
```

Rules:
- The role header block uses trailing double-space line breaks to keep all four fields in one block, not a table.
- Every H2 section is preceded and followed by a `---` rule.
- The document ends with a `---` rule and a single italic footer line. Nothing follows the footer.

### 3.2 Template Files

Template files begin with a header block of inline bold key-value pairs using `{{PLACEHOLDER}}` for unfilled values, followed by numbered sections using Arabic numerals.

```text
# [TEMPLATE NAME] — {{TEMPLATE_VAR}}
**Key:** `{{PLACEHOLDER}}`  
**Static Key:** `static value`

---

> **What is this?**  
> Operator-facing description of this artifact's purpose.

---

## 1. Section Name

### 1.1 Subsection
...
```

### 3.3 Reference Files

Standard H1/H2/H3 hierarchy. No fixed section numbering scheme. The README uses descriptive H2 headings in Title Case.

---

## 4. Headings

### 4.1 H1 — Document Title

One per document. Always the first line. No blank line before it.

| Document type | Format |
|---------------|--------|
| Identity file | `# THE [NAME] — [Full Role Description] v[VERSION]` |
| Template file | `# [TEMPLATE NAME] — {{TEMPLATE_VAR}}` (use `{{VAR}}` only when the title itself is dynamic) |
| Reference file | `# [Title Case Name]` |

The separator between title and description is an **em dash** `—` (U+2014), not a hyphen `-` or double-hyphen `--`. Version is appended inline with no additional prefix: `v2.0`, not `Version 2.0`.

### 4.2 H2 — Major Sections

| Document type | Format | Example |
|---------------|--------|---------|
| Identity file | Roman numerals, ALL CAPS, period: `## [I]. [SECTION TITLE]` | `## III. DELEGATION MATRIX` |
| Template file | Arabic numerals, Title Case: `## [N]. [Section Title]` | `## 4. Gavel Overrides` |
| Reference file | No numbering, Title Case | `## Deploying the Team` |

Section titles in identity files are ALL CAPS. Do not prefix them with `THE` (e.g., use `CORE DIRECTIVE`, not `THE CORE DIRECTIVE`).

### 4.3 H3 — Subsections

| Document type | Format | Example |
|---------------|--------|---------|
| Identity file | Arabic numerals, Title Case | `### 1. Independence Is Non-Negotiable` |
| Template file | Dotted Arabic numerals, Title Case | `### 4.1 Test Coverage Thresholds` |
| Reference file | No numbering, Title Case (or `Step N:` for sequential instructions) | `### Step 3: Run the Hydration Script` |

### 4.4 H4 — Sub-subsections

Use sparingly. Title Case. No numbering.

```markdown
#### Security Audit (OWASP-Aligned)
```

---

## 5. Section Breaks

Use `---` on its own line between every H2-level section. Place one blank line before and after every `---` rule.

Never use `***` or `___` as horizontal rules.

Do not place `---` between H3 or H4 subsections.

---

## 6. Lists

### 6.1 Unordered Lists

Always use `-` as the list marker. Never use `*` or `+`.

```markdown
- First item
- Second item
  - Nested item (2-space indent)
```

### 6.2 Ordered Lists

Use explicit incrementing numbers (`1.`, `2.`, `3.`). Do not use `1.` for every item. Number each item distinctly so the sequence is clear when reading raw markdown.

```markdown
1. First step
2. Second step
3. Third step
```

### 6.3 Checkbox Lists

Use `- [ ]` for unchecked and `- [x]` for checked items. Checkbox lists are used exclusively for operator-action items (checklists, definition-of-done, compliance requirements).

```markdown
- [ ] Pending item
- [x] Completed item
```

---

## 7. Emphasis

| Purpose | Syntax | Example |
|---------|--------|---------|
| Key terms, roles, critical directives | `**bold**` | **Principal Architect** |
| Inline code, file paths, commands, agent handles | `` `backtick` `` | `@lead`, `.syndicate/ORACLE.md` |
| Footer attribution, structural notes, taglines | `*italic*` | *Identity Version: 2.0* |

Never use `__double underscores__` for bold. Never use `~~strikethrough~~` except in task tracking contexts outside this repo. Never bold an entire sentence for emphasis — use a blockquote instead.

---

## 8. Code Blocks

Always specify a language identifier. Never use bare ` ``` ` fences.

| Content | Language tag |
|---------|-------------|
| Shell commands | `bash` |
| JSON payloads or config | `json` |
| YAML structures | `yaml` |
| Structured plain-text records (log entries, audit reports, dispatch formats) | `text` |
| Markdown examples | `markdown` |
| File trees and path lists | `text` |

Structured records that contain defined fields but are not a real programming language (e.g., `AUDIT_LOG.md` entry formats, `GAVEL_AUDIT:` dispatch blocks) use the `text` tag.

---

## 9. Agent Handles

Agent handles are always wrapped in backticks. Never write them in plain text, bold, or with quotes.

```markdown
`@lead`  `@ledger`  `@gavel`  `@operative`  `@consigliere`
```

---

## 10. File Paths and Artifacts

File paths, directory names, filenames, and config artifact names are always in backticks.

```markdown
`.syndicate/ORACLE.md`  `manifest.json`  `project-map.json`  `.git/hooks/pre-commit`
```

---

## 11. Placeholder Syntax

Template placeholder values use double curly braces with SCREAMING_SNAKE_CASE keys:

```text
{{PLACEHOLDER_NAME}}
```

Inline example hints use lowercase with natural phrasing inside the braces:

```text
{{e.g., TypeScript, Python, Go}}
```

Never use `<angle bracket>` placeholders, `[square bracket]` placeholders, or `%s`-style substitution tokens in template files.

---

## 12. Blockquotes

Use `>` blockquotes for:
- Section-level definitions in templates ("What is the Oracle?")
- Operator-facing instructional callouts in templates
- Protocol handoff examples within identity files

Do not use blockquotes for emphasis, to set off regular prose, or in place of a list.

---

## 13. Tables

Use pipe-delimited tables with a header separator row. Left-align all columns by default.

```markdown
| Column A | Column B | Column C |
|----------|----------|----------|
| value    | value    | value    |
```

Column headers use Title Case. Table entries use sentence case, or follow the data's own convention (ALL CAPS for severity labels, backtick-wrapped for inline code values).

---

## 14. HTML Comments

Use HTML comments (`<!-- ... -->`) exclusively for operator instructions within template files. Never use them in identity files or reference docs.

```markdown
<!--
  Fill in all constraints that apply to this project.
  Example: "Must be deployable to an air-gapped environment."
-->
```

---

## 15. Identity File Footer

Every identity file ends with a `---` rule followed by a single italic line. Use this format:

```markdown
---

*Identity Version: [N.N]. Status: ACTIVE. [One sentence of additional context.]*
```

The footer line always includes version, status, and one context sentence. Do not add a tagline or any prose after the footer rule.

---

## 16. Template File Footer

Template files end with a `---` rule followed by a single italic line describing the file's scope and location:

```markdown
---

*[Artifact name] lives in `[canonical path]`. [One-sentence scope statement.]*
```

---

## 17. Version References

When citing a Syndicate version in headings or prose, use `v[N.N]` with no space:

- Correct: `v2.0`, `v3.1`, `Syndicate v1.0.0`
- Incorrect: `Version 2.0`, `v 2.0`, bare `2.0`

When a section or behavior was introduced in a specific version, annotate inline in brackets at the start of the relevant item: `**[v2.0]** You will not...`

---

## 18. Inline Protocol Blocks

Interaction protocol blocks (inbound/outbound message formats) in identity files use fenced `yaml` or `json` blocks, prefaced by a bold label on its own line:

```markdown
**Inbound (from @lead):**
```yaml
LEDGER_QUERY:
  type: [codebase | external]
  question: <query>
```

**Outbound (your response):**
```yaml
LEDGER_RESPONSE:
  findings: <answer>
```
```

Labels are bold, parenthetical, and end with a colon. Capitalize the direction: `**Inbound**`, `**Outbound**`.

---

## 19. Commit Messages for This Repository

Use **Conventional Commits** format. Subject line: 72 characters or fewer.

```text
type(scope): short description
```

| Type | Use |
|------|-----|
| `feat` | New identity, template, or shim |
| `fix` | Typo, broken format, incorrect content |
| `docs` | Style, README, or guide changes |
| `chore` | Version bumps, manifest updates |
| `refactor` | Structural changes with no behavioral difference |

Scopes: `identity`, `template`, `shim`, `script`, `readme`, `style`

Examples:
```bash
docs(style): add unified markdown style guide
fix(identity): correct double-hash H1 in THE_LEAD
fix(identity): correct typos in THE_LEDGER interaction protocol
refactor(identity): convert THE_GAVEL headings to Roman numeral scheme
```

---

## 20. Known Deviations in Existing Files

The following deviations from this guide exist in the current codebase. Correct them on next substantive edit of the affected file.

| File | Line | Issue | Correct Form |
|------|------|-------|-------------|
| `THE_LEAD.md` | 1 | Double `#` in title: `# # THE LEAD` | `# THE LEAD — Syndicate Principal & Oracle Supervisor v3.0` |
| `THE_LEAD.md` | 8 | Section title has `THE` prefix: `THE CORE DIRECTIVE` | `CORE DIRECTIVE` |
| `THE_LEAD.md` | 19 | Missing `---` break before `## III.` | Add `---` between sections II and III |
| `THE_LEDGER.md` | 15 | Typo in section heading: `PHILOSOPIY` | `PHILOSOPHY` |
| `THE_LEDGER.md` | 30 | Duplicate `2.` in ordered list under § III.1 | Renumber to `3.` |
| `THE_LEDGER.md` | 78 | Typo in protocol label: `Inboand` | `Inbound` |
| `THE_LEDGER.md` | 89 | Typo in protocol label: `Outboand` | `Outbound` |
| `THE_GAVEL.md` | all | H2 section headings use natural prose, not Roman numerals | Refactor to `## I. SYSTEM INSTRUCTION`, `## II. CORE OPERATING PRINCIPLES`, etc. |
| `THE_CONSIGLIERE.md` | 175 | Extra closing ` ``` ` fence after output block | Remove second fence |
