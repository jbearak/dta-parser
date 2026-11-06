# Read the NSFG female respondent and pregnancy files of 1973 to
# 2017-2019, which CDC publishes as fixed-width .dat files with SAS setup
# files, with datakit's read_fixed_width and with asciiSetupReader (MIT,
# the oracle of ADR 0005), and compare row counts, names, every value,
# variable labels and value labels (plan 0009). Local only: the data are
# CDC's, not ours to commit.
#
#   NSFG_DIR=<dir holding "NSFG 1973/1973NSFGData.dat" ...> \
#   NSFG_SETUP_DIR=<dir holding CDC's 1973FemRespSetup.sas ...> \
#   Rscript scripts/check-nsfg.R
#
# The setup files are at
# https://ftp.cdc.gov/pub/Health_Statistics/NCHS/Datasets/NSFG/sas/ and
# the data files one directory up; put each data file in the folder that
# `files` below names, such as "NSFG 2017-2019".
#
# asciiSetupReader cannot read two layouts, so it is given equivalent
# input: the 1988 files have no line breaks (RECFM=F), so it reads a copy
# with one after every LRECL bytes; 1976 and 1982 hold two record types,
# so it reads a copy of the lines of the wanted type, through a copy of
# the setup whose selection (INPUT rec_type c @; IF ... THEN DELETE;
# ELSE INPUT) becomes a plain INPUT with rec_type first. It takes one
# setup file, so it reads 2002's three (Input, VarLabel, ValueLabel)
# joined into one. It reads the setups of 2006-2010 on as published: it
# finds the PROC FORMAT step and FORMAT statement CDC wraps in /* */, as
# read_fixed_width does with commented_formats on. It ends a
# double-quoted label at a quote inside it, as SAS does, where we read to
# the last quote (ADR 0030), so such labels are compared up to there.
library(datakit)
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
  list("1995FemRespSetup", "NSFG 1995/1995FemRespData.dat", 10847),
  list("2002FemPreg", "NSFG 2002/2002FemPreg.dat", 13593, paste0("2002FemPreg", c("Input", "VarLabel", "ValueLabel"))),
  list("2002FemResp", "NSFG 2002/2002FemResp.dat", 7643, paste0("2002FemResp", c("Input", "VarLabel", "ValueLabel"))),
  list("2006_2010_FemPregSetup", "NSFG 2006-2010/2006_2010_FemPreg.dat", 20492),
  list("2006_2010_FemRespSetup", "NSFG 2006-2010/2006_2010_FemResp.dat", 12279),
  list("2011_2013_FemPregSetup", "NSFG 2011-2013/2011_2013_FemPregData.dat", 9543),
  list("2011_2013_FemRespSetup", "NSFG 2011-2013/2011_2013_FemRespData.dat", 5601),
  list("2013_2015_FemPregSetup", "NSFG 2013-2015/2013_2015_FemPregData.dat", 9358),
  list("2013_2015_FemRespSetup", "NSFG 2013-2015/2013_2015_FemRespData.dat", 5699),
  list("2015_2017_FemPregSetup", "NSFG 2015-2017/2015_2017_FemPregData.dat", 9553),
  list("2015_2017_FemRespSetup", "NSFG 2015-2017/2015_2017_FemRespData.dat", 5554),
  list("2017_2019_FemPregSetup", "NSFG 2017-2019/2017_2019_FemPregData.dat", 10215),
  list("2017_2019_FemRespSetup", "NSFG 2017-2019/2017_2019_FemRespData.dat", 6141)
)

alnum <- function(s) gsub("[^A-Za-z0-9]", "", s)

# A label as asciiSetupReader makes it a name, letters and digits only:
# "+" to "plus" and the like, and an X before a leading digit.
as_name <- function(o) {
  for (r in list(c("+", "plus"), c("<", "under"), c(">", "over"), c("@", "at"), c("$", "dollar"))) {
    o <- gsub(r[1], r[2], o, fixed = TRUE)
  }
  o <- alnum(o)
  if (grepl("^[0-9]", o)) paste0("X", o) else o
}

# The input asciiSetupReader can read: paths of a data file and a setup.
oracle_input <- function(setup, data) {
  # Four setups are not UTF-8; read them as read_fixed_width does.
  text <- unlist(lapply(setup, function(f) {
    t <- readLines(f, warn = FALSE)
    if (all(validUTF8(t))) t else iconv(t, "windows-1252", "UTF-8")
  }))
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
  if (length(sel) || length(setup) > 1 || !identical(text, readLines(setup, warn = FALSE))) {
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

compare <- function(name, dat, rows, parts = name) {
  setup <- file.path(setup_dir, paste0(parts, ".sas"))
  dat <- file.path(data_dir, dat)
  time <- system.time(ours <- suppressWarnings(read_fixed_width(dat, setup, factors = FALSE)))
  input <- oracle_input(setup, dat)
  theirs <- suppressWarnings(read_ascii_setup(input$data, input$setup, use_value_labels = FALSE,
                                              use_clean_names = FALSE))
  parsed <- parse_setup(input$setup)
  # Whether the setup holds this text as a quoted string, as written.
  setup_text <- paste(readLines(input$setup, warn = FALSE), collapse = "\n")
  in_setup <- function(s) grepl(paste0('"', s, '"'), setup_text, fixed = TRUE) ||
    grepl(paste0("'", s, "'"), setup_text, fixed = TRUE)
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
  quoted <- character()
  spaced <- character()
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
      # It turns labels into names (as_name), adds the variable's name
      # where two labels are the same, and cuts long ones.
      ours_label <- attr(ours[[v]], "label") %||% ""
      t <- alnum(parsed$setup$column_name[i])
      same_label <- function(o) {
        tolower(t) %in% tolower(c(o, paste0(o, alnum(v)))) || (o == "" && t == alnum(v)) ||
          (nchar(t) >= 90 && startsWith(paste0(o, alnum(v)), t))
      }
      ok <- same_label(as_name(ours_label))
      # A double-quoted label with a quote inside (RING = "... RING OR
      # "NuvaRing"?"), as the setup writes it.
      if (!ok && grepl('"', ours_label, fixed = TRUE) && in_setup(ours_label) &&
          same_label(as_name(sub('".*', "", ours_label)))) {
        ok <- TRUE
        quoted <- c(quoted, v)
      }
      if (!ok) note(v, ": label differs: ours \"", ours_label, "\" | theirs ", parsed$setup$column_name[i])
    }
    want <- parsed$value_labels[[match(toupper(v), toupper(names(parsed$value_labels)))]]
    # Stata labels only numbers, so we skip a $ format (plan 0009).
    if (is.character(ours[[v]])) want <- NULL
    got <- attr(ours[[v]], "labels")
    got <- if (is.null(got)) numeric() else stats::setNames(as.numeric(got), names(got))
    if (!is.null(want) || length(got)) {
      want <- want %||% character()
      # Stata labels only integers, so we skip a range (3-6=), . and
      # other keys (plan 0009); it reads them as NA.
      want <- want[grepl("^\\s*-?[0-9]+\\s*$", want)]
      codes <- as.numeric(want)
      gone <- if (is.null(recoded)) numeric() else as.numeric(recoded$values[toupper(recoded$variable) == toupper(v)])
      keep <- !codes %in% gone
      want <- stats::setNames(codes[keep], names(want)[keep])
      pairs <- function(x, squish = identity) paste(sort(unname(x)), squish(names(x)[order(x)]))
      same <- identical(pairs(got), pairs(want))
      # A label with runs of spaces (1 = "1  PARTNER"), as the setup
      # writes it: it makes each run one space.
      one_space <- function(s) gsub(" +", " ", s)
      runs <- names(got)[grepl("  ", names(got), fixed = TRUE)]
      if (!same && length(runs) && all(vapply(runs, in_setup, TRUE)) &&
          identical(pairs(got, one_space), pairs(want))) {
        same <- TRUE
        spaced <- c(spaced, v)
      }
      if (!same) {
        note(v, ": value labels differ: ours ", paste(utils::head(paste0(got, "=", names(got)), 4), collapse = "; "),
             " | theirs ", paste(utils::head(paste0(want, "=", names(want)), 4), collapse = "; "))
      }
    }
  }
  if (length(quoted)) cat("     labels with a quote inside, which it ends there, compared up to it:", length(quoted), "\n")
  if (length(spaced)) cat("     value labels with runs of spaces, which it makes one, compared that way:", spaced, "\n")
  known_here <- known[[name]] %||% character()
  is_known <- vapply(problems, function(p) any(vapply(names(known_here), function(k) grepl(k, p), TRUE)), TRUE)
  for (k in names(known_here)) {
    if (any(vapply(problems, function(p) grepl(k, p), TRUE))) cat("     known:", known_here[[k]], "\n")
  }
  problems <- problems[!is_known]
  cat(sprintf("%-22s %6d rows %5d columns  %5.2f s  %s\n", name, nrow(ours), ncol(ours), time[["elapsed"]],
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
results <- lapply(files, function(f) do.call(compare, f))

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
