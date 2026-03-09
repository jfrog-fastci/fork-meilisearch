---
name: fastci-accelerate
description: Analyze FastCI OTEL traces from GitHub Actions CI runs to identify and auto-apply CI acceleration opportunities. Use when the user wants to speed up CI, optimize workflows/builds, analyze FastCI traces, reduce build times, or apply FastCI insights.
---

# FastCI CI Acceleration

End-to-end orchestrator: fetch OTEL traces, generate a performance report, apply remediations, verify in CI, and open a PR. Delegates report generation to `fastci-report` and PR creation to `fastci-document-pr`.

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
4. Verdict: **APPLY** or **SKIP** (skip only when a concrete prerequisite is missing — cite it)

Every insight must have a before/after snippet. If no change is possible, explain exactly what you checked and why.

**Confirmation prompt:** End Phase 2 with a rendered confirmation block:

---

**Proceed with auto-apply?**

**Insights to apply:** N of M (list each with file and change summary)
**Insights to skip:** K (each cites the missing prerequisite)

I will:
1. Create branch `fastci/accelerate-ci-YYYYMMDD`
2. Apply each fix as a separate commit
3. Run local validation before CI (e.g., build if Dockerfile changed); on failure, fix and retry up to 3 times
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
- Read the target file and related manifests (`go.mod`, `package.json`, lockfiles, version files, workflow YAML).
- Verify every path you reference exists in the repo and build context.
- Derive toolchain versions from the repo — never guess.
- Preserve workflow triggers, Dockerfile semantics, and build config unless the insight requires a change.
- Only skip an insight when a concrete prerequisite is missing (e.g., no lockfile for `npm ci`, no registry login for `--push`). Log the reason.

### Apply and Commit

**Ordering:** workflow/cache insights first, then build/Dockerfile insights. Within each group, highest impact first. All insights must be committed before pushing.

For each insight:
1. Apply the fix.
2. Commit as a separate commit: `git add -A && git commit -m "FastCI acceleration: <short_description>"`

**Validation (once, before CI):** Before pushing, run local validation if any commit touched build artifacts (e.g., `docker build -t fastci-validation-test .` for Dockerfile changes). If validation fails, fix the issue and retry up to 3 times; on success, proceed to push. Workflow-only changes skip local validation.

After all insights, run `git log --oneline <base>..HEAD` and verify the commit count matches the APPLY verdicts.

### Two-Run CI Strategy

Push and run CI twice:

1. **Run 1 (cold):** `git push -u origin HEAD` then `gh run watch <RUN_ID> --exit-status`. This populates caches. If CI fails, revert the offending commit, push, and retry (up to 3 times).
2. **Run 2 (warm):** `gh workflow run <WORKFLOW>.yml --ref $(git branch --show-current)` (or `gh run rerun <RUN_ID>`). This measures acceleration with warm caches. The warm run should be faster than Run 1.

### Post-Change Report

Generate the post-change report:

```bash
bun run .cursor/skills/fastci-report/scripts/generate-report.ts \
  --branch $(git branch --show-current) \
  --limit 2 \
  --output /tmp/fastci-report-after
```

Compare `/tmp/fastci-report-after.yaml` against the baseline.

## Phase 4: Open PR

Delegate to the `fastci-document-pr` skill (`.cursor/skills/fastci-document-pr/SKILL.md`). Ensure these inputs exist:
- Baseline report at `/tmp/fastci-report.yaml`
- Post-change report at `/tmp/fastci-report-after.yaml`
- All remediations committed on the current branch

Always finish by printing the PR URL.

## Important Notes

- Never push directly to `main`.
- Each remediation is a separate commit for easy revert.
- Run CI at least twice: first run warms caches, second measures acceleration.
- If an insight references files that don't exist, skip it with a logged reason.
- Estimated savings are approximations; actual results depend on caching behavior and runner performance.
