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

Unmatched \code{NaN} values in a bare numeric \code{.x} retain their payload. A
storage-bearing Stata vector cannot contain \code{NaN}, so inserting one through
a replacement, \code{.default}, or \code{.missing} errors. Use \code{NA_real_} for
system missing or \code{\link[=tagged_missing]{tagged_missing()}} for an extended missing value. Arithmetic is
different: undefined results become system missing as described in
\code{\link[=stata_byte]{stata_byte()}}.

A recode from numeric to a non-numeric type cannot retain tagged-NA payloads.
If \code{.x} contains missing values and the result is non-numeric, supply
\code{.missing} explicitly to choose their new representation. Numeric widening
from integer to double preserves missing values automatically.

\code{dtaparser::recode()} rejects classed replacements such as \code{Date} or
factor values for bare numeric sources rather than silently dropping the
replacement class. Stata date and datetime sources accept \code{Date} and
\code{POSIXct} replacements, respectively. For other class changes, apply the
desired class after recoding.

When the dtaparser namespace is loaded, \code{dplyr::recode()} dispatches here
for bare numeric, \code{haven_labelled}, \code{Date}, and \code{POSIXct}
vectors. This also applies when \code{recode()} is called inside
\code{dplyr::mutate()}, regardless of package attachment order. For numeric
vectors without tags, this method retains dplyr's exact legacy behavior. Tagged
numeric vectors use \code{dtaparser::recode()} and preserve unmatched tag
payloads and numeric metadata.
}
\examples{
x <- c(1, 2, NA_real_, tagged_missing(c("a", "z")))
y <- recode(x, `1` = 10)
missing_tag(y)

recode(x, `1` = 10, .missing = -99)
}
