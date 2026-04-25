---
name: cran-submit
description: >
  Prepare an R package for CRAN submission. Runs local CRAN-style
  checks (devtools::check with incoming feasibility), spell_check,
  url_check, reverse-dep check, builds the source tarball and the
  reference manual PDF, commits and pushes to trigger the project's
  R-CMD-check GitHub Actions workflow, waits for the matrix to pass,
  fills in cran-comments.md with the real CI outcome, and hands the
  user the tarball path plus submission instructions. Triggers on
  "submit to CRAN", "prepare CRAN submission", "CRAN resubmission",
  "R CMD check for CRAN", "build the CRAN tarball".
user_invocable: true
version: 0.1.0
---

# cran-submit

Skill for preparing an R package for submission or resubmission to
CRAN. Split into a deterministic Bash driver (`scripts/check_and_build.sh`)
that runs the build/check pipeline and emits a JSON status line, and a
model-driven orchestration (this file) that handles prose edits,
commits, and waiting on CI.

## When to invoke

- "prepare a CRAN submission for this package"
- "submit &lt;pkg&gt; to CRAN"
- "CRAN resubmission" (after a declined submission)
- "build the CRAN tarball"
- "run R CMD check for CRAN"

Assume the user is the package maintainer and that the repo is on a
release branch (e.g. `v1.3.0-branch`, `develop`, or `main` / `master`
if they release from trunk).

## Workflow

### 1. Pre-flight

Read and confirm with the user:

- `DESCRIPTION` — `Package` and `Version`. If this is a resubmission
  after CRAN declined, the `Version` should be bumped (patch-level for
  a fix, minor for a new feature set).
- `NEWS.md` — the topmost entry should match the current `Version` and
  describe what changed.
- `cran-comments.md` — the "Submission" section should state why this
  is being submitted (new release vs resubmission) and what's in it.

Run `git status`. If the tree is dirty with unrelated changes, ask the
user whether to proceed or pause. Do **not** silently commit files
that aren't part of the submission.

### 2. Run the driver script

```sh
~/.claude/skills/cran-submit/scripts/check_and_build.sh <pkg-dir>
```

The script runs document, spell_check, url_check, `devtools::check(cran
= TRUE, incoming = TRUE, remote = TRUE, error_on = "note")`, reverse-dep
detection (with opt-in `revdep_check` if any downstream packages
exist), builds the source tarball, and builds the reference manual
PDF.

Parse the **final line** of stdout — it is a JSON object with fields:

```json
{"pkg":"cosmicsig","version":"1.3.1",
 "tarball":"/home/steve/github/cosmicsig_1.3.1.tar.gz",
 "manual":"/home/steve/github/cosmicsig_1.3.1.pdf",
 "errors":0,"warnings":0,"notes":0,
 "revdeps":0,"spell_hits":0,"url_hits":0}
```

If `errors + warnings + notes > 0`, the script already exited non-zero;
surface the last ~60 lines of the R check log and stop. Don't commit
anything.

If `spell_hits > 0` or `url_hits > 0`, show the reported hits to the
user. These are not auto-fatal but usually block CRAN acceptance —
let the user decide whether to fix them before continuing.

### 3. First commit + push (triggers CI)

Stage the package changes (**not** `cran-comments.md` yet):

```sh
git add DESCRIPTION NEWS.md R/ man/ <any other package files changed>
git commit -m "v<version>: <one-line summary>"
git push origin <current-branch>
```

The project's `R-CMD-check.yaml` will fire on the push.

### 4. Wait for CI to go green

Get the run ID of the just-triggered matrix:

```sh
gh run list --branch <current-branch> --limit 1 \
  --json databaseId -q '.[0].databaseId'
```

Then watch it:

```sh
gh run watch <run-id> --exit-status
```

On failure: surface the failing job's log (`gh run view <id> --log-failed`)
and stop. On success: proceed.

### 5. Fill in cran-comments.md

Edit the **R CMD check results** section of `cran-comments.md` to
reflect reality. Template:

```markdown
## R CMD check results

0 ERRORs, 0 WARNINGs, 0 NOTEs across all five environments listed
above (run <run-url>), and 0 ERRORs / 0 WARNINGs / 0 NOTEs on a local
`R CMD check --as-cran` run on the built tarball (with the CRAN
incoming-feasibility check enabled).
```

If `spell_hits` / `url_hits` were non-zero and the user chose to
submit anyway, mention them here explicitly so CRAN reviewers aren't
surprised.

Commit and push with `[skip ci]` so the matrix doesn't re-run for a
comments-only change:

```sh
git add cran-comments.md
git commit -m "Record CI results in cran-comments

[skip ci]"
git push origin <current-branch>
```

(The tarball built in step 2 is unaffected by this edit — `cran-comments.md`
is in `.Rbuildignore` on any well-formed R package.)

### 6. Hand-off to the user

Print, verbatim:

- **Submit (preferred):** From the package root in an R session run
  `devtools::submit_cran()`. It rebuilds the tarball with manual into
  `tempdir()`, prompts "Is your email address <maintainer>?" then
  "Ready to submit <pkg> (<ver>) to CRAN?", uploads to CRAN's intake,
  and writes `CRAN-SUBMISSION` (version + date + SHA) to the package
  root on success.
- **Submit (backup):** If `devtools::submit_cran()` is unavailable or
  chokes (proxy, TLS, devtools install issues), upload
  `<tarball path>` manually at
  https://cran.r-project.org/submit.html. Name and Email fields on
  the form must match `Authors@R` (`cre` role) in `DESCRIPTION`
  exactly.
- **Manual PDF:** `<manual path>` — keep locally for your records;
  CRAN will build its own.
- **CRAN will email the maintainer** (the `cre` role in `Authors@R`)
  with the submission-confirmation link. Click it within 7 days.
- **After CRAN acceptance:**
  - `git tag v<version> && git push origin v<version>`
  - Merge the release branch into `master` (`gh pr create --base
    master --head <release-branch> --title "Release v<version>"`). If
    the project has a pkgdown deployment workflow on `master`, the
    merge re-publishes the package website.
- **If CRAN requests changes:** fix, bump the patch version
  (`1.3.1` → `1.3.2`), update `NEWS.md` and the "Submission" section
  of `cran-comments.md`, and re-invoke this skill.

## Manual dry-run of the driver

To sanity-check the driver script alone without triggering any commit:

```sh
bash ~/.claude/skills/cran-submit/scripts/check_and_build.sh \
  /path/to/your/pkg
```

The final line of stdout is the JSON status. All logs go to stderr,
so you can capture just the JSON with:

```sh
bash .../check_and_build.sh /path/to/pkg 2>/dev/null | tail -1
```

## Assumptions

- `R` and `Rscript` are on `$PATH`.
- `devtools`, `urlchecker`, `desc` are installed (`urlchecker` is
  optional — the script skips the URL check if it's missing).
- `revdepcheck` is installed **if** the package has reverse
  dependencies on CRAN.
- `gh` is authenticated and the current working directory is inside a
  git repo with a GitHub remote named `origin`.
- The project has an `R-CMD-check.yaml` Actions workflow that runs on
  pushes to the current branch (the r-lib/actions reference matrix is
  ideal).
