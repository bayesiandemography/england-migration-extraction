suppressPackageStartupMessages(library(dplyr))

command::cmd_assign(.database = "../ukmig/out/ukmig.duckdb",
                    .out = "out/migration.csv")

# Read inter-region moves only, aggregating local authorities in the database.
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = .database, read_only = TRUE,
                      config = list(memory_limit = "2GB", threads = "2"))
tryCatch({
  regions <- DBI::dbGetQuery(con, "SELECT DISTINCT region FROM region_lookup ORDER BY region")$region
  years <- DBI::dbGetQuery(con, "SELECT DISTINCT time FROM mig ORDER BY time")$time
  stopifnot(length(regions) == 9L, !anyNA(regions), length(years) > 0L,
            identical(years, seq.int(min(years), max(years))))
  migration <- DBI::dbGetQuery(con, "SELECT ro.region AS reg_orig,
    rd.region AS reg_dest, m.age, m.sex, m.time, SUM(m.value) AS mig
    FROM mig AS m
    INNER JOIN region_lookup AS ro ON m.outla = ro.lad23cd
    INNER JOIN region_lookup AS rd ON m.inla = rd.lad23cd
    WHERE ro.region <> rd.region
    GROUP BY ro.region, rd.region, m.age, m.sex, m.time")

}, finally = DBI::dbDisconnect(con, shutdown = TRUE))

target_ages <- as.character(agetime::age_standard(c(as.character(0:89), "90+")))
agetime::age_assert(target_ages, no_overlap = TRUE, no_gap = TRUE,
                    no_total = TRUE, no_na = TRUE, has_open_right = TRUE)

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

keys <- c("reg_orig", "reg_dest", "age", "sex", "time")
stopifnot(!anyNA(migration), !anyDuplicated(migration[keys]),
          setequal(migration$reg_orig, regions), setequal(migration$reg_dest, regions),
          all(migration$reg_orig != migration$reg_dest),
          setequal(migration$age, target_ages), setequal(migration$time, years),
          setequal(migration$sex, c("Female", "Male")),
          nrow(migration) == length(regions) * (length(regions) - 1L) *
            length(target_ages) * 2L * length(years),
          all(is.finite(migration$mig)), all(migration$mig >= 0))
migration <- migration |> arrange(time, reg_orig, reg_dest, sex, match(age, target_ages))
dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(migration, .out)
