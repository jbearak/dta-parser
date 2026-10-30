# The writer reads packed data columns from their text (plan 0007), and
# makes packed vectors found anywhere else in the spec before Rust reads
# them as metadata.

test_that("a packed vector given as notes and characteristic values is made, then written", {
  src <- tempfile(fileext = ".dta")
  spec_src <- list(
    columns = list(c("first note é", "second note", "x")), names = "s", storage = "str", formats = "%9s",
    labels = "", label_sets = "", sets = list(), data_label = "", timestamp = "01 Jan 2026 00:00",
    notes = character(), characteristics = list(character(), character(), character()), sort_order = integer()
  )
  .Call(dtaparser:::C_dta_write, src, spec_src)
  notes <- read_dta(src)$s
  values <- read_dta(src)$s
  expect_gte(state(notes), 0)
  expect_gte(state(values), 0)

  path <- tempfile(fileext = ".dta")
  spec <- list(
    columns = list(c(1, 2, 3)), names = "x", storage = "double", formats = "%9.0g",
    labels = "", label_sets = "", sets = list(), data_label = "", timestamp = "01 Jan 2026 00:00",
    notes = notes,
    characteristics = list(rep("x", 3), c("a", "b", "c"), values),
    sort_order = integer()
  )
  .Call(dtaparser:::C_dta_write, path, spec)
  expect_identical(state(notes), -1)
  expect_identical(state(values), -1)

  expect_identical(attr(read_dta(path), "notes"), c("first note é", "second note", "x"))
  chars <- .Call(dtaparser:::C_dta_meta, path, NULL)$characteristics
  expect_identical(chars$value[chars$variable == "x"], c("first note é", "second note", "x"))
})

# Reads with the parallel path forced (plan 0007): tiny chunks, four
# threads, every read eligible.
with_parallel <- function(code) {
  old_env <- Sys.getenv("DTA_TEST_SMALL_CHUNKS", unset = NA)
  old_opt <- options(dtaparser.threads = 4)
  on.exit({
    options(old_opt)
    if (is.na(old_env)) Sys.unsetenv("DTA_TEST_SMALL_CHUNKS") else Sys.setenv(DTA_TEST_SMALL_CHUNKS = old_env)
  })
  Sys.setenv(DTA_TEST_SMALL_CHUNKS = "1")
  force(code)
}

test_that("a byte column with .a only in its last chunk reads the same in parallel", {
  skip_if_not_installed("haven")
  n <- 20000
  b <- as.double(seq_len(n) %% 50)
  b[n] <- haven::tagged_na("a")
  d <- seq_len(n) / 4
  d[7] <- haven::tagged_na("q")
  path <- write_fixture(b = col(b, "byte"), d = col(d, "double"), s = col(rep(c("x", "yé"), n / 2), "str", "%9s"))
  old <- options(dtaparser.threads = 1)
  serial <- read_dta(path)
  options(old)
  parallel <- with_parallel(read_dta(path))
  expect_identical(parallel, serial)
  expect_type(parallel$b, "double")
  expect_identical(haven::na_tag(parallel$b[n]), "a")
  expect_identical(haven::na_tag(parallel$d[7]), "q")
  expect_identical(parallel$b[1:3], c(1, 2, 3))
})
