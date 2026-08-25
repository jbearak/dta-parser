\name{recode}
\alias{recode}
\title{Recode values while preserving Stata missing tags}
\usage{
recode(.x, ..., .default = NULL, .missing = NULL)
}
\arguments{
\item{.x}{A numeric, character, or factor vector. Numeric storage may carry
Stata missing tags and Stata metadata attributes.}

\item{...}{Replacements in the legacy \code{dplyr::recode()} form. Numeric
replacements may be named by source value or supplied positionally; character
and factor replacements must be named.}

\item{.default}{Optional replacement for unmatched non-missing values. The
default \code{NULL} retains compatible source values.}

\item{.missing}{Optional replacement for missing values. The default
\code{NULL} preserves the exact system, extended, or \code{NaN} payload from
\code{.x}. A supplied value intentionally replaces every missing kind.
Following dplyr, factor inputs do not support a non-\code{NULL}
\code{.missing}.}
}
\value{
A recoded vector. Unmatched numeric missing values retain their exact payload
unless \code{.missing} is supplied.
}
\description{
Provides the familiar \code{dplyr::recode()} interface while retaining the
exact payload of every unmatched Stata system or extended missing value. It
also supports the numeric classes returned by \code{read_dta()}, including
\code{haven_labelled}, \code{Date}, and \code{POSIXct}.
}
\details{
Recoding materializes a numeric ALTREP vector because it creates a writable
result. When the result remains numeric, the original class and Stata metadata
attributes are restored. Value-label definitions are not rewritten when their
associated numeric codes change.

A recode from numeric to a non-numeric type cannot retain tagged-NA payloads.
If \code{.x} contains missing values and the result is non-numeric, supply
\code{.missing} explicitly to choose their new representation. Numeric widening
from integer to double preserves missing values automatically.

Class-changing numeric replacements, such as using \code{Date} or factor
values to recode a bare numeric vector, are rejected rather than silently
dropping the replacement class. Apply the desired class after recoding instead.

When the dtaparser namespace is loaded, \code{dplyr::recode()} dispatches here
for bare numeric, \code{haven_labelled}, \code{Date}, and \code{POSIXct}
vectors. This also applies when \code{recode()} is called inside
\code{dplyr::mutate()}, regardless of package attachment order. Ordinary
numeric vectors without tags retain dplyr's exact legacy behavior; tagged
vectors preserve unmatched tag payloads and numeric metadata.
}
\examples{
if (requireNamespace("haven", quietly = TRUE)) {
    x <- c(1, 2, NA_real_, haven::tagged_na(c("a", "z")))
    y <- recode(x, `1` = 10)
    haven::na_tag(y)

    recode(x, `1` = 10, .missing = -99)
}
}
