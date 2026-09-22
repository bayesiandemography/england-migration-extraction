suppressPackageStartupMessages({
  library(dplyr)
  library(command)
})

cmd_assign(.database = "../ukmig/out/ukmig.duckdb",
                    .out = "out/births.csv")

## Extract --------------------------------------------------------------------

# Births by mother's usual residence, years ending 30 June, England regions.
# Wales local authorities drop with the England region lookup.
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = .database, read_only = TRUE,
                      config = list(memory_limit = "2GB", threads = "2"))
tryCatch({
  regions <- DBI::dbGetQuery(con, "SELECT DISTINCT region FROM region_lookup ORDER BY region")$region
  years <- DBI::dbGetQuery(con, "SELECT DISTINCT time FROM mig ORDER BY time")$time
  stopifnot(length(regions) == 9L, !anyNA(regions), length(years) > 0L,
            identical(years, seq.int(min(years), max(years))))
  births <- DBI::dbGetQuery(con, "SELECT r.region, b.sex, b.time,
    SUM(b.value) AS births
    FROM births AS b INNER JOIN region_lookup AS r ON b.ladcode23 = r.lad23cd
    WHERE b.time BETWEEN ? AND ?
    GROUP BY r.region, b.sex, b.time",
    params = list(min(years), max(years)))

}, finally = DBI::dbDisconnect(con, shutdown = TRUE))

## Assert ---------------------------------------------------------------------

stopifnot(identical(names(births), c("region", "sex", "time", "births")),
          setequal(births$region, regions),
          setequal(births$sex, c("Female", "Male")),
          setequal(births$time, years),
          nrow(births) == length(regions) * 2L * length(years),
          !anyNA(births), !anyDuplicated(births[c("region", "sex", "time")]),
          all(is.finite(births$births)), all(births$births >= 0))

## Write ----------------------------------------------------------------------

births <- births |> arrange(time, region, sex)
dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(births, .out)
