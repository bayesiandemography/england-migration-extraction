suppressPackageStartupMessages(library(dplyr))

command::cmd_assign(.migration = "out/migration.csv",
                    .population = "out/population.csv", .out = "out/data.csv")

migration <- readr::read_csv(.migration, col_types = "ccccid")
population <- readr::read_csv(.population, col_types = "cccid")
readr::stop_for_problems(migration)
readr::stop_for_problems(population)
stopifnot(identical(names(migration), c("reg_orig", "reg_dest", "age", "sex", "time", "mig")),
          identical(names(population), c("reg_orig", "age", "sex", "time", "popn")),
          !anyNA(migration), !anyNA(population),
          all(is.finite(population$popn)), all(population$popn >= 0))
regions <- sort(unique(migration$reg_orig))
years <- sort(unique(migration$time))
stopifnot(length(regions) == 9L, length(years) > 0L,
          identical(years, seq.int(min(years), max(years))),
          setequal(population$time, seq.int(min(years) - 1L, max(years))))
target_ages <- as.character(agetime::age_standard(c(as.character(0:89), "90+")))
agetime::age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
                    no_total = TRUE, no_na = TRUE, has_open_right = TRUE)

# Join the same age group at each endpoint, without shifting ages by cohort.
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

dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(out, .out, na = "NA")
