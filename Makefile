DATABASE ?= ../ukmig/out/ukmig.duckdb
# The commit whose code and inputs produced DATABASE; update after a new build.
UKMIG_COMMIT ?= cf7786cfa30b1f97601375f624878895e8f986db
OUT ?= out/england-region-migration-$(shell date +%Y-%m-%d).zip
WORK := $(basename $(OUT)).work

.DELETE_ON_ERROR:
.PHONY: all data
all: $(OUT)
data: $(WORK)/data.csv

$(WORK)/migration.rds: src/migration.R $(DATABASE) Makefile renv.lock
	Rscript src/migration.R "$(DATABASE)" "$@"

$(WORK)/population.rds: src/population.R $(DATABASE) Makefile renv.lock
	Rscript src/population.R "$(DATABASE)" "$@"

$(WORK)/births.rds: src/births.R $(DATABASE) Makefile renv.lock
	Rscript src/births.R "$(DATABASE)" "$@"

$(WORK)/exposure.rds: src/exposure.R $(WORK)/population.rds $(WORK)/births.rds Makefile renv.lock
	Rscript src/exposure.R "$(WORK)/population.rds" "$(WORK)/births.rds" "$@"

$(WORK)/data.csv: src/data.R $(WORK)/migration.rds $(WORK)/exposure.rds Makefile renv.lock
	Rscript src/data.R "$(WORK)/migration.rds" "$(WORK)/exposure.rds" "$@"

$(WORK)/README.md: src/notes.R $(WORK)/data.csv data-notes.md Makefile renv.lock
	Rscript src/notes.R "$(WORK)/data.csv" data-notes.md "$(UKMIG_COMMIT)" "$@"

$(OUT): src/zip.R $(WORK)/data.csv $(WORK)/README.md Makefile renv.lock
	Rscript src/zip.R "$(WORK)/data.csv" "$(WORK)/README.md" "$@"
