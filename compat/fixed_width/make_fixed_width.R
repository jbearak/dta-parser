# Write a synthetic fixed-width data file and its SAS setup file in the
# style CDC publishes for the NSFG cycles of 1973 to 1995 (plan 0009):
# header comment, libname, PROC FORMAT, an unnamed DATA step, column
# INPUT with overlapping columns and a string, LABEL, missing-value
# recodes, FORMAT and RUN. The data are made here from a fixed seed.
# Run from the repository root: Rscript compat/fixed_width/make_fixed_width.R
set.seed(20261101)
n <- 200
dir <- "compat/fixed_width"

vars <- list()
add <- function(name, width, values, label, labels = NULL, recode = NULL, string = FALSE) {
  vars[[length(vars) + 1]] <<- list(name = name, width = width, values = values, label = label,
                                    labels = labels, recode = recode, string = string)
}
yn <- c("(1) Yes" = 1, "(2) No" = 2, "(8) DK" = 8, "(9) Not ascertained" = 9)
add("CASEID", 5, 10000 + seq_len(n), "Case identification number")
for (i in 1:12) {
  add(sprintf("Q%02d", i), 1, sample(c(1, 2, 8, 9), n, TRUE, c(.5, .4, .06, .04)),
      sprintf("Question %d: did R's family agree; \"yes\" or no", i), yn,
      recode = if (i %% 3 != 0) c(8, 9) else if (i %% 2 == 0) 9)
}
for (i in 1:6) {
  add(sprintf("AGE%d", i), 2, sample(c(15:44, 98, 99), n, TRUE), sprintf("Age at event %d", i),
      c("(98) DK" = 98, "(99) Not ascertained" = 99), recode = c(98, 99))
}
add("INCOME", 6, sample(c(0:250000, 999998), n, TRUE), "Family income in dollars",
    c("(0) None" = 0, "(999998) Refused" = 999998), recode = 999998)
add("WEIGHT", 9, round(stats::runif(n, 1000, 99999), 2), "Post-stratified weight")
add("CHILDREN", 2, sample(c(0:12, 97, 98, 99), n, TRUE), "Number of children ever born",
    c("(0) None" = 0, "(97) Refused" = 97, "(98) DK" = 98, "(99) Not ascertained" = 99), recode = c(97, 98, 99))
add("CMBIRTH", 4, sample(c(700:1000, NA), n, TRUE), "Century month of birth (blank when not asked)")
add("STATE", 2, sample(c(-1, 1:56), n, TRUE), "State of residence",
    c("(-1) Abroad" = -1, "(6) California" = 6, "(36) New York" = 36))
add("RELIGION", 2, sample(c(1:5, 99), n, TRUE), "Religion raised in",
    c("(1) None" = 1, "(2) Catholic" = 2, "(3) Protestant" = 3), recode = 99)
add("INTVWR", 3, sample(c("ABC", "XY", "Q", "   "), n, TRUE), "Interviewer initials", string = TRUE)
add("FLAG1", 1, sample(0:3, n, TRUE), "Imputation flag",
    c("(0) No imputation" = 0, "(1) Hot deck imputation" = 1))
add("FLAG2", 1, sample(0:3, n, TRUE), "Imputation flag",
    c("(0) No imputation" = 0, "(1) Hot deck imputation" = 1))
add("BLANK", 3, rep(NA, n), "Blank")

# Columns: back to back, then two variables overlapping earlier ones.
start <- 1
for (i in seq_along(vars)) {
  vars[[i]]$begin <- start
  vars[[i]]$end <- start + vars[[i]]$width - 1
  start <- vars[[i]]$end + 1
}
lrecl <- start - 1
field <- function(v, x) {
  if (is.na(x)) return(strrep(" ", v$width))
  if (v$string) return(formatC(x, width = -v$width))
  text <- if (x == round(x)) sprintf("%.0f", x) else sprintf("%.2f", x)
  stopifnot(nchar(text) <= v$width)
  formatC(text, width = v$width)
}
lines <- vapply(seq_len(n), function(r) {
  paste(vapply(vars, function(v) field(v, v$values[[r]]), ""), collapse = "")
}, "")
writeLines(lines, file.path(dir, "synthetic.dat"), sep = "\r\n")

q <- function(s) paste0("'", gsub("'", "''", s), "'")
fmt <- function(v) paste0(tolower(v$name), "f")
setup <- c(
  "/*-------------------------------------------------------------------------",
  " |                             SAS SETUP FILE",
  " |           A SYNTHETIC SURVEY IN THE STYLE OF CDC'S NSFG SETUPS",
  " | Sections: LIBNAME, PROC FORMAT, DATA, INFILE, INPUT, LABEL,",
  " | MISSING VALUE RECODES (\"user-defined\" codes to SAS's .), FORMAT.",
  " |------------------------------------------------------------------------*/",
  "",
  "* DEFINING THE PATH TO PERMANENT SAS DATA SET LOCATION;",
  "",
  "libname \"data-file-path\";",
  "",
  "* SAS PROC FORMAT;",
  "",
  "PROC FORMAT;"
)
for (v in vars) {
  if (is.null(v$labels)) next
  pairs <- paste0(unname(v$labels), "=", q(names(v$labels)))
  setup <- c(setup, paste0("  VALUE ", fmt(v), "  ", paste(pairs, collapse = " "), " ;"))
}
spec <- vapply(vars, function(v) {
  cols <- if (v$begin == v$end) v$begin else paste0(v$begin, "-", v$end)
  paste0(v$name, if (v$string) " $", " ", cols)
}, "")
spec <- c(spec, paste0("AGE1_TENS ", vars[[which(vapply(vars, `[[`, "", "name") == "AGE1")]]$begin),
          "CASE_LAST2 4-5")
setup <- c(setup, "", "* SAS DATA, INFILE, INPUT STATEMENTS;", "", "DATA ;",
           paste0("INFILE \"c:\\temp\\synthetic.dat\" LRECL=", lrecl, ";"), "INPUT")
for (i in seq(1, length(spec), by = 3)) {
  setup <- c(setup, paste0("        ", paste(formatC(spec[i:min(i + 2, length(spec))], width = -24), collapse = "")))
}
setup <- c(setup, "        ;", "", "", "* SAS LABEL STATEMENT;", "", "LABEL")
for (v in vars) setup <- c(setup, paste0("   ", formatC(v$name, width = -8), "= ", q(v$label)))
setup <- c(setup, "   AGE1_TENS = 'Tens digit of age at event 1'", "   CASE_LAST2 = 'Last two digits of case'", "        ;",
           "", "", "* USER-DEFINED MISSING VALUES RECODE TO SAS SYSMIS;", "")
for (v in vars) {
  if (is.null(v$recode)) next
  cond <- paste0(v$name, " = ", v$recode, collapse = " OR ")
  setup <- c(setup, paste0("   IF (", cond, ") THEN ", v$name, " = .;"))
}
setup <- c(setup, "", "", "* SAS FORMAT STATEMENT;", "", "  FORMAT")
for (v in vars) if (!is.null(v$labels)) setup <- c(setup, paste0("         ", v$name, " ", fmt(v), "."))
setup <- c(setup, "  ;", "", "RUN ;")
writeLines(setup, file.path(dir, "synthetic.sas"), sep = "\r\n")
