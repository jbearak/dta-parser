\name{summarize}
\alias{summarize}
\alias{summarise}
\alias{summ}
\title{Summarize variables using Stata's statistics}
\usage{
summarize(
  x, ..., data = NULL, where = NULL, rows = NULL, by = NULL,
  weights = NULL, weight = c("aweight", "fweight", "iweight"),
  detail = FALSE, meanonly = FALSE, format = FALSE, separator = 5,
  vsquish = FALSE, noemptycells = FALSE, baselevels = FALSE,
  allbaselevels = FALSE, nofvlabel = FALSE, fvwrap = 1,
  fvwrapon = c("word", "width"), time = NULL, panel = NULL, delta = 1
)

summarise(
  x, ..., data = NULL, where = NULL, rows = NULL, by = NULL,
  weights = NULL, weight = c("aweight", "fweight", "iweight"),
  detail = FALSE, meanonly = FALSE, format = FALSE, separator = 5,
  vsquish = FALSE, noemptycells = FALSE, baselevels = FALSE,
  allbaselevels = FALSE, nofvlabel = FALSE, fvwrap = 1,
  fvwrapon = c("word", "width"), time = NULL, panel = NULL, delta = 1
)

summ(
  x, ..., data = NULL, where = NULL, rows = NULL, by = NULL,
  weights = NULL, weight = c("aweight", "fweight", "iweight"),
  detail = FALSE, meanonly = FALSE, format = FALSE, separator = 5,
  vsquish = FALSE, noemptycells = FALSE, baselevels = FALSE,
  allbaselevels = FALSE, nofvlabel = FALSE, fvwrap = 1,
  fvwrapon = c("word", "width"), time = NULL, panel = NULL, delta = 1
)
}
\arguments{
\item{x}{A vector or data frame. With \code{data}, a column name or quoted
Stata varlist. Omit \code{x} to summarize all columns of \code{data}.}
\item{...}{Additional vectors, column names, or quoted Stata varlists.
When a data frame is supplied as \code{x}, these select its columns.}
\item{data}{Optional data frame in which to evaluate column names,
\code{where}, and \code{weights}.}
\item{where}{Logical expression selecting observations, corresponding to
Stata's \code{if} qualifier. Missing conditions are excluded.}
\item{rows}{Positive row positions, corresponding to Stata's \code{in}
qualifier. With groups, positions are relative to each group.}
\item{by}{Grouping columns. A grouped data frame uses its existing groups
when \code{by} is omitted. \code{.n} and \code{.N} in expressions give each
observation's position and its group's size.}
\item{weights}{Numeric expression evaluated in the data. Analytic and
frequency weights must be nonnegative. Importance weights may be negative.
Zero and missing weights exclude observations.}
\item{weight}{Weight type. Analytic weights are \code{"aweight"}, frequency
weights are \code{"fweight"}, and importance weights are \code{"iweight"}.
Frequency weights must be integers. Importance weights cannot be used
with \code{detail}. Probability weights are not supported by Stata's
\code{summarize}. Ignored when \code{weights} is omitted.}
\item{detail}{Include percentiles, skewness, kurtosis, and the four smallest
and largest observed values. As in Stata, factor-display options and
\code{fvwrap} controls cannot be combined with \code{detail}.}
\item{meanonly}{Compute counts, sums, means, and extrema without variance.
Returns invisibly and suppresses printing. Cannot be combined with
\code{detail}.}
\item{format}{Use each column's \code{format.stata} display attribute.
Numeric \code{f}, \code{fc}, \code{g}, and \code{gc} formats and all standard
calendar encodings \code{\%td}, \code{\%tc}, \code{\%tC}, \code{\%tw},
\code{\%tm}, \code{\%tq}, \code{\%th}, and \code{\%ty} are supported,
including the custom tokens documented in Stata's datetime display manual
and left-aligned calendar formats. Standard calendars cover years 0100
through 9999; values outside that range use numeric display.
The leap-second table for \code{\%tC} includes all insertions through 2016.
Business-calendar formats \code{\%tbname} and \code{\%tbname:picture} read
\file{name.stbcal} from the working directory or directories listed in
\code{getOption("dtatools.business_calendar_path")}. The loader supports
\code{range}, \code{centerdate}, \code{dateformat}, and the documented
\code{omit date}, \code{omit dayofweek}, and \code{omit dowinmonth} rules,
including date bounds, offsets, and conditional restrictions. Missing or
invalid calendar files and codes outside their range use numeric display,
as Stata does. Unknown calendar-picture tokens raise an error.}
\item{separator}{Draw a separator after this many summary rows. The absolute
value of an integer is used. Zero
suppresses separators. Corresponds to Stata's \code{separator()} option.}
\item{vsquish}{Suppress blank lines around factor and time-series terms.}
\item{noemptycells}{Suppress unobserved factor combinations in the display.}
\item{baselevels, allbaselevels}{Display factor base levels.}
\item{nofvlabel}{Display factor levels using numeric values instead of
value labels.}
\item{fvwrap}{Maximum number of lines for factor-level labels.}
\item{fvwrapon}{Wrap factor labels at words or at the available width.}
\item{time}{Time column for Stata time-series operators, supplied as a
column name string. Time values must identify observations uniquely
within each panel.}
\item{panel}{Optional panel column name string for time-series operators.}
\item{delta}{Distance between consecutive time values. Defaults to one.}
}
\description{
Computes and displays descriptive statistics using Stata's
\code{summarize} conventions. \code{summarise} and \code{summ} are aliases
with the same arguments and return value.
}
\details{
The default table reports each variable's nonmissing observation count,
mean, sample standard deviation, minimum, and maximum. String variables
have zero numeric observations. System and extended Stata missing values,
R \code{NA}, and \code{NaN} are excluded separately for each variable.

\code{detail = TRUE} also reports variance, skewness, kurtosis, and the
1st, 5th, 10th, 25th, 50th, 75th, 90th, 95th, and 99th percentiles.
Percentiles locate the interval containing the target cumulative weight.
An exact boundary averages adjacent ordered values. As in Stata, a boundary
tolerance of \code{1e-5} percentage points also permits averaging when only
one edge of the interval is near the target; a target near both edges
retains the observation inside that interval. Floating-point rounding at
the tolerance cutoff can differ from native Stata. If the weight total
overflows, detailed percentiles are zero, matching Stata's overflow result.
Frequency weights count repetitions for statistics; the displayed
four smallest and largest values are taken from source observations.
Skewness and kurtosis use population central moments. Kurtosis is not
excess kurtosis, so the normal-distribution reference value is three.

Analytic weights retain the count of source observations and normalize
weights when calculating sample variance. Frequency weights use their sum
as the observation count. Importance weights retain the source count but
use the sum of weights minus one in the variance denominator. Means use
the weighted sum divided by the sum of weights in each case. The default
table includes a Weight column for analytic and importance weights.

A quoted varlist supports Stata variable names, abbreviations, wildcards,
variable ranges, factor terms such as \code{"i.group"}, interactions such
as \code{"i.group##c.age"}, and time-series terms such as \code{"L.income"}.
Supply \code{time}, and \code{panel} when needed, for time-series terms.
Gaps in time produce missing lags or leads. Variable labels appear in
detailed headings and value labels appear in factor-level rows.
Numlist increments use their magnitude, with the direction determined by
the endpoints. Each numlist may expand to at most 100,000 entries before
duplicates are removed.

R arguments provide the roles of Stata qualifiers and prefixes:
\code{where} for \code{if}, \code{rows} for \code{in}, and \code{by} or an
existing grouped data frame for \code{by:}. Stata's surrounding command
environment, including \code{collect}, \code{statsby}, \code{rolling},
\code{bootstrap}, and \code{jackknife} prefixes, is not interpreted.
Results are ordinary R objects that can be collected or resampled by
calling this function from R.
}
\value{
A \code{dta_summarize} object containing:
\item{statistics}{A data frame with one row per variable and group, and
columns \code{variable}, \code{N}, \code{sum_w}, \code{mean}, \code{Var},
\code{sd}, \code{min}, \code{max}, and \code{sum}. Detailed results add
\code{skewness}, \code{kurtosis}, and percentile columns \code{p1} through
\code{p99}. \code{meanonly} omits the \code{Var} and \code{sd} columns.
Unavailable statistics are missing. Factor base and empty
levels remain in this data frame even when display options hide them.}
\item{r}{The named scalars Stata would leave in \code{r()} for the last
variable in the last group.}
\item{smallest, largest}{Lists of four extreme values per result row for
detailed summaries, padded with missing values when needed.}
\item{groups}{Group keys aligned with the statistic rows.}
\item{headers, formats, options}{Metadata used for printing.}
\code{as.data.frame()} returns the statistics with group keys attached.
\code{format()} returns the printed lines. \code{meanonly = TRUE} returns
invisibly, and both \code{format()} and \code{print()} remain silent.
}
\seealso{
\code{\link{tab}}, \code{\link{set_var_format}},
\href{https://www.stata.com/manuals/rsummarize.pdf}{Stata summarize manual}.
}
\examples{
summarize(mtcars, mpg, wt)
summarise(mtcars, mpg, detail = TRUE)
summ(mtcars, mpg, where = cyl == 6, rows = 1:20)
summarize(mtcars, mpg, by = cyl)
summarize(mtcars, mpg, weights = wt, weight = "aweight")
summarize(mtcars, "i.cyl")

result <- summarize(mtcars, mpg, meanonly = TRUE)
result$r$mean
as.data.frame(result)
}
