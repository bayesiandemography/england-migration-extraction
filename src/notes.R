command::use_renv()

suppressPackageStartupMessages(library(command))

cmd_assign(.data = "out/data.csv", .notes = "data-notes.md",
                    .ukmig_commit = "", .out = "out/README.md")

## Assert ---------------------------------------------------------------------

if (!grepl("^[0-9a-f]{40}$", .ukmig_commit)) {
  stop("Supply the full ukmig commit used to build this database.")
}
# A release records committed code and notes, rather than silently attributing
# uncommitted changes to an old commit.
extract_commit <- system2("git", c("rev-parse", "--verify", "HEAD"), stdout = TRUE)
if (!is.null(attr(extract_commit, "status")) || length(extract_commit) != 1L ||
    !grepl("^[0-9a-f]{40}$", extract_commit)) stop("Commit the extraction project first")
changes <- system2("git", c("status", "--porcelain", "--untracked-files=normal"),
                   stdout = TRUE)
if (!is.null(attr(changes, "status")) || length(changes)) {
  stop("Commit extraction code, settings and notes before creating a release")
}

out <- readr::read_csv(.data, col_types = "ccccidd")
readr::stop_for_problems(out)
stopifnot(nrow(out) > 0L, !anyNA(out))

## Write ----------------------------------------------------------------------

years <- sort(unique(out$time))
notes <- c("# England inter-region migration and origin exposure", "",
  paste0("Created: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste0("ukmig build commit (supplied by producer): `", .ukmig_commit, "`"),
  paste0("Extraction commit: `", extract_commit, "`"),
  paste0("R version: ", getRversion()),
  paste0("Migration years ending June: ", min(years), "–", max(years)),
  paste0("Data rows: ", nrow(out)), "", readLines(.notes, warn = FALSE))
dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
writeLines(enc2utf8(notes), .out, useBytes = TRUE)

