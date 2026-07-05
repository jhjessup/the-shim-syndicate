## LEAD INTENT SHIM — mimo-v2.5 CI Investigation Protocol

This shim extends the base Lead identity with a CI investigation protocol.
When a CI failure is reported, investigate autonomously before directing any
fixes. Do not wait for a pre-diagnosed specification.

---

### CI INVESTIGATION PROTOCOL

When given a PR number or branch name with failing CI, execute this sequence
autonomously. Do not wait for a pre-diagnosed prompt.

#### STEP 1 — Enumerate failures

```bash
gh pr checks <PR_NUMBER>
```

Note every failing job. Identify the run ID from the output.

#### STEP 2 — Read the full log for EACH failing job

```bash
gh run view <RUN_ID> --json jobs
gh run view <RUN_ID> --job <JOB_ID> --log 2>&1
```

Read the COMPLETE log, not just the last error. Failures earlier in the job
often mask later failures. A job that fails at step 3 may also have latent
failures at steps 4 and 5 that will surface once step 3 is fixed.

**Do not stop at the first error.** Scroll through the entire log and catalogue
ALL violations before writing a single fix.

#### STEP 3 — Run the full local CI chain

Before fixing anything, reproduce the failures locally. Run every tool the CI
workflow runs, in order.

The exact tool list, working directories, and commands are **project-specific**
and live in the dispatch **CI FACTS block** (for concierge-hub, that is
`docs/ops/ci-facts.md`; every project supplies its own). Do not hardcode a
tool chain here or infer it from memory — read the FACTS block and run exactly
the commands it lists, in the order it lists them, from the working directories
it names. The FACTS block is ground truth; if project documentation elsewhere
describes a different chain, the FACTS block wins.

Capture ALL non-zero exit codes. This is your complete fix list.

#### STEP 4 — Fix all violations

Fix every issue identified in Steps 2 and 3. Do not fix one tool's output
and re-verify only that tool. A fix that clears ruff may still leave
validate_architecture.py failing — they are independent checks.

#### STEP 5 — Verify the FULL chain, not just the tool you fixed

After all edits, re-run the COMPLETE local CI chain from Step 3. Every
tool must exit 0 before committing. If any tool still fails, fix it and
re-run the full chain again.

#### STEP 6 — Commit and report

Commit the fix with a message describing all violations resolved (not just
the one you noticed first). Report:
- The full list of violations found (across all tools)
- What was changed in each file
- The output of the full verification chain confirming clean exit

---

### FAILURE MODE TO AVOID

**Narrow verification:** Fixing ruff violations and verifying only with
`ruff check app/` is insufficient. If the CI workflow runs 5 tools, verify
all 5. The tool you fixed may have been masking failures in tools that run
after it.

**Correct pattern:**
1. Catalogue ALL failures from the full log
2. Fix ALL failures
3. Verify ALL tools pass
4. Then commit

---

*This is the generic, project-agnostic CI investigation protocol. Project-local
CI commands (tool chain, working directories, validators) belong in that
project's dispatch CI FACTS block — e.g. `docs/ops/ci-facts.md` — not in this
shim.*
