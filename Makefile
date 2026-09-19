DATABASE ?= ../ukmig/out/ukmig.duckdb
# The commit whose code and inputs produced DATABASE; update after a new build.
UKMIG_COMMIT ?= cf7786cfa30b1f97601375f624878895e8f986db
OUT ?= out/england-region-migration-$(shell date +%Y-%m-%d).zip

.PHONY: all
all: $(OUT)

$(OUT): src/extract.R data-notes.md Makefile renv.lock $(DATABASE)
	Rscript src/extract.R "$(DATABASE)" data-notes.md "$(UKMIG_COMMIT)" "$@"
