suppressPackageStartupMessages({
  library(DBI)
  library(duckdb)
  library(dplyr)
})

command::cmd_assign(
  .database = "../ukmig/out/ukmig.duckdb",
  .notes = "data-notes.md",
  .ukmig_commit = "",
  .out = paste0("out/england-region-migration-", Sys.Date(), ".zip")
)

if (!file.exists(.database)) stop("Database does not exist: ", .database)
if (!file.exists(.notes)) stop("Data notes do not exist: ", .notes)
if (!grepl("^[0-9a-f]{40}$", .ukmig_commit)) {
  stop("Supply the full ukmig commit used to build this database.")
}
if (file.exists(.out)) stop("ZIP already exists; choose a new filename: ", .out)
if (tolower(tools::file_ext(.out)) != "zip") stop("Output must have a .zip extension")

# Run from the companion repository root. A release records committed code and
# notes, rather than silently attributing uncommitted changes to an old commit.
extract_commit <- system2("git", c("rev-parse", "--verify", "HEAD"), stdout = TRUE)
if (!is.null(attr(extract_commit, "status")) || length(extract_commit) != 1L ||
    !grepl("^[0-9a-f]{40}$", extract_commit)) stop("Commit the extraction project first")
changes <- system2("git", c("status", "--porcelain", "--untracked-files=normal"),
                   stdout = TRUE)
if (!is.null(attr(changes, "status")) || length(changes)) {
  stop("Commit extraction code, settings and notes before creating a release")
}

# Age interpretation and coarsening belong to agetime. In particular, source
# 100+ and the older workbooks' individual ages above 90 all map into 90+.
target_ages <- as.character(agetime::age_standard(c(as.character(0:89), "90+")))
agetime::age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
                    no_total = TRUE, no_na = TRUE, has_open_right = TRUE)
con <- NULL
staging <- NULL
tryCatch({
  con <- dbConnect(duckdb(), dbdir = .database, read_only = TRUE,
                   config = list(memory_limit = "2GB", threads = "2"))
  stopifnot(all(c("mig", "mye", "region_lookup") %in% dbListTables(con)))
  regions <- dbGetQuery(con, "SELECT DISTINCT region FROM region_lookup ORDER BY region")$region
  years <- dbGetQuery(con, "SELECT DISTINCT time FROM mig ORDER BY time")$time
  stopifnot(length(regions) == 9L, !anyNA(regions), length(years) > 0L,
            identical(years, seq.int(min(years), max(years))))

  # Aggregate geography in SQL before bringing the smaller regional table into R.
  # Both ends must be English and in different regions. No within-region moves
  # or cross-border moves are included; supplied zero counts are retained.
  migration <- dbGetQuery(con, "SELECT ro.region AS reg_orig,
    rd.region AS reg_dest, m.age, m.sex, m.time, SUM(m.value) AS mig
    FROM mig AS m
    INNER JOIN region_lookup AS ro ON m.outla = ro.lad23cd
    INNER JOIN region_lookup AS rd ON m.inla = rd.lad23cd
    WHERE ro.region <> rd.region
    GROUP BY ro.region, rd.region, m.age, m.sex, m.time")
  migration_totals <- migration |>
    group_by(time, sex) |> summarise(value = sum(mig), .groups = "drop") |>
    arrange(time, sex)
  migration <- migration |>
    mutate(age = as.character(agetime::age_coarsen_to(age, to = target_ages))) |>
    group_by(reg_orig, reg_dest, age, sex, time) |>
    summarise(mig = sum(mig), .groups = "drop")
  coarsened_totals <- migration |>
    group_by(time, sex) |> summarise(value = sum(mig), .groups = "drop") |>
    arrange(time, sex)
  stopifnot(isTRUE(all.equal(migration_totals, coarsened_totals, tolerance = 1e-10)))

  # Include both endpoints for every migration year, including the preceding
  # June for the first year. Join the same age group at each endpoint, not a
  # cohort shifted by one year of age.
  population <- dbGetQuery(con, "SELECT r.region AS reg_orig,
    m.age, m.sex, m.time, SUM(m.value) AS popn
    FROM mye AS m INNER JOIN region_lookup AS r ON m.ladcode23 = r.lad23cd
    WHERE m.time BETWEEN ? AND ?
    GROUP BY r.region, m.age, m.sex, m.time",
    params = list(min(years) - 1L, max(years)))
  population_totals <- population |>
    group_by(time, sex) |> summarise(value = sum(popn), .groups = "drop") |>
    arrange(time, sex)
  population <- population |>
    mutate(age = as.character(agetime::age_coarsen_to(age, to = target_ages))) |>
    group_by(reg_orig, age, sex, time) |>
    summarise(popn = sum(popn), .groups = "drop")
  coarsened_population <- population |>
    group_by(time, sex) |> summarise(value = sum(popn), .groups = "drop") |>
    arrange(time, sex)
  stopifnot(isTRUE(all.equal(population_totals, coarsened_population, tolerance = 1e-10)),
            setequal(population$time, seq.int(min(years) - 1L, max(years))),
            setequal(population$age, target_ages),
            setequal(population$sex, c("Female", "Male")),
            nrow(population) == length(regions) * length(target_ages) * 2L * (length(years) + 1L),
            !anyNA(population), all(is.finite(population$popn)), all(population$popn >= 0))
  start_population <- population |>
    transmute(reg_orig, age, sex, time = time + 1L, popn_orig_start = popn)
  end_population <- population |>
    rename(popn_orig_end = popn)
  out <- migration |>
    left_join(start_population, by = c("reg_orig", "age", "sex", "time"),
              relationship = "many-to-one") |>
    left_join(end_population, by = c("reg_orig", "age", "sex", "time"),
              relationship = "many-to-one") |>
    mutate(exposure_orig = (popn_orig_start + popn_orig_end) / 2) |>
    arrange(time, reg_orig, reg_dest, sex, match(age, target_ages))

  keys <- c("reg_orig", "reg_dest", "age", "sex", "time")
  expected_rows <- length(regions) * (length(regions) - 1L) * length(target_ages) * 2L * length(years)
  stopifnot(nrow(out) == expected_rows, !anyNA(out), !anyDuplicated(out[keys]),
            all(out$reg_orig != out$reg_dest),
            setequal(out$reg_orig, regions), setequal(out$reg_dest, regions),
            setequal(out$time, years), setequal(out$age, target_ages),
            setequal(out$sex, c("Female", "Male")),
            all(is.finite(out$mig)), all(out$mig >= 0),
            all(is.finite(out$exposure_orig)), all(out$exposure_orig >= 0),
            isTRUE(all.equal(sum(out$mig), sum(migration$mig), tolerance = 1e-10)))
  dbDisconnect(con, shutdown = TRUE)
  con <- NULL

  dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
  staging <- tempfile(".extract-", tmpdir = dirname(.out))
  dir.create(staging)
  readr::write_csv(out, file.path(staging, "data.csv"), na = "NA")
  notes <- c("# England inter-region migration and origin population", "",
    paste0("Created: ", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste0("ukmig build commit (supplied by producer): `", .ukmig_commit, "`"),
    paste0("Extraction commit: `", extract_commit, "`"),
    paste0("R version: ", getRversion()),
    paste0("Migration years ending June: ", min(years), "–", max(years)),
    paste0("Population at 30 June: ", min(years) - 1L, "–", max(years)),
    paste0("Data rows: ", nrow(out)), "", readLines(.notes, warn = FALSE))
  writeLines(enc2utf8(notes), file.path(staging, "README.md"), useBytes = TRUE)

  # Stage, reopen and check the actual packaged CSV before publishing the ZIP.
  archive <- file.path(normalizePath(staging), "extract.zip")
  old_wd <- getwd()
  tryCatch({
    setwd(staging)
    status <- utils::zip(archive, c("data.csv", "README.md"), flags = "-q")
    if (status != 0L) stop("ZIP creation failed")
  }, finally = setwd(old_wd))
  contents <- utils::unzip(archive, list = TRUE)
  stopifnot(setequal(contents$Name, c("data.csv", "README.md")), nrow(contents) == 2L)
  check_dir <- file.path(staging, "check")
  utils::unzip(archive, exdir = check_dir)
  checked <- readr::read_csv(file.path(check_dir, "data.csv"),
    col_types = "ccccidddd", show_col_types = FALSE)
  readr::stop_for_problems(checked)
  stopifnot(isTRUE(all.equal(as.data.frame(out), as.data.frame(checked), tolerance = 1e-12)),
            identical(readLines(file.path(check_dir, "README.md"), warn = FALSE), enc2utf8(notes)))
  if (file.exists(.out)) stop("ZIP already exists; choose a new filename: ", .out)
  if (!file.rename(archive, .out)) stop("Could not publish ZIP: ", .out)
  message("Created ", .out, " (", nrow(out), " rows)")
}, finally = {
  if (!is.null(con) && dbIsValid(con)) dbDisconnect(con, shutdown = TRUE)
  if (!is.null(staging)) unlink(staging, recursive = TRUE)
})
