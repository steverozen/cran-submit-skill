#!/usr/bin/env bash
# check_and_build.sh — CRAN submission prep driver.
#
# Usage: check_and_build.sh [pkg-dir]
#   pkg-dir defaults to the current working directory.
#
# Runs, in order:
#   1. devtools::document()
#   2. devtools::spell_check()             (non-fatal; reports hit count)
#   3. urlchecker::url_check()             (non-fatal; reports hit count)
#   4. devtools::check(cran = TRUE,        (HARD FAIL on any NOTE/WARNING/ERROR)
#                      incoming = TRUE,
#                      remote = TRUE,
#                      error_on = "note")
#   4b. Same devtools::check() under R-devel if `Rscript-devel` is on
#       $PATH. CRAN's pretest runs under R-devel and exposes checks that
#       stable R does not (e.g. invalid file URIs in README). HARD FAIL
#       on any NOTE/WARNING/ERROR. Skipped with a warning if missing.
#   5. Reverse-dep detection. If any downstream packages exist on CRAN,
#      runs revdepcheck::revdep_check(num_workers = 2).
#   6. Builds source tarball via devtools::build().
#   7. Builds reference manual PDF via R CMD Rd2pdf.
#
# On success, emits a single JSON line on stdout (last line of stdout):
#
#   {"pkg":"...","version":"...","tarball":"...","manual":"...",
#    "errors":0,"warnings":0,"notes":0,
#    "revdeps":N,"spell_hits":N,"url_hits":N,
#    "rdevel":"ran"|"missing"|"failed"}
#
# All other output (R logs, progress, spell-check table, url-check table)
# goes to stderr. Exits non-zero on check failure or any internal error.

set -euo pipefail

PKG_DIR_ARG="${1:-.}"
if [ ! -d "$PKG_DIR_ARG" ]; then
  echo "check_and_build.sh: package directory not found: $PKG_DIR_ARG" >&2
  exit 2
fi
PKG_DIR="$(cd "$PKG_DIR_ARG" && pwd)"
PARENT_DIR="$(cd "$PKG_DIR/.." && pwd)"

if [ ! -f "$PKG_DIR/DESCRIPTION" ]; then
  echo "check_and_build.sh: no DESCRIPTION in $PKG_DIR" >&2
  exit 2
fi

RESULTS_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULTS_DIR"' EXIT

log() { printf '\n=== %s ===\n' "$*" >&2; }

cd "$PKG_DIR"

# --- 0. package name + version ---------------------------------------------
PKG=$(awk -F': *' '/^Package:/ {print $2; exit}' DESCRIPTION | tr -d '[:space:]')
VER=$(awk -F': *' '/^Version:/ {print $2; exit}' DESCRIPTION | tr -d '[:space:]')
if [ -z "$PKG" ] || [ -z "$VER" ]; then
  echo "check_and_build.sh: could not parse Package/Version from DESCRIPTION" >&2
  exit 2
fi
log "Package: $PKG $VER  (dir: $PKG_DIR)"

# --- 1. document -----------------------------------------------------------
log "devtools::document()"
Rscript --no-init-file -e 'devtools::document()' 1>&2

# --- 2. spell_check --------------------------------------------------------
log "devtools::spell_check()"
Rscript --no-init-file -e "
  res <- devtools::spell_check()
  if (nrow(res) > 0) print(res)
  writeLines(as.character(nrow(res)), '$RESULTS_DIR/spell_hits')
" 1>&2
SPELL_HITS=$(cat "$RESULTS_DIR/spell_hits")

# --- 3. url_check ----------------------------------------------------------
log "urlchecker::url_check()"
Rscript --no-init-file -e "
  if (!requireNamespace('urlchecker', quietly = TRUE)) {
    message('urlchecker not installed; skipping')
    writeLines('0', '$RESULTS_DIR/url_hits')
  } else {
    res <- urlchecker::url_check()
    if (nrow(res) > 0) print(res)
    writeLines(as.character(nrow(res)), '$RESULTS_DIR/url_hits')
  }
" 1>&2
URL_HITS=$(cat "$RESULTS_DIR/url_hits")

# --- 4. devtools::check (stable R) -----------------------------------------
log "devtools::check(cran = TRUE, incoming = TRUE, remote = TRUE, error_on = 'note')"
_R_CHECK_CRAN_INCOMING_=TRUE \
_R_CHECK_CRAN_INCOMING_REMOTE_=TRUE \
_R_CHECK_CRAN_INCOMING_CHECK_FILE_URIS_=TRUE \
_R_CHECK_CRAN_INCOMING_USE_ASPELL_=TRUE \
Rscript --no-init-file -e '
  devtools::check(
    cran     = TRUE,
    incoming = TRUE,
    remote   = TRUE,
    error_on = "note"
  )
' 1>&2

# --- 4b. devtools::check (R-devel, optional) -------------------------------
# CRAN runs --as-cran on R-devel. Stable R may not have R-devel-only checks
# (e.g. invalid file URI in README). Run a second pass under R-devel if
# available; skip cleanly if not installed.
RDEVEL="ran"
if command -v Rscript-devel >/dev/null 2>&1; then
  log "devtools::check() under R-devel ($(R-devel --version 2>&1 | head -1))"
  set +e
  _R_CHECK_CRAN_INCOMING_=TRUE \
  _R_CHECK_CRAN_INCOMING_REMOTE_=TRUE \
  _R_CHECK_CRAN_INCOMING_CHECK_FILE_URIS_=TRUE \
  _R_CHECK_CRAN_INCOMING_USE_ASPELL_=TRUE \
  Rscript-devel --no-init-file -e '
    devtools::check(
      cran     = TRUE,
      incoming = TRUE,
      remote   = TRUE,
      error_on = "note"
    )
  ' 1>&2
  rdevel_rc=$?
  set -e
  if [ "$rdevel_rc" -ne 0 ]; then
    RDEVEL="failed"
    echo "check_and_build.sh: R-devel check failed (rc=$rdevel_rc)" >&2
    exit "$rdevel_rc"
  fi
else
  RDEVEL="missing"
  log "R-devel (Rscript-devel) not on PATH; skipping R-devel check"
  log "  Install with:  sudo apt install -y https://cdn.posit.co/r/ubuntu-2404/pkgs/r-devel_1_amd64.deb"
  log "                 sudo ln -sf /opt/R/devel/bin/Rscript /usr/local/bin/Rscript-devel"
fi

# --- 5. reverse deps -------------------------------------------------------
log "Reverse dependency detection"
Rscript --no-init-file -e "
  options(repos = c(CRAN = 'https://cloud.r-project.org'))
  deps <- tools::package_dependencies(
    '$PKG',
    db = available.packages(),
    reverse = TRUE,
    recursive = FALSE
  )
  writeLines(as.character(length(deps[['$PKG']])), '$RESULTS_DIR/revdeps')
" 1>&2
REVDEPS=$(cat "$RESULTS_DIR/revdeps")
if [ "$REVDEPS" -gt 0 ]; then
  log "Running revdepcheck::revdep_check(num_workers = 2)  (revdeps=$REVDEPS)"
  Rscript --no-init-file -e 'revdepcheck::revdep_check(num_workers = 2)' 1>&2
else
  log "No reverse dependencies on CRAN; skipping revdep_check"
fi

# --- 6. build source tarball ----------------------------------------------
log "devtools::build(path = '..')"
Rscript --no-init-file -e "
  path <- devtools::build(path = normalizePath('..'))
  writeLines(path, '$RESULTS_DIR/tarball')
" 1>&2
TARBALL=$(cat "$RESULTS_DIR/tarball")

# --- 7. reference manual PDF ----------------------------------------------
log "R CMD Rd2pdf"
MANUAL="$PARENT_DIR/${PKG}_${VER}.pdf"
R CMD Rd2pdf --no-preview --force -o "$MANUAL" . 1>&2

# --- 8. emit JSON ---------------------------------------------------------
printf '{"pkg":"%s","version":"%s","tarball":"%s","manual":"%s","errors":0,"warnings":0,"notes":0,"revdeps":%s,"spell_hits":%s,"url_hits":%s,"rdevel":"%s"}\n' \
  "$PKG" "$VER" "$TARBALL" "$MANUAL" "$REVDEPS" "$SPELL_HITS" "$URL_HITS" "$RDEVEL"
