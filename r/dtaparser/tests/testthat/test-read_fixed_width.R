# read_fixed_width reads fixed-width text through a SAS setup file (plan
# 0009). What each value should be follows from the setup text written
# here; the converted file is also read with haven and readstata13, which
# check the letters, value labels and long labels independently.

fw_setup <- c(
  "/* A setup in CDC's style */",
  "libname \"data-file-path\";",
  "PROC FORMAT;",
  "  VALUE sexf  1='(1) Boy' 2='(2) Girl' ;",
  "  VALUE kidsf 0='(0) None' 98='(98) DK' 99='(99) Not ascertained' ;",
  "DATA ;",
  "INFILE \"c:\\temp\\x.dat\" LRECL=6;",
  "INPUT ID 1-3 SEX 4 KIDS 5-6 ;",
  "LABEL ID = 'Case number' SEX = \"R's sex\"",
  paste0("  KIDS = '", strrep("k", 200), "' ;"),
  "IF (KIDS = 98 OR KIDS = 99) THEN KIDS = .;",
  "FORMAT SEX sexf. KIDS kidsf. ;",
  "RUN ;"
)
fw_data <- c("0011 2", "002298", "003199", "004199", "0052 0")

fw_files <- function(setup = fw_setup, data = fw_data) {
  dir <- tempfile()
  dir.create(dir)
  writeLines(setup, file.path(dir, "x.sas"))
  writeLines(data, file.path(dir, "x.dat"))
  c(data = file.path(dir, "x.dat"), setup = file.path(dir, "x.sas"))
}

test_that("setup mode applies the recodes as written", {
  f <- fw_files()
  df <- read_fixed_width(f[["data"]], f[["setup"]])
  expect_s3_class(df, "tbl_df")
  expect_named(df, c("ID", "SEX", "KIDS"))
  expect_identical(as.vector(df$ID), 1:5)
  expect_identical(as.character(df$SEX), c("(1) Boy", "(2) Girl", "(1) Boy", "(1) Boy", "(2) Girl"))
  # 98 and 99 are NA; their labels are gone, so the factor has one level.
  expect_identical(levels(df$KIDS), c("(0) None", "2"))
  expect_identical(as.character(df$KIDS), c("2", NA, NA, NA, "(0) None"))
  expect_identical(attr(df$ID, "label"), "Case number")
  expect_identical(attr(df$SEX, "label"), "R's sex")
  expect_identical(attr(df$KIDS, "label"), strrep("k", 200))
  expect_null(attr(df, "warnings"))
})

test_that("tagged mode keeps labelled missings, and factors defaults to FALSE", {
  f <- fw_files()
  df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "tagged")
  expect_type(df$KIDS, "double")
  expect_identical(haven::na_tag(df$KIDS), c(NA, "a", "b", "b", NA))
  expect_identical(is.na(df$KIDS), c(FALSE, TRUE, TRUE, TRUE, FALSE))
  labels <- attr(df$KIDS, "labels")
  expect_identical(names(labels), c("(0) None", "(98) DK", "(99) Not ascertained"))
  expect_identical(haven::na_tag(labels), c(NA, "a", "b"))
  # SEX has ordinary labels and no recodes: numbers and labels too.
  expect_identical(unclass(df$SEX)[1:2], c(1L, 2L))
  expect_warning(
    df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "tagged", factors = TRUE),
    class = "dtaparser_extended_missing"
  )
  expect_s3_class(df$KIDS, "factor")
})

test_that("recodes = \"none\" keeps the codes", {
  f <- fw_files()
  df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE)
  expect_identical(df$KIDS, structure(c(2L, 98L, 99L, 99L, 0L), label = strrep("k", 200),
                                      labels = c(`(0) None` = 0, `(98) DK` = 98, `(99) Not ascertained` = 99)))
  expect_error(read_fixed_width(f[["data"]], f[["setup"]], recodes = "letters"), "should be one of")
})

test_that("col_select, skip and n_max apply to the result", {
  f <- fw_files()
  df <- read_fixed_width(f[["data"]], f[["setup"]], col_select = c(KIDS, ID), skip = 1, n_max = 2)
  expect_named(df, c("KIDS", "ID"))
  expect_identical(as.vector(df$ID), 2:3)
})

test_that("warnings are one classed warning and an attribute", {
  setup <- c("PROC FORMAT; VALUE f 1-5='low';", "DATA; INPUT X 1;", sprintf("y%d = x * 2;", 1:10))
  f <- fw_files(setup, c("1", "2"))
  expect_warning(df <- read_fixed_width(f[["data"]], f[["setup"]]), class = "dtaparser_fixed_width_warning")
  expect_length(attr(df, "warnings"), 11)
  w <- tryCatch(read_fixed_width(f[["data"]], f[["setup"]]), warning = function(w) conditionMessage(w))
  expect_match(w, "3 more", fixed = TRUE)
  expect_lt(nchar(w), 1000)
})

test_that("errors name the setup line, and leave no temporary files", {
  before <- Sys.glob(file.path(tempdir(), "dtaparser*"))
  f <- fw_files(c("DATA;", "INPUT X 1. ;"), "1")
  expect_error(read_fixed_width(f[["data"]], f[["setup"]]), "setup line 2: INPUT form not supported")
  expect_identical(Sys.glob(file.path(tempdir(), "dtaparser*")), before)
  df <- read_fixed_width(fw_files()[["data"]], fw_files()[["setup"]])
  expect_identical(Sys.glob(file.path(tempdir(), "dtaparser*")), before)
})

test_that("haven and readstata13 read the tagged file's letters and labels", {
  skip_if_not_installed("haven")
  f <- fw_files()
  out <- tempfile(fileext = ".dta")
  .Call(C_dta_fixed_width, f[["data"]], f[["setup"]], out, "tagged", TRUE)
  h <- haven::read_dta(out)
  expect_identical(haven::na_tag(h$KIDS), c(NA, "a", "b", "b", NA))
  labels <- attr(h$KIDS, "labels")
  expect_identical(names(labels), c("(0) None", "(98) DK", "(99) Not ascertained"))
  expect_identical(haven::na_tag(unname(labels)), c(NA, "a", "b"))
  expect_identical(attr(h$KIDS, "label"), strrep("k", 200))
  skip_if_not_installed("readstata13")
  r <- suppressWarnings(readstata13::read.dta13(out, convert.factors = FALSE, missing.type = TRUE))
  # readstata13 numbers .a as 1 and .b as 2.
  expect_identical(attr(r, "missing")$KIDS, c(NA, 1, 2, 2, NA))
  expect_identical(attr(r, "var.labels")[3], strrep("k", 200))
})

# CDC's setups from 2006-2010 on put the PROC FORMAT step and the FORMAT
# statement each in a block comment; their lines end in CRLF until
# 2011-2013.
fw_commented <- c(
  "/*-----------------------------------------------",
  " | PROC FORMAT:  creates user-defined formats; FORMAT: attaches them.",
  " | Sections for PROC FORMAT and FORMAT have been commented out.",
  " |----------------------------------------------*/",
  "* SAS PROC FORMAT;",
  "/*",
  "PROC FORMAT;",
  "VALUE sexf 1 = 'Boy' 2 = 'Girl' ;",
  "VALUE kidsf 0 = 'None' 98 = 'DK' ;",
  "QUIT;",
  "*/",
  "* SAS DATA, INFILE, INPUT STATEMENTS;",
  "DATA;",
  "INFILE \"data-filename\" LRECL=5;",
  "INPUT ID 1-2 SEX 3 KIDS 4-5 ;",
  "* SAS LABEL STATEMENT;",
  "LABEL ID = 'Case' SEX = 'Sex' KIDS = 'Kids' ;",
  "* SAS FORMAT STATEMENT;",
  "/*",
  "FORMAT",
  "   SEX sexf.",
  "   KIDS kidsf. ;",
  "*/",
  "RUN ;"
)
fw_commented_data <- c("01100", "02298")

# Write lines with CRLF endings.
write_crlf <- function(lines, path) writeBin(charToRaw(paste0(lines, "\r\n", collapse = "")), path)

fw_crlf <- function(setup = fw_commented) {
  dir <- tempfile()
  dir.create(dir)
  write_crlf(setup, file.path(dir, "x.sas"))
  write_crlf(fw_commented_data, file.path(dir, "x.dat"))
  c(data = file.path(dir, "x.dat"), setup = file.path(dir, "x.sas"))
}

test_that("commented-out PROC FORMAT and FORMAT are read, unless commented_formats = FALSE", {
  f <- fw_crlf()
  df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE)
  expect_null(attr(df, "warnings"))
  expect_identical(attr(df$SEX, "labels"), c(Boy = 1, Girl = 2))
  expect_identical(attr(df$KIDS, "labels"), c(None = 0, DK = 98))
  expect_identical(as.vector(df$KIDS), c(0L, 98L))
  off <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE, commented_formats = FALSE)
  expect_null(attr(off$SEX, "labels"))
  expect_null(attr(off$KIDS, "labels"))
  expect_identical(as.vector(off$KIDS), as.vector(df$KIDS))
  expect_identical(attr(off$KIDS, "label"), "Kids")
  expect_error(read_fixed_width(f[["data"]], f[["setup"]], commented_formats = NA), "TRUE or FALSE")
})

test_that("a commented PROC FORMAT or a commented FORMAT alone is read", {
  only_proc <- fw_commented[-c(19, 23)]
  only_format <- fw_commented[-c(6, 11)]
  for (setup in list(only_proc, only_format)) {
    f <- fw_crlf(setup)
    df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE)
    expect_identical(attr(df$KIDS, "labels"), c(None = 0, DK = 98))
    off <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE, commented_formats = FALSE)
    expect_null(attr(off$KIDS, "labels"))
  }
})

test_that("a comment that mentions PROC FORMAT stays a comment", {
  # Read as code, each would end the DATA step before LABEL, or fail.
  for (comment in c("/* PROC FORMAT: see the codebook; */", "/* PROC FORMAT; VALUE labels are below */",
                    "/* FORMAT statements: below; */")) {
    setup <- replace(fw_commented, 16, comment)
    f <- fw_crlf(setup)
    df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE)
    expect_null(attr(df, "warnings"))
    expect_identical(attr(df$KIDS, "label"), "Kids")
  }
})

test_that("a setup in several files reads as the files joined", {
  # CDC's 2002 setups: the DATA step, LABEL, then PROC FORMAT and FORMAT.
  input <- c("FILENAME datafile 'x.dat' ;", "DATA &dataset ;", "INFILE datafile LRECL=5;",
             "INPUT ID $ 1-2 SEX 3 KIDS 4-5 ;", "RUN;")
  label <- c("LABEL", " /* SECTION A */", "  ID = \"RESPONDENT ID\"", "  KIDS = \"NUMBER OF KIDS\"", "  ;")
  value <- c("PROC FORMAT;", "VALUE SEXF 1 = \"BOY\" 2 = \"GIRL\" ;", "VALUE KIDSF 98 = \"DK\" ;", "RUN;",
             "FORMAT SEX SEXF. KIDS KIDSF. ;", "RUN;")
  dir <- tempfile()
  dir.create(dir)
  paths <- file.path(dir, c("Input.sas", "VarLabel.sas", "ValueLabel.sas", "all.sas"))
  write_crlf(input, paths[1])
  write_crlf(label, paths[2])
  write_crlf(value, paths[3])
  write_crlf(c(input, label, value), paths[4])
  write_crlf(fw_commented_data, file.path(dir, "x.dat"))
  read <- function(setup) {
    suppressWarnings(read_fixed_width(file.path(dir, "x.dat"), setup, recodes = "none", factors = FALSE))
  }
  files <- read(paths[1:3])
  joined <- read(paths[4])
  expect_identical(lapply(files, as.vector), lapply(joined, as.vector))
  expect_identical(lapply(files, attributes), lapply(joined, attributes))
  expect_identical(attr(files$SEX, "labels"), c(BOY = 1, GIRL = 2))
  expect_identical(attr(files$KIDS, "label"), "NUMBER OF KIDS")
  expect_null(attr(files, "warnings"))
  # Errors name a file by its place in `setup`.
  write_crlf(c("LABEL KIDS 3;"), paths[2])
  expect_error(read(paths[1:3]), "setup file 2 line 1: LABEL KIDS", fixed = TRUE)
  expect_error(read_fixed_width(file.path(dir, "x.dat"), character()), "one or more paths")
})

test_that("QUIT ends a PROC step like RUN", {
  f <- fw_files(c("DATA; INPUT X 1;", "PROC FORMAT; VALUE f 1='one'; QUIT;", "FORMAT X f.;"), c("1", "2"))
  df <- read_fixed_width(f[["data"]], f[["setup"]], recodes = "none", factors = FALSE)
  expect_null(attr(df, "warnings"))
  expect_identical(attr(df$X, "labels"), c(one = 1))
})

test_that("a label with stray quotes is read whole, with a warning naming its line", {
  setup <- c(
    "DATA; INPUT SALMX1 1 RING 2 C 3;",
    "LABEL",
    "  SALMX1 = \"FLAG INDICATING WHETHER \" SAME AS LAST MONTH\" WAS ORIGINAL ANSWER\"",
    "  RING = \"EVER USED RING OR \"NUVARING\"?\"",
    "  C 'no equals' ;"
  )
  dir <- tempfile()
  dir.create(dir)
  write_crlf(setup, file.path(dir, "x.sas"))
  write_crlf("123", file.path(dir, "x.dat"))
  expect_warning(
    df <- read_fixed_width(file.path(dir, "x.dat"), file.path(dir, "x.sas")),
    class = "dtaparser_fixed_width_warning"
  )
  expect_identical(attr(df$SALMX1, "label"), "FLAG INDICATING WHETHER \" SAME AS LAST MONTH\" WAS ORIGINAL ANSWER")
  expect_identical(attr(df$RING, "label"), "EVER USED RING OR \"NUVARING\"?")
  expect_identical(attr(df$C, "label"), "no equals")
  expect_identical(attr(df, "warnings"), c(
    "line 3: the label of SALMX1 has quotes inside it; it is read from its first quote to its last",
    "line 4: the label of RING has quotes inside it; it is read from its first quote to its last"
  ))
})
