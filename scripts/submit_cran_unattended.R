#!/usr/bin/env Rscript
# submit_cran_unattended.R — non-interactive wrapper around
# devtools::submit_cran().
#
# devtools::submit_cran() guards the upload with multiple yesno() prompts
# ("Is your email address X?" and "Ready to submit ... to CRAN?").
# yesno() shuffles its options each call, so positional input is
# unreliable. Instead we override yesno() in the devtools namespace
# to return FALSE (yesno() returns TRUE only when the user picks an
# abort option, so FALSE means "proceed").
#
# Usage:  Rscript submit_cran_unattended.R [pkg-dir]
#         pkg-dir defaults to the current working directory.
#
# On success, devtools writes CRAN-SUBMISSION (version + date + SHA)
# into the package root.

args   <- commandArgs(trailingOnly = TRUE)
pkgdir <- if (length(args) >= 1) args[[1]] else "."
pkgdir <- normalizePath(pkgdir, mustWork = TRUE)

if (!file.exists(file.path(pkgdir, "DESCRIPTION"))) {
  stop("submit_cran_unattended.R: no DESCRIPTION in ", pkgdir)
}

assignInNamespace("yesno", function(...) FALSE, ns = "devtools")
devtools::submit_cran(pkg = pkgdir)

pkg <- desc::desc(file.path(pkgdir, "DESCRIPTION"))
maintainer_email <- pkg$get_maintainer()

message("")
message("============================================================")
message("CRAN intake accepted ", pkg$get("Package"), " ", pkg$get("Version"), ".")
message("")
message("Check the inbox for ", maintainer_email)
message("for an email from CRAN with subject like")
message("    'CRAN package <pkg> submission'")
message("containing a confirmation URL. You MUST click that link")
message("within 7 days or the submission will be discarded.")
message("============================================================")