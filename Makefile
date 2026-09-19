DATABASE ?= ../ukmig/out/ukmig.duckdb
# The commit whose code and inputs produced DATABASE; update after a new build.
UKMIG_COMMIT ?= cf7786cfa30b1f97601375f624878895e8f986db
OUT ?= out/england-region-migration-$(shell date +%Y-%m-%d).zip
WORK := $(basename $(OUT)).work

.DELETE_ON_ERROR:
.PHONY: all data
all: $(OUT)
data: $(WORK)/data.csv

$(WORK)/migration.csv: src/extract_migration.R $(DATABASE) Makefile renv.lock
	Rscript src/extract_migration.R "$(DATABASE)" "$@"

$(WORK)/population.csv: src/extract_population.R $(DATABASE) Makefile renv.lock
	Rscript src/extract_population.R "$(DATABASE)" "$@"

$(WORK)/data.csv: src/assemble_data.R $(WORK)/migration.csv $(WORK)/population.csv Makefile renv.lock
	Rscript src/assemble_data.R "$(WORK)/migration.csv" "$(WORK)/population.csv" "$@"

$(WORK)/README.md: src/write_notes.R $(WORK)/data.csv data-notes.md Makefile renv.lock
	Rscript src/write_notes.R "$(WORK)/data.csv" data-notes.md "$(UKMIG_COMMIT)" "$@"

$(OUT): src/package_zip.R $(WORK)/data.csv $(WORK)/README.md Makefile renv.lock
	Rscript src/package_zip.R "$(WORK)/data.csv" "$(WORK)/README.md" "$@"
