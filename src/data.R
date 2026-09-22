command::use_renv()

suppressPackageStartupMessages({
  library(dplyr)
  library(agetime)
  library(command)
})

cmd_assign(.migration = "out/migration.csv",
                    .exposure = "out/exposure.csv", .out = "out/data.csv")

## Read -----------------------------------------------------------------------

migration <- readr::read_csv(.migration, col_types = "ccccid")
exposure <- readr::read_csv(.exposure, col_types = "cccid")
readr::stop_for_problems(migration)
readr::stop_for_problems(exposure)

## Assert inputs --------------------------------------------------------------

stopifnot(identical(names(migration), c("reg_orig", "reg_dest", "age", "sex", "time", "mig")),
          identical(names(exposure), c("region", "age", "sex", "time", "exposure")),
          !anyNA(migration), !anyNA(exposure),
          all(is.finite(exposure$exposure)), all(exposure$exposure >= 0))
regions <- sort(unique(migration$reg_orig))
years <- sort(unique(migration$time))
stopifnot(length(regions) == 9L, length(years) > 0L,
          identical(years, seq.int(min(years), max(years))),
          setequal(exposure$time, years), setequal(exposure$region, regions))
target_ages <- age_labels_one(lower_last = 90)
age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
           no_total = TRUE, no_na = TRUE, has_open_right = TRUE)
stopifnot(setequal(migration$age, target_ages), setequal(exposure$age, target_ages))

## Join -----------------------------------------------------------------------

# Origin exposure is one row per origin-age-sex-year; it repeats across destinations.
out <- migration |>
  left_join(exposure, by = c("reg_orig" = "region", "age", "sex", "time"),
            relationship = "many-to-one") |>
  rename(exposure_orig = exposure) |>
  arrange(time, reg_orig, reg_dest, sex, match(age, target_ages))

## Assert ---------------------------------------------------------------------

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

## Write ----------------------------------------------------------------------

dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(out, .out, na = "NA")
