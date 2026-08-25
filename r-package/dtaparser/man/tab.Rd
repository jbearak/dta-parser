\name{tab}
\alias{tab}
\title{Tabulate vectors using Stata value labels}
\usage{
tab(
  x,
  ...,
  data = NULL,
  missing = FALSE,
  display = c("label", "value", "both")
)
}
\arguments{
\item{x}{A vector, or a data frame whose columns should be tabulated. When
\code{data} is supplied, an unquoted column name. The argument may be omitted
when \code{data} is supplied or named vectors are passed through \code{...}.}

\item{...}{Additional vectors or, when \code{x} or \code{data} is a data
frame, unquoted column names. All selected vectors must have the same length.}

\item{data}{Optional data frame in which to evaluate \code{x} and \code{...}.}

\item{missing}{How missing values should be handled. \code{FALSE} and
\code{"exclude"} omit them; \code{TRUE} and \code{"distinguish"} give Stata
system missing (\code{.}), every observed extended missing (\code{.a} through
\code{.z}), and R \code{NaN} separate categories; \code{"combine"} creates
one base-R missing category.}

\item{display}{How labelled values should be named: by \code{"label"} (the
default), underlying \code{"value"}, or \code{"both"}. An absent label always
falls back to the underlying value. Duplicate displayed labels are qualified
by their values.}
}
\value{
A standard \code{table} object.
}
\description{
Creates one-way or multidimensional frequency tables while using the value
labels and extended missing codes carried by vectors returned by
\code{read_dta()}. Ordinary unlabelled vectors retain the familiar behavior of
\code{base::table()}.
}
\details{
Calls may supply vectors directly, select unquoted names from \code{data}, or
pipe a data frame into \code{tab()}. A data frame passed as \code{x} contributes
all of its columns when no names follow it. Thus \code{tab(df)},
\code{tab(x, y, data = df)}, and \code{df |> tab(x, y)} are equivalent ways to
tabulate the corresponding columns.

Value labels affect only displayed dimension names. Categories remain ordered
by their underlying values. Unused value-label definitions do not create
zero-count categories. If displayed labels collide, their underlying values
are appended to keep every dimension name unambiguous.

With \code{missing = TRUE} or \code{"distinguish"}, numeric categories are
ordered after observed values as system missing, extended missings
\code{.a} through \code{.z}, and then R \code{NaN}. A labelled missing code
uses its value label unless \code{display = "value"}; otherwise its Stata code
is shown. \code{missing = "combine"} follows base R by collapsing all missing
numeric payloads into one category.
}
\examples{
if (requireNamespace("haven", quietly = TRUE)) {
    x <- haven::labelled(
        c(1, 2, 1, NA_real_, haven::tagged_na(c("a", "b"))),
        c(Yes = 1, No = 2, Refused = haven::tagged_na("a"))
    )

    table(x, useNA = "ifany")
    table(haven::as_factor(x), useNA = "ifany")
    tab(x, missing = TRUE)
    tab(x, missing = TRUE, display = "both")
}

mtcars |>
    tab(cyl, gear)
}
