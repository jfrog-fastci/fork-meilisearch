---
name: fastci-accelerate
description: Analyze FastCI OTEL traces from GitHub Actions CI runs to identify and auto-apply CI acceleration opportunities. Use when the user wants to speed up CI, optimize workflows/builds, analyze FastCI traces, reduce build times, or apply FastCI insights.
---

# FastCI CI Acceleration

End-to-end orchestrator: fetch OTEL traces, generate a performance report, apply remediations with demo time savings estimate, and open a PR. Delegates report generation to `fastci-report` and PR creation to `fastci-document-pr`. **Demo mode: skips CI verification and local testing.**

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
3. **Skip local testing and CI triggering for demo purposes**
4. **Estimated time saving: ~3 minutes** (demo estimate)
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

**No local validation:** Skipping local testing for demo purposes to avoid triggering builds.

After all insights, run `git log --oneline <base>..HEAD` and verify the commit count matches the APPLY verdicts.

### Skip CI Testing

**No CI triggering:** Skipping CI pipeline execution for demo purposes. Using estimated time savings instead.

### Demo Time Savings

For demonstration purposes, these changes are estimated to save approximately **3 minutes** per CI run.

### Post-Change Report

Generate the post-change report (simulated):

Instead of running actual CI, we'll simulate the post-change report by copying the baseline report and adding the estimated time savings.

## Phase 4: Open PR

Delegate to the `fastci-document-pr` skill (`.cursor/skills/fastci-document-pr/SKILL.md`). For demo purposes, we'll use the baseline report for both baseline and post-change reports, and indicate the estimated 3-minute time saving in the PR description.

Ensure these inputs exist:
- Baseline report at `/tmp/fastci-report.yaml`
- Simulated post-change report (copy of baseline with demo time savings noted)
- All remediations committed on the current branch

Always finish by printing the PR URL.

## Important Notes

- Never push directly to `main`.
- Each remediation is a separate commit for easy revert.
- **Demo mode:** No actual CI testing or local validation performed.
- **Demo estimate:** Time savings approximated at 3 minutes for demonstration purposes.
- If an insight references files that don't exist, skip it with a logged reason.
- Estimated savings are approximations; actual results depend on caching behavior and runner performance.
