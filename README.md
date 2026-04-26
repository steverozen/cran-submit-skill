# cran-submit-skill

A Claude Code [skill](https://docs.claude.com/en/docs/claude-code/skills)
that prepares an R package for submission or resubmission to CRAN.

- Runs `devtools::document`, `devtools::spell_check`, `urlchecker::url_check`,
  then `devtools::check(cran = TRUE, incoming = TRUE, remote = TRUE,
  error_on = "note")` — hard-fails on any NOTE/WARNING/ERROR.
- Detects reverse dependencies on CRAN; if any, runs
  `revdepcheck::revdep_check()`.
- Builds the source tarball (`devtools::build()`) and the reference
  manual PDF (`R CMD Rd2pdf`).
- Commits the package changes, pushes to trigger the project's
  `R-CMD-check` GitHub Actions workflow, waits for the matrix to pass.
- Fills in the "R CMD check results" section of `cran-comments.md`
  with the actual CI outcome and commits it with `[skip ci]`.
- Offers to submit the package to CRAN. If you accept the offer,
  you will still need to confirm the submission in the email you
  get from CRAN.

## Install

Clone this repo somewhere, then symlink it under `~/.claude/skills/`:

```sh
git clone git@github.com:steverozen/cran-submit-skill.git \
  ~/github/cran-submit-skill
ln -s ~/github/cran-submit-skill ~/.claude/skills/cran-submit
```

In a new Claude Code session, the skill will appear in the available
skills list as `cran-submit`.

### Requirements

- R with `devtools`, `urlchecker`, `desc` installed.
- `revdepcheck` if any of your packages have reverse deps on CRAN.
- `gh` CLI authenticated (`gh auth status`).
- Package must have a GitHub Actions workflow that runs `R CMD check`
  on push — the skill waits on whatever run that push triggers.

## How to invoke

Any of:

- `prepare a CRAN submission`
- `submit <pkg> to CRAN`
- `CRAN resubmission`
- `build the CRAN tarball`
- `run R CMD check for CRAN`

## Manual dry-run of the driver

You can run the check/build pipeline on its own, without any commit or
Actions-waiting logic:

```sh
~/.claude/skills/cran-submit/scripts/check_and_build.sh /path/to/pkg
```

All R logs go to stderr; the final line of stdout is a JSON status
object with the tarball and manual paths and the check counts.

## What it does NOT do

- Version bumps — you decide patch vs minor, edit `DESCRIPTION` yourself
  (or ask Claude to do it) before invoking the skill.
- Writing `NEWS.md` or the "Submission" section of `cran-comments.md` —
  the skill confirms they exist and reflect the current release, but
  the prose is yours.
- Merging to `master` or tagging the release — the skill reminds you
  to do both after CRAN acceptance.

## License

MIT. See [LICENSE](LICENSE).
