\name{read_dta}
\alias{read_dta}
\title{Read a Stata DTA file}
\usage{
read_dta(file, encoding = NULL, col_select = NULL, skip = 0,
  n_max = Inf, .name_repair = "unique",
  threads = getOption("dtaparser.threads", 0L))
}
\arguments{
\item{file}{A path, URL, raw vector, or binary connection. Local and remote
gzip files and local bzip2, xz, and zip files are decompressed automatically.
Character vectors containing literal data are not handled, matching
\code{haven::read_dta()}. URLs are fetched at call time; applications accepting
untrusted \code{file} values should validate or allowlist sources before calling
\code{read_dta()}.}
\item{encoding}{Optional source encoding override. Supported aliases are
\code{"UTF-8"}/\code{"UTF8"}, \code{"Windows-1252"}/\code{"CP1252"}, and
\code{"ISO-8859-1"}/\code{"latin1"}, matched case-insensitively. \code{NULL}
uses Windows-1252 for releases 105, 108, 110--111, 113--115, and 117 and UTF-8 for releases
118--119. The override
applies to metadata, fixed strings, \code{strL} payloads, and value-label
names and text. Explicit UTF-8 replaces malformed input sequences
deterministically with U+FFFD. Haven 2.5.5 may instead omit an affected label.}
\item{col_select}{One or more tidyselect expressions. Predicates treat Stata
string storage as character and numeric storage as double. If a source
variable is selected more than once, the first selection and alias win.}
\item{skip}{Number of observations to skip. Must be one non-negative whole
number no larger than \code{2^53}.}
\item{n_max}{Maximum observations to read. \code{NA}, either infinity, and
negative finite values read all remaining rows, following haven's unlimited-row
convention. Non-negative values must be whole numbers no larger than
\code{2^53}.}
\item{.name_repair}{Name repair passed to \code{tibble::as_tibble()}.}
\item{threads}{Number of decoder threads. Zero selects an automatic count for
sufficiently large files in any supported Stata release. One always uses the
serial decoder. Projections containing \code{strL} remain serial.}
}
\value{A tibble containing native numeric and character vectors. Byte, int,
long, and float columns retain their compact Stata storage width until R
requests a materialized double vector; source doubles are created eagerly.
\code{\%td} columns and legacy or custom formats beginning \code{\%d} have class
\code{Date}; \code{\%tc} and \code{\%tC} columns have classes \code{POSIXct}
and \code{POSIXt} in UTC. Other Stata temporal formats remain numeric with
their \code{format.stata} attribute.}
\description{
Reads Stata releases 105, 108, 110--111, 113--115, and 117--119 through the native Rust parser,
retaining dataset and variable labels, dataset notes, formats, value labels,
long strings, temporal classes, and Stata tagged missing values.
}
