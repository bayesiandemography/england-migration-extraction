## Contents and coverage

`data.csv` contains estimated migration between different English regions and
origin-region population counts. A row is an origin, destination, age group,
sex and migration year. All nine English regions and 72 directed region pairs
are included. Within-region flows and flows across England's boundary are
excluded. Supplied zeros are retained. Estimates are not rounded.

The year in `time` denotes the year ending 30 June. Thus `time = 2012` describes
the period from 30 June 2011 to 30 June 2012. Geography uses 2023 local authority
boundaries and the December 2023 England local-authority-to-region lookup.

## Columns

| Column | Type | Definition |
| --- | --- | --- |
| `reg_orig` | Text | Origin English region name |
| `reg_dest` | Text | Destination English region name |
| `age` | Text | Single-year age 0–89 or open-ended interval `90+` |
| `sex` | Text | `Female` or `Male` |
| `time` | Integer | Year ending 30 June |
| `mig` | Numeric | Estimated internal migration moves during that year |
| `popn_orig_start` | Numeric | Origin population in this age-sex group at 30 June of `time - 1` |
| `popn_orig_end` | Numeric | Origin population in this age-sex group at 30 June of `time` |
| `exposure_orig` | Numeric | Mean of start and end population: `(popn_orig_start + popn_orig_end) / 2` |

The unique key is `reg_orig`, `reg_dest`, `age`, `sex`, `time`. The CSV is UTF-8,
comma-delimited, with a header and no row-name column. There are no missing
values in a validated release; `NA` is reserved as the missing-value marker.
Read geography, age and sex as text, `time` as an integer, and measures as numeric.

## Ages, population and exposure

The extraction uses `agetime::age_standard()` and `agetime::age_assert()` for
the target labels, and `agetime::age_coarsen_to()` for both migration and
population ages. It then sums values within each target group. Individual
migration ages 90 and above, including the later `100+` interval, become `90+`.
Population is already represented as ages 0–89 and `90+` in `ukmig`.
Older migration files have some missing high-age columns; only supplied counts
are aggregated. Missing source ages are not imputed or claimed to be zeros.

Migration age is measured at 30 June at the end of the migration year. Population
age is measured at each population reference date. Start and end populations
use the same age group, without shifting ages to follow a cohort. The exposure
is an average population count, used as a one-year exposure approximation; it
is not an independently measured person-time total.

Both population endpoints are retained for every migration year. For migration
years 2012–2024 this includes populations from 30 June 2011 through 30 June 2024.
Population and exposure repeat for each destination of a given origin-age-sex-
year group. Deduplicate these columns across destinations before summing them;
otherwise origin population would be counted eight times. For a calendar year
shared by adjacent periods, the previous period's end population equals the
next period's start population.

## Sources and provenance

Publisher: Office for National Statistics (ONS).

- Migration: [Internal migration in England and Wales](https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/internalmigrationinenglandandwales), detailed local-authority estimates, using 2023 boundaries. The 2022 and 2023 source workbooks contain revisions published on 30 July 2025.
- Population: [Estimates of the population for England and Wales](https://www.ons.gov.uk/peoplepopulationandcommunity/populationandmigration/populationestimates/datasets/estimatesofthepopulationforenglandandwales), `myebtablesenglandwales20112024.xlsx`, sheet `MYEB1`.
- Region lookup: `Local_Authority_District_to_Region_(December_2023)_Lookup_in_England.csv`, attributed to the [ONS Open Geography Portal](https://geoportal.statistics.gov.uk/). The exact catalogue URL has not yet been confirmed.

Contains public sector information licensed under the Open Government Licence
v3.0, except where otherwise stated by the source publisher. The ONS dataset
pages state this licence; the lookup's exact edition-specific attribution has
not yet been confirmed. Collection links may now offer revised editions; the
recorded `ukmig` commit identifies the preserved inputs used by this release.

The header records the database build commit supplied by the producer and the
companion extraction commit. The database itself does not store build provenance;
the producer must supply the commit actually used, rather than infer it from the
current checkout. Package versions are recorded in each project's `renv.lock`.

## Using this archive

Unzip `data.csv` and read it into your analysis. Neither `ukmig` nor the extraction
project is needed to reproduce research from this supplied input. Preserve this
ZIP unchanged with the research project, using Git LFS if appropriate. Adopt a
new named ZIP explicitly when updating the research data.
