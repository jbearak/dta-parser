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
