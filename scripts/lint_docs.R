#!/usr/bin/env Rscript
# lint_docs.R — Static lint for CRAN documentation policy violations
# that devtools::check() does not catch automatically.
#
# Checks:
#   1. \dontrun{} in R/ source files (CRAN wants \donttest{} or unwrapped)
#   2. Single-quoted all-caps acronyms in DESCRIPTION Description field
#      (single quotes are only for package/software names, not acronyms)
#   3. Malformed reference links in DESCRIPTION (space after '<' or after
#      'doi:'/'https:' inside angle brackets)
#
# Usage: Rscript lint_docs.R [--pkg-dir <dir>]
# Exit:  0 = clean, 1 = issues found, 2 = usage/setup error

suppressPackageStartupMessages(library(argparser))

p <- arg_parser("Lint CRAN documentation policy violations")
p <- add_argument(p, "--pkg-dir", help = "Package root directory", default = ".")
args <- parse_args(p)

pkg_dir <- tryCatch(
  normalizePath(args$pkg_dir, mustWork = TRUE),
  error = function(e) {
    message("lint_docs: directory not found: ", args$pkg_dir)
    quit(status = 2)
  }
)

desc_file <- file.path(pkg_dir, "DESCRIPTION")
if (!file.exists(desc_file)) {
  message("lint_docs: no DESCRIPTION in ", pkg_dir)
  quit(status = 2)
}

issues <- character(0)

# --- Check 1: \dontrun{} in R/ source files ----------------------------------
r_dir <- file.path(pkg_dir, "R")
if (dir.exists(r_dir)) {
  r_files <- list.files(r_dir, pattern = "\\.R$", full.names = TRUE, recursive = TRUE)
  for (f in r_files) {
    lines <- readLines(f, warn = FALSE)
    hits <- grep("\\\\dontrun", lines)
    for (h in hits) {
      issues <- c(issues, sprintf(
        "%s:%d  \\dontrun{} found — replace with \\donttest{} or unwrap if example runs in < 5 sec",
        f, h
      ))
    }
  }
}

# --- Check 2: Single-quoted all-caps acronyms in DESCRIPTION -----------------
desc <- read.dcf(desc_file)
if ("Description" %in% colnames(desc)) {
  desc_text <- desc[1L, "Description"]
  m <- gregexpr("'[A-Z]{2,}'", desc_text, perl = TRUE)
  matched <- regmatches(desc_text, m)[[1L]]
  if (length(matched) > 0L) {
    issues <- c(issues, sprintf(
      "DESCRIPTION Description: single-quoted acronym(s) found — CRAN wants single quotes only around package/software names, not acronyms: %s",
      paste(matched, collapse = ", ")
    ))
  }
}

# --- Check 3: Malformed reference links in DESCRIPTION -----------------------
if ("Description" %in% colnames(desc)) {
  desc_text <- desc[1L, "Description"]
  if (grepl("< +(doi|https?):", desc_text, perl = TRUE)) {
    issues <- c(issues,
      "DESCRIPTION Description: space after '<' in reference link — use <doi:10.x/y>, not < doi:10.x/y>"
    )
  }
  if (grepl("<(doi|https?): ", desc_text, perl = TRUE)) {
    issues <- c(issues,
      "DESCRIPTION Description: space after colon in reference link — use <doi:10.x/y>, not <doi: 10.x/y>"
    )
  }
}

# --- Report ------------------------------------------------------------------
n <- length(issues)
if (n > 0L) {
  message("lint_docs: ", n, " CRAN policy issue(s) found:")
  for (issue in issues) message("  - ", issue)
  quit(status = 1L)
} else {
  message("lint_docs: OK")
}
