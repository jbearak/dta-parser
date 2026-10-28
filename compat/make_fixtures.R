# Write .dta fixtures with haven from data made here. Run from the
# repository root: Rscript compat/make_fixtures.R
library(haven)

out <- file.path("compat", "fixtures")
long_text <- strrep("long text ", 300)  # 3000 bytes: needs a strL

fixture <- data.frame(row = 1:6)
fixture$num <- labelled(
  c(1.5, -2.25, NA, tagged_na("a"), tagged_na("z"), 1e300),
  label = "A double with extended missing values"
)
fixture$answer <- labelled(
  c(1, 2, tagged_na("d"), tagged_na("g"), NA, 1),
  labels = c(Yes = 1, No = 2, `Don't know` = tagged_na("d"),
             `Not in universe` = tagged_na("g")),
  label = "Labelled codes, some missing"
)
fixture$count <- labelled(
  c(0L, 1L, 2L, NA, 100L, -100L),
  labels = c(None = 0L, One = 1L),
  label = "An integer"
)
fixture$text <- c("plain", "café", "中文", "", "trailing  ", "x")
attr(fixture$text, "label") <- "Text"
fixture$day <- as.Date("1960-01-01") + c(0, 1, -1, 365, NA, 20000)
fixture$big <- c(long_text, "short", "", paste0(long_text, "!"), long_text, "z")
attr(fixture, "label") <- "haven fixture"

# haven's `version` is the Stata version; 8 to 15 give releases 113 to 119.
for (stata in c(13, 14, 15)) {
  release <- c(`13` = 117, `14` = 118, `15` = 119)[[as.character(stata)]]
  write_dta(fixture, file.path(out, sprintf("haven_%d.dta", release)),
            version = stata, label = "haven fixture")
}
for (stata in c(8, 10, 12)) {
  release <- c(`8` = 113, `10` = 114, `12` = 115)[[as.character(stata)]]
  small <- fixture[setdiff(names(fixture), "big")]
  write_dta(small, file.path(out, sprintf("haven_%d.dta", release)),
            version = stata, label = "haven fixture")
}
