# Read the NSFG cycles of 1973 to 1995, which CDC publishes as
# fixed-width .dat files with SAS setup files, with dtaparser's
# read_fixed_width and with asciiSetupReader (MIT, the oracle of ADR
# 0005), and compare row counts, names, every value, variable labels and
# value labels (plan 0009). Local only: the data are CDC's, not ours to
# commit.
#
#   NSFG_DIR=<dir holding "NSFG 1973/1973NSFGData.dat" ...> \
#   NSFG_SETUP_DIR=<dir holding CDC's 1973FemRespSetup.sas ...> \
#   Rscript scripts/check-nsfg.R
#
# The setup files are at
# https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NSFG/sas/.
#
# asciiSetupReader cannot read two layouts, so it is given equivalent
# input: the 1988 files have no line breaks (RECFM=F), so it reads a copy
# with one after every LRECL bytes; 1976 and 1982 hold two record types,
# so it reads a copy of the lines of the wanted type, through a copy of
# the setup whose selection (INPUT rec_type c @; IF ... THEN DELETE;
# ELSE INPUT) becomes a plain INPUT with rec_type first.
library(dtaparser)
library(asciiSetupReader)

data_dir <- Sys.getenv("NSFG_DIR")
setup_dir <- Sys.getenv("NSFG_SETUP_DIR")
if (!nzchar(data_dir) || !nzchar(setup_dir)) stop("set NSFG_DIR and NSFG_SETUP_DIR")

files <- list(
  list("1973FemRespSetup", "NSFG 1973/1973NSFGData.dat", 9797),
  list("1976FemRespSetup", "NSFG 1976/1976NSFGData.dat", 8611),
  list("1976PregSetup", "NSFG 1976/1976NSFGData.dat", 23042),
  list("1982FemRespSetup", "NSFG 1982/1982NSFGData.dat", 7969),
  list("1982PregSetup", "NSFG 1982/1982NSFGData.dat", 13768),
  list("1988FemRespSetup", "NSFG 1988/1988FemRespData.dat", 8450),
  list("1988PregSetup", "NSFG 1988/1988PregData.dat", 15759),
  list("1995FemPregFile", "NSFG 1995/1995PregData.dat", 21332),
  list("1995FemRespSetup", "NSFG 1995/1995FemRespData.dat", 10847)
)

alnum <- function(s) gsub("[^A-Za-z0-9]", "", s)

# The input asciiSetupReader can read: paths of a data file and a setup.
oracle_input <- function(setup, data) {
  # Two setups are not UTF-8; read them as dtaparser does.
  text <- readLines(setup, warn = FALSE)
  if (!all(validUTF8(text))) text <- iconv(text, "windows-1252", "UTF-8")
  joined <- paste(text, collapse = "\n")
  tmp <- tempfile()
  dir.create(tmp)
  lrecl <- regmatches(joined, regexpr("(?i)recfm=f\\s+lrecl=\\d+", joined, perl = TRUE))
  if (length(lrecl)) {
    n <- as.integer(sub("(?i).*lrecl=", "", lrecl, perl = TRUE))
    raw <- readBin(data, "raw", file.info(data)$size)
    starts <- seq(1, length(raw), by = n)
    lines <- vapply(starts, function(s) rawToChar(raw[s:(s + n - 1)]), "")
    data <- file.path(tmp, "data.dat")
    writeLines(lines, data)
  }
  sel <- regmatches(joined, regexec(
    "(?is)input\\s+(\\w+)\\s+(\\d+)(?:-(\\d+))?\\s*@;\\s*if\\s+\\w+\\s*([<>=]+)\\s*(\\d+)\\s+then\\s+delete;\\s*else\\s+input",
    joined, perl = TRUE))[[1]]
  if (length(sel) || !identical(text, readLines(setup, warn = FALSE))) {
    setup <- file.path(tmp, "setup.sas")
    writeLines(joined, setup)
  }
  if (length(sel)) {
    from <- as.integer(sel[3])
    to <- if (nzchar(sel[4])) as.integer(sel[4]) else from
    op <- sel[5]
    k <- as.numeric(sel[6])
    lines <- readLines(data, warn = FALSE)
    type <- suppressWarnings(as.numeric(substr(lines, from, to)))
    drop <- switch(op, "<" = type < k, ">" = type > k, "=" = type == k)
    # SAS: a missing type is below every number.
    drop[is.na(type)] <- op == "<"
    data <- file.path(tmp, "data.dat")
    writeLines(lines[!drop], data)
    joined <- sub(sel[1], paste0("INPUT ", sel[2], " ", sel[3], if (nzchar(sel[4])) paste0("-", sel[4]), "\n"),
                  joined, fixed = TRUE)
    setup <- file.path(tmp, "setup.sas")
    writeLines(joined, setup)
  }
  list(data = data, setup = setup)
}

compare <- function(name, dat, rows) {
  setup <- file.path(setup_dir, paste0(name, ".sas"))
  dat <- file.path(data_dir, dat)
  time <- system.time(ours <- suppressWarnings(read_fixed_width(dat, setup, factors = FALSE)))
  input <- oracle_input(setup, dat)
  theirs <- suppressWarnings(read_ascii_setup(input$data, input$setup, use_value_labels = FALSE,
                                              use_clean_names = FALSE))
  parsed <- parse_setup(input$setup)
  problems <- character()
  note <- function(...) problems <<- c(problems, paste0(...))
  if (nrow(ours) != rows) note("rows: ", nrow(ours), ", expected ", rows)
  if (nrow(theirs) != nrow(ours)) note("rows: asciiSetupReader ", nrow(theirs), ", ours ", nrow(ours))
  # asciiSetupReader names a column as LABEL spells it, where SAS (and we)
  # keep INPUT's spelling, and keeps each spec of a repeated name, as
  # NAME...k; the last one gives the values SAS keeps.
  base <- sub("\\.\\.\\.[0-9]+$", "", names(theirs))
  last <- !duplicated(toupper(base), fromLast = TRUE)
  repeated <- unique(toupper(base[duplicated(toupper(base))]))
  theirs <- stats::setNames(theirs[last], toupper(base[last]))
  key <- toupper(names(ours))
  only_ours <- names(ours)[!key %in% names(theirs)]
  only_theirs <- setdiff(names(theirs), key)
  if (length(only_ours)) note("only ours: ", paste(only_ours, collapse = " "))
  if (length(only_theirs)) note("only asciiSetupReader: ", paste(only_theirs, collapse = " "))
  if (length(repeated)) cat("     repeated in INPUT, compared with the last spec:", repeated, "\n")
  recoded <- parsed$missing
  info_row <- match(toupper(parsed$setup$column_number), toupper(parsed$setup$column_number))
  for (v in names(ours)[key %in% names(theirs)]) {
    x <- ours[[v]]
    y <- theirs[[toupper(v)]]
    if (is.character(x) || is.character(y)) {
      x <- ifelse(is.na(x), "", x)
      y <- ifelse(is.na(y), "", trimws(y))
      if (!identical(as.character(x), as.character(y))) note(v, ": strings differ in ", sum(x != y), " rows")
    } else {
      x <- as.double(unclass(x))
      y <- as.double(y)
      same <- (is.na(x) & is.na(y)) | (!is.na(x) & !is.na(y) & abs(x - y) <= 1e-9 * pmax(abs(y), 1))
      if (!all(same)) note(v, ": values differ in ", sum(!same), " rows")
    }
    i <- utils::tail(which(toupper(parsed$setup$column_number) == toupper(v)), 1)
    if (length(i)) {
      # It turns labels into names: punctuation to _, "+" to "plus", an X
      # before a leading digit, the variable's name added where two
      # labels are the same, and long ones cut.
      ours_label <- attr(ours[[v]], "label") %||% ""
      o <- ours_label
      for (r in list(c("+", "plus"), c("<", "under"), c(">", "over"), c("@", "at"), c("$", "dollar"))) {
        o <- gsub(r[1], r[2], o, fixed = TRUE)
      }
      o <- alnum(o)
      if (grepl("^[0-9]", o)) o <- paste0("X", o)
      t <- alnum(parsed$setup$column_name[i])
      ok <- tolower(t) %in% tolower(c(o, paste0(o, alnum(v)))) || (o == "" && t == alnum(v)) ||
        (nchar(t) >= 90 && startsWith(paste0(o, alnum(v)), t))
      if (!ok) note(v, ": label differs: ours \"", ours_label, "\" | theirs ", parsed$setup$column_name[i])
    }
    want <- parsed$value_labels[[match(toupper(v), toupper(names(parsed$value_labels)))]]
    got <- attr(ours[[v]], "labels")
    got <- if (is.null(got)) numeric() else stats::setNames(as.numeric(got), names(got))
    if (!is.null(want) || length(got)) {
      want <- want %||% character()
      codes <- as.numeric(want)
      gone <- if (is.null(recoded)) numeric() else as.numeric(recoded$values[toupper(recoded$variable) == toupper(v)])
      keep <- !codes %in% gone
      want <- stats::setNames(codes[keep], names(want)[keep])
      if (!identical(paste(sort(unname(got)), names(got)[order(got)]), paste(sort(unname(want)), names(want)[order(want)]))) {
        note(v, ": value labels differ: ours ", paste(utils::head(paste0(got, "=", names(got)), 4), collapse = "; "),
             " | theirs ", paste(utils::head(paste0(want, "=", names(want)), 4), collapse = "; "))
      }
    }
  }
  known_here <- known[[name]] %||% character()
  is_known <- vapply(problems, function(p) any(vapply(names(known_here), function(k) grepl(k, p), TRUE)), TRUE)
  for (k in names(known_here)) {
    if (any(vapply(problems, function(p) grepl(k, p), TRUE))) cat("     known:", known_here[[k]], "\n")
  }
  problems <- problems[!is_known]
  cat(sprintf("%-18s %6d rows %5d columns  %5.2f s  %s\n", name, nrow(ours), ncol(ours), time[["elapsed"]],
              if (length(problems)) paste(length(problems), "differences") else "same"))
  for (p in problems) cat("    ", substr(p, 1, 300), "\n")
  invisible(list(ours = ours, theirs = theirs, problems = problems))
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# Differences that are asciiSetupReader's limits, each checked against
# the setup text (plan 0009): pattern -> reason.
known <- list(
  "1973FemRespSetup" = c(
    "only ours: H_FINC_NLAMOUNT" = "H_FINC_NLAMOUNT is made by the setup's data-step code, which asciiSetupReader does not run (checked below)",
    "temp_NLAMOUNT: strings differ in 1 rows" = "the setup sets case 3882's temp_NLAMOUNT to '0000'; asciiSetupReader does not run that (checked below)",
    "^(FEC_STATUS|ETH_SPANISH1|EXP_NUMB2|EXP_DESIREDB|FAM_POVERTYCOL|FAM_INTFAMPL): value labels differ" = "VALUE fec_staf has no space after a label (24='(20) Subfecund'33=...); asciiSetupReader misreads it and the VALUE statements after it"
  ),
  "1982FemRespSetup" = c(
    "^(INTENT|DISFIRST): label differs" = "LABEL names INTENT and DISFIRST twice; SAS keeps the last, asciiSetupReader the first"
  ),
  "1995FemRespSetup" = c(
    "^(STRTL069|ENDLO069|MTHUS662): label differs" = "three LABEL entries have no = (STRTL069 'AG8 ...'); asciiSetupReader skips them"
  )
)
results <- lapply(files, function(f) compare(f[[1]], f[[2]], f[[3]]))

# 1973: asciiSetupReader does not run the setup's two data-step
# statements, so check them against the setup itself: case 3882's
# temp_NLAMOUNT is '0000', and H_FINC_NLAMOUNT is temp_NLAMOUNT as a
# number.
r73 <- results[[1]]$ours
fixed <- r73$temp_NLAMOUNT
fixed[r73$INT_ID == 3882] <- "0000"
stopifnot(identical(fixed, r73$temp_NLAMOUNT))
want <- suppressWarnings(as.numeric(substr(fixed, 1, 4)))
stopifnot(identical(is.na(want), is.na(r73$H_FINC_NLAMOUNT)),
          all(want[!is.na(want)] == r73$H_FINC_NLAMOUNT[!is.na(want)]))
cat("1973 data-step statements: as the setup says\n")
