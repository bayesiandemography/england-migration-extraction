
suppressPackageStartupMessages({
  library(duckdb)
  library(dplyr)
  library(bage)
  library(agetime)
  library(command)
})

cmd_assign(.mig = "out/mig.duckdb",
           .lookup = "out/region_lookup.rds",
           .out = "out/england_region_mig.csv")

lookup <- readRDS(.lookup)

drv <- duckdb()
con <- dbConnect(drv, dbdir = .mig)

data_mig <- dbGetQuery(con, "
  SELECT
    ro.region AS reg_orig,
    rd.region AS reg_dest,
    m.age,
    m.sex, 
    m.time,
    SUM(m.value) AS mig
   FROM mig AS m
   INNER JOIN region_lookup AS ro
   ON m.outla = ro.lad23cd
   INNER JOIN region_lookup AS rd
   ON m.inla = rd.lad23cd
   WHERE ro.region != rd.region
   GROUP BY all
   ORDER BY all"
  ) |>
  tibble()

data_popn <- dbGetQuery(con, "
  SELECT 
    r.region AS reg_orig,
    m.age,
    m.sex, 
    m.time,
    SUM(m.value) AS popn_orig
   FROM mye AS m
   INNER JOIN region_lookup AS r
   ON m.ladcode23 = r.lad23cd
   GROUP BY all
   ORDER BY all"
  ) |>
  tibble()

dbDisconnect(con)

out <- data_mig |>
  left_join(data_popn, by = c("reg_orig", "age", "sex", "time"))


write_csv(out, file = .out)
