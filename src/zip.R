command::use_renv()

suppressPackageStartupMessages(library(command))

cmd_assign(.data = "out/data.csv", .notes = "out/README.md",
                    .out = paste0("out/england-region-migration-", Sys.Date(), ".zip"))

## Assert ---------------------------------------------------------------------

if (file.exists(.out)) stop("ZIP already exists; choose a new filename: ", .out)
if (tolower(tools::file_ext(.out)) != "zip") stop("Output must have a .zip extension")
stopifnot(file.exists(.data), file.exists(.notes))

## Package --------------------------------------------------------------------

dir.create(dirname(.out), recursive = TRUE, showWarnings = FALSE)
staging <- tempfile(".zip-", tmpdir = dirname(.out))
dir.create(staging)
tryCatch({
  stopifnot(file.copy(.data, file.path(staging, "data.csv")),
            file.copy(.notes, file.path(staging, "README.md")))
  archive <- file.path(normalizePath(staging), "extract.zip")
  old_wd <- getwd()
  tryCatch({
    setwd(staging)
    status <- utils::zip(archive, c("data.csv", "README.md"), flags = "-q")
    if (status != 0L) stop("ZIP creation failed")
  }, finally = setwd(old_wd))
  ## Assert -------------------------------------------------------------------

  contents <- utils::unzip(archive, list = TRUE)
  stopifnot(setequal(contents$Name, c("data.csv", "README.md")), nrow(contents) == 2L)
  check_dir <- file.path(staging, "check")
  utils::unzip(archive, exdir = check_dir)
  # Byte-for-byte check of packaging, not of the data processing.
  stopifnot(identical(unname(tools::md5sum(c(.data, .notes))),
                     unname(tools::md5sum(file.path(check_dir, c("data.csv", "README.md"))))))
  if (file.exists(.out)) stop("ZIP already exists; choose a new filename: ", .out)
  if (!file.rename(archive, .out)) stop("Could not publish ZIP: ", .out)
  message("Created ", .out)
}, finally = unlink(staging, recursive = TRUE))
