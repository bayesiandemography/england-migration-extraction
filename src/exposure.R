command::use_renv()

suppressPackageStartupMessages({
  library(dplyr)
  library(agetime)
  library(command)
})

cmd_assign(.population = "out/population.csv",
                    .births = "out/births.csv", .out = "out/exposure.csv")

## Read -----------------------------------------------------------------------

population <- readr::read_csv(.population, col_types = "cccid")
births <- readr::read_csv(.births, col_types = "ccid")
readr::stop_for_problems(population)
readr::stop_for_problems(births)

## Assert inputs --------------------------------------------------------------

stopifnot(identical(names(population), c("region", "age", "sex", "time", "popn")),
          identical(names(births), c("region", "sex", "time", "births")),
          !anyNA(population), !anyNA(births),
          all(is.finite(population$popn)), all(population$popn >= 0),
          all(is.finite(births$births)), all(births$births >= 0))

regions <- sort(unique(population$region))
pop_times <- sort(unique(population$time))
years <- sort(unique(births$time))
stopifnot(length(regions) == 9L, length(years) > 0L,
          identical(years, seq.int(min(years), max(years))),
          identical(pop_times, seq.int(min(years) - 1L, max(years))),
          setequal(births$region, regions),
          setequal(births$sex, c("Female", "Male")),
          setequal(population$sex, c("Female", "Male")))
target_ages <- age_labels_one(lower_last = 90)
age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
           no_total = TRUE, no_na = TRUE, has_open_right = TRUE)
stopifnot(setequal(population$age, target_ages))

## Calculate ------------------------------------------------------------------

# Origin-only person-years for the cohort that is age a on 30 June of year t.
closed_ages <- as.character(1:89)
popn_end <- population |>
  filter(time %in% years) |>
  rename(popn_end = popn)

age0 <- popn_end |>
  filter(age == "0") |>
  left_join(births, by = c("region", "sex", "time"),
            relationship = "one-to-one") |>
  transmute(region, age, sex, time,
            exposure = 0.25 * (births + popn_end))

ages_1_89 <- popn_end |>
  filter(age %in% closed_ages) |>
  left_join(
    population |>
      filter(age %in% as.character(0:88)) |>
      transmute(region, age = as.character(as.integer(age) + 1L), sex,
                time = time + 1L, popn_start = popn),
    by = c("region", "age", "sex", "time"),
    relationship = "one-to-one"
  ) |>
  transmute(region, age, sex, time,
            exposure = 0.5 * (popn_start + popn_end))

age90 <- popn_end |>
  filter(age == "90+") |>
  left_join(
    population |>
      filter(age == "89") |>
      transmute(region, sex, time = time + 1L, popn_89_start = popn),
    by = c("region", "sex", "time"),
    relationship = "one-to-one"
  ) |>
  left_join(
    population |>
      filter(age == "90+") |>
      transmute(region, sex, time = time + 1L, popn_90_start = popn),
    by = c("region", "sex", "time"),
    relationship = "one-to-one"
  ) |>
  transmute(region, age, sex, time,
            exposure = 0.5 * (popn_89_start + popn_90_start + popn_end))

exposure <- bind_rows(age0, ages_1_89, age90) |>
  arrange(time, region, sex, match(age, target_ages))

## Assert ---------------------------------------------------------------------

keys <- c("region", "age", "sex", "time")
stopifnot(nrow(exposure) == length(regions) * length(target_ages) * 2L * length(years),
          identical(names(exposure), c("region", "age", "sex", "time", "exposure")),
          !anyNA(exposure), !anyDuplicated(exposure[keys]),
          setequal(exposure$region, regions), setequal(exposure$age, target_ages),
          setequal(exposure$sex, c("Female", "Male")), setequal(exposure$time, years),
          all(is.finite(exposure$exposure)), all(exposure$exposure >= 0))

## Write ----------------------------------------------------------------------

dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(exposure, .out)
