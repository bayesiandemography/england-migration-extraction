# England migration extraction

This companion project reads the `ukmig` database and produces a named ZIP
containing `data.csv` and `README.md`. The core research project uses that ZIP
and has no dependency on `ukmig` or this extraction repository.

The extract covers moves between distinct English regions, single-year ages
0–89 and `90+`, both sexes, and every migration year in the database. It retains
origin population at both period endpoints and their average as exposure.
See [data-notes.md](data-notes.md) for column definitions, age interpretation,
source attribution and the repeated-population convention.

## Build

Use R 4.6.1 and restore the recorded dependencies from this project directory:

```r
renv::restore()
```

The project has its own `renv.lock`. `command` comes from CRAN; `agetime` is
pinned to a GitHub revision. No sibling package checkout is required. The `zip`
command must also be available. R sessions started here activate `renv` through
`.Rprofile`.

Commit the extraction code and notes before producing a release, then run:

```sh
make
```

The default database is `../ukmig/out/ukmig.duckdb`. The default output is
`out/england-region-migration-YYYY-MM-DD.zip`, using the local date. `Makefile`
records the known database build commit. To use another database build or make
another release on the same day, supply the corresponding values explicitly:

```sh
make DATABASE=/path/to/ukmig.duckdb UKMIG_COMMIT=<full-build-commit> OUT=out/england-region-migration-YYYY-MM-DD-2.zip
```

Replace the example placeholders before running that command. The producer is
responsible for supplying the actual database build commit. Changing the central
checkout alone does not change the provenance of an existing database. This
project opens the database read-only and does not build or modify it.

The script refuses to overwrite an existing ZIP. If code or inputs change,
choose a new output name; never replace a released archive. Output ZIPs are
ignored here and preserved with Git LFS in the receiving research repository.
There is deliberately no target that deletes released ZIPs.

## Implementation and checks

`src/extract.R` is standalone and declares the database, data notes, build commit
and output through `command::cmd_assign()`. It aggregates local authorities to
regions in SQL, uses `agetime` to harmonize age groups, aligns the population
endpoints, and writes one ZIP through temporary staging files.

Validation checks the complete region-pair/age/sex/year grid, unique keys,
nonnegative finite values, complete population endpoints, and conservation of
migration and population totals during age coarsening. It reopens the ZIP and
compares the packaged CSV with the validated table before publishing it.
`dbplyr` is excluded from inferred dependencies: database queries use DBI, with
dplyr operating only on in-memory tables.

## Delivery

Copy the named ZIP to the research project's input folder and commit it there
with Git LFS alongside the explicit analysis input selection. Other researchers
need the actual ZIP, not just its LFS pointer. No automatic publishing or copying
to another repository is performed by this project.
