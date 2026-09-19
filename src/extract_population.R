suppressPackageStartupMessages(library(dplyr))

command::cmd_assign(.database = "../ukmig/out/ukmig.duckdb",
                    .out = "out/population.csv")

# Read every mid-year population endpoint needed by the migration series.
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = .database, read_only = TRUE,
                      config = list(memory_limit = "2GB", threads = "2"))
tryCatch({
  regions <- DBI::dbGetQuery(con, "SELECT DISTINCT region FROM region_lookup ORDER BY region")$region
  years <- DBI::dbGetQuery(con, "SELECT DISTINCT time FROM mig ORDER BY time")$time
  stopifnot(length(regions) == 9L, !anyNA(regions), length(years) > 0L,
            identical(years, seq.int(min(years), max(years))))
  population <- DBI::dbGetQuery(con, "SELECT r.region AS reg_orig,
    m.age, m.sex, m.time, SUM(m.value) AS popn
    FROM mye AS m INNER JOIN region_lookup AS r ON m.ladcode23 = r.lad23cd
    WHERE m.time BETWEEN ? AND ?
    GROUP BY r.region, m.age, m.sex, m.time",
    params = list(min(years) - 1L, max(years)))

}, finally = DBI::dbDisconnect(con, shutdown = TRUE))

target_ages <- as.character(agetime::age_standard(c(as.character(0:89), "90+")))
agetime::age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
                    no_total = TRUE, no_na = TRUE, has_open_right = TRUE)

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

stopifnot(!anyDuplicated(population[c("reg_orig", "age", "sex", "time")]),
          setequal(population$reg_orig, regions))
population <- population |> arrange(time, reg_orig, sex, match(age, target_ages))
dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(population, .out)
