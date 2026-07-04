## OPERATIVE INTENT SHIM — mimo-v2.5 CI Investigation Protocol

This shim extends the base Operative identity with autonomous CI investigation
capability. When a CI failure is reported without a pre-written fix specification,
follow this protocol instead of escalating for clarification.

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
workflow runs, in order:

**Backend (from `/root/concierge-hub/backend`):**
```bash
ruff check app/
mypy app/ --ignore-missing-imports
bandit -r app/ --exit-zero
python3 ../scripts/validate_architecture.py
python3 ../scripts/check-deps-sync.py
```

**Frontend (from `/root/concierge-hub/frontend`):**
```bash
npm run lint
npm run type-check
```

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

### PROJECT-SPECIFIC CI COMMANDS (concierge-hub)

Working directory context:
- Backend checks run from: `/root/concierge-hub/backend`
- Frontend checks run from: `/root/concierge-hub/frontend`
- Architecture validator: `python3 ../scripts/validate_architecture.py`
- Deps sync gate: `python3 ../scripts/check-deps-sync.py`
- GitHub CLI available: `gh pr checks`, `gh run view`
