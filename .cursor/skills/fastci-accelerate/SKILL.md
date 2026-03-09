---
name: fastci-accelerate
description: Analyze FastCI OTEL traces from GitHub Actions CI runs to identify and auto-apply CI acceleration opportunities. Use when the user wants to speed up CI, optimize workflows/builds, analyze FastCI traces, reduce build times, or apply FastCI insights.
---

# FastCI CI Acceleration

End-to-end orchestrator: fetch OTEL traces, generate a performance report, apply remediations, and open a PR. Delegates report generation to `fastci-report` and PR creation to `fastci-document-pr`.

## Prerequisites

- `gh` CLI installed and authenticated (`gh auth status`)
- `bun` runtime installed (no `bun install` needed — scripts have zero npm dependencies)
- Repository uses GitHub Actions with FastCI (`jfrog-fastci/fastci`) producing `fastci-trace-*` artifacts

## Phase 1: Generate Baseline Report

Delegate to the `fastci-report` skill. Run:

```bash
bun run .cursor/skills/fastci-report/scripts/generate-report.ts \
  --branch <BASE_BRANCH> \
  --limit 10 \
  --output /tmp/fastci-report
```

Read `/tmp/fastci-report.yaml` — this is the **baseline**. Save these numbers for later comparison.

If the script fails due to expired artifacts, report this to the user and work with whatever traces are available.

## Phase 2: Build Improvement Plan

Parse the YAML report and build an improvement plan from the `best_practices:` blocks. Read [insights.md](insights.md) for the full catalog of known insight types and their per-insight safety rules.

**Summary table:** Markdown table of all `best_practices.missing` entries across jobs/steps. Columns: rank, insight title, affected job/step, avg step duration, estimated impact (high/medium/low). Also show `best_practices.implemented` counts so reviewers see what is already healthy.

**Remediation details:** For each missing insight (highest-impact first):
1. Title, affected file path, and line numbers
2. Brief explanation
3. Before/after code snippet showing the exact change
4. Verdict: **APPLY** or **SKIP** (skip when a concrete prerequisite is missing OR the change is redundant because existing configuration already achieves the same intent — cite the reason)

Every insight must have a before/after snippet. If no change is possible, explain exactly what you checked and why.

**Confirmation prompt:** End Phase 2 with a rendered confirmation block:

---

**Proceed with auto-apply?**

**Insights to apply:** N of M (list each with file and change summary)
**Insights to skip:** K (each cites the missing prerequisite)

I will:
1. Create branch `fastci/accelerate-ci-YYYYMMDD`
2. Apply each fix as a separate commit
3. Ask whether to run local validation before CI (e.g., Docker build if Dockerfile changed); on failure, diagnose and offer to fix
4. Push and run CI twice (cold run to populate caches, warm run to measure)
5. Open a PR via `fastci-document-pr`

---

Do not proceed to Phase 3 until the user explicitly confirms.

## Phase 3: Auto-Apply Remediations

### Branch Setup

Branch from the **current branch** (do not checkout `main`):

```bash
git checkout -b fastci/accelerate-ci-$(date +%Y%m%d)
```

If the branch already exists, append a sequence suffix (`-YYYYMMDD-2`).

### Safety Rules

Before editing any file, follow the general rules below **and** the per-insight rules in [insights.md](insights.md):
- Read the target file **in full** and related manifests (`go.mod`, `Cargo.toml`, `Cargo.lock`, `package.json`, lockfiles, version files, workflow YAML).
- Verify every path you reference exists in the repo and build context.
- Derive toolchain versions from the repo — never guess.
- Preserve workflow triggers, Dockerfile semantics, and build config unless the insight requires a change.
- Only skip an insight when a concrete prerequisite is missing (e.g., no lockfile for `npm ci`, no registry login for `--push`). Log the reason.

### Dockerfile Change Protocol

Dockerfile insights are high-risk because they involve multi-stage builds, path dependencies, and tool installation ordering. Follow this plan-validate-execute workflow:

**Step 1 — Inventory the existing Dockerfile.** Before writing any changes, list:
- Every `FROM` stage name and base image
- Every `WORKDIR` and which stages set it
- Every system package install (`apk add`, `apt-get install`) and which stage runs it
- Every `ARG`/`ENV` and which `RUN` steps reference them
- Every `COPY --from=<stage>` in the runtime stage and its absolute path

**Step 2 — Write the complete new Dockerfile.** Do not apply partial edits. Replace the entire file content with the new multi-stage structure following the templates in [insights.md](insights.md). Verify against the post-change checklist in insights.md before saving.

**Step 3 — Validate.** Run `docker build --check .` or lint the Dockerfile for syntax errors. If a linter is not available, manually verify:
- Every `COPY --from=<stage> <src>` references a stage that exists and the `<src>` path is correct given that stage's WORKDIR
- No `RUN` references a binary that hasn't been installed yet in the current stage
- Every `ARG` is declared in the stage that uses it (ARGs reset at each `FROM`)

**Step 4 — Commit** only after validation passes.

### Apply and Commit

**Ordering:** workflow/cache insights first, then build/Dockerfile insights. Within each group, highest impact first. All insights must be committed before pushing.

For each insight:
1. Apply the fix following the protocol above.
2. Validate the change.
3. Commit as a separate commit: `git add -A && git commit -m "FastCI acceleration: <short_description>"`

After all insights, run `git log --oneline <base>..HEAD` and verify the commit count matches the APPLY verdicts.

### Final Validation

After all insights are committed, if any commit modified a Dockerfile, ask the user whether to run a local validation build before pushing:
- If the user confirms, run `docker build -t fastci-validation-test .` (full build, not just `--check`).
- If the build fails, diagnose the error and present the fix to the user. Apply and re-validate only after the user approves the corrective change.
- If the user declines local validation or no Dockerfile was changed, proceed directly to push.

### Two-Run CI Strategy

After pushing the branch, trigger CI twice:
1. **Cold run:** populates remote caches (GHA cache, Docker layer cache). Expect longer build times.
2. **Warm run:** measures actual performance with caches populated. Compare against the baseline report from Phase 1.

Use the warm-run metrics as the post-change report for the PR.

### Post-Change Report

After the warm CI run completes, generate the post-change report by re-running the baseline report script against the new branch:

```bash
bun run .cursor/skills/fastci-report/scripts/generate-report.ts \
  --branch $(git branch --show-current) \
  --limit 2 \
  --output /tmp/fastci-report-post
```

If CI was not triggered (e.g., no push permissions), estimate savings from the insights applied.

## Phase 4: Open PR

Delegate to the `fastci-document-pr` skill (`.cursor/skills/fastci-document-pr/SKILL.md`).

Ensure these inputs exist:
- Baseline report at `/tmp/fastci-report.yaml`
- All remediations committed on the current branch

Always finish by printing the PR URL.

## Important Notes

- Never push directly to `main`.
- Each remediation is a separate commit for easy revert.
- Dockerfile changes are high-risk — always follow the Dockerfile Change Protocol in Phase 3 and the per-insight checklists in [insights.md](insights.md).
- If an insight references files that don't exist, skip it with a logged reason.
- Estimated savings are approximations; actual results depend on caching behavior and runner performance.
