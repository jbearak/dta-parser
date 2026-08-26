\name{read_dta}
\alias{read_dta}
\title{Read a Stata DTA file}
\usage{
read_dta(file, encoding = NULL, col_select = NULL, skip = 0,
  n_max = Inf, .name_repair = "unique",
  threads = getOption("dtaparser.threads", 0L),
  use_numeric_altrep = getOption("dtaparser.numeric_altrep", TRUE))
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
serial decoder. For selected \code{strL} columns, workers decode observation
references before the coordinator resolves their payloads.}
\item{use_numeric_altrep}{Whether byte, int, long, and float columns should retain
their compact Stata storage through ALTREP. Set to \code{FALSE} to create eager
R double vectors during decoding, which uses more memory but avoids later
widening when a workload requires a contiguous double data pointer.
Character-column ALTREP is unaffected.}
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
\section{Stata missing values}{
Stata system missing (\code{.}) is returned as \code{NA_real_}; in releases
supporting extended missings (113 and newer), \code{.a} through \code{.z} use
haven-compatible tagged-NA payloads. Base \code{is.na()} therefore identifies
every code present. Use \code{haven::na_tag()} to recover their letters,
\code{haven::is_tagged_na()} to select tagged values, and
\code{haven::tagged_na()} to create them. Use ordinary \code{NA_real_}, rather
than a tagged value, to create Stata system missing. Missing tags are part of
the numeric values and are distinct from Stata value labels stored in a
column's \code{labels} attribute.
Tagged missings can be stored in any R double vector; no Stata-specific class
is required. Assigning one to an R integer vector widens that vector to double
because R integers have only \code{NA_integer_}. This does not reflect a Stata
limitation: Stata \code{byte}, \code{int}, and \code{long} storage each encode
all 27 missing codes in reserved high values.

\code{dtaparser} therefore presents Stata numeric columns as R doubles. A
double can retain the tag in the payload bits of an IEEE-754 missing value, so
base \code{is.na()} works without a package-specific class or method and
haven's tag helpers remain interoperable. R integers have only one missing
encoding and could not expose \code{.a} through \code{.z} losslessly. The
R-facing double type does not require eight bytes per source value while the
column remains ALTREP: source \code{byte}, \code{int}, \code{long}, and
\code{float} values stay in their compact Stata storage and are converted to
doubles on access. A write or full materialization creates an ordinary R
double vector. This combines lossless missing-code semantics with compact
storage for read-mostly data.
For example:
\preformatted{x <- c(1, NA_real_, haven::tagged_na("a"), haven::tagged_na("z"))
is.na(x)
haven::na_tag(x)
haven::is_tagged_na(x)
haven::is_tagged_na(x, "a")
haven::na_tag(x) \%in\% c("a", "f")

x[1] <- NA_real_                 # Stata .
x[2] <- haven::tagged_na("a")    # Stata .a
x[3] <- haven::tagged_na("f")    # Stata .f
}
\code{haven::is_tagged_na()} accepts only one specific tag at a time; extract
tags with \code{haven::na_tag()} and use \code{\%in\%} to match several tags.

Base subassignment and \code{replace()} retain unselected tags when their index
contains no missing values; use \code{!is.na(x) & x == value} when recoding an
observed value. Avoid \code{ifelse(x == value, replacement, x)}, whose missing
condition entries become ordinary \code{NA} and lose their tags.

When recoding, \code{dplyr::case_when()} preserves values returned by its
default branch. \code{dplyr::if_else()} preserves unselected tags when its
condition is complete; if the condition can be \code{NA}, also supply
\code{missing = x}. Once the dtaparser namespace is loaded, \code{recode()} and
\code{dplyr::recode()} preserve unmatched tags in bare numeric,
\code{haven_labelled}, \code{Date}, and \code{POSIXct} columns, including
inside \code{dplyr::mutate()}. Missing-value replacement helpers match all 27
codes; select a particular code with \code{haven::is_tagged_na(x, tag)}
instead. A transformation may materialize an ALTREP column and may drop Stata
metadata attributes when it constructs a new vector, following the same
behavior as haven-compatible vectors.
}

\section{Labels and optional missing-code helpers}{
Reading DTA files and working with their labels does not require haven or
labelled. Use \code{var_label()}, \code{val_labels()}, \code{dataset_label()},
\code{set_variable_labels()}, and \code{set_value_labels()} to inspect or
change package-owned Stata metadata without materializing compact numeric
columns or dropping unrelated attributes. For example:
\preformatted{data <- data.frame(status = c(1, 2, 1))
var_label(data$status)
var_label(data$status) <- "Interview status"
val_labels(data$status)
val_labels(data$status) <- c(Complete = 1, Refused = 2)
}

The suggested haven package remains useful for inspecting, selecting, and
creating tagged missing values, and for conversions such as
\code{haven::as_factor()}:
\preformatted{haven::na_tag(data$status)
haven::is_tagged_na(data$status, "a")
data$status[1] <- haven::tagged_na("a")
}
Installing the tidyverse installs haven but \code{library(tidyverse)} does not
attach it, so use the explicit \code{haven::} prefix unless haven is attached.
See the
\href{https://github.com/jbearak/dta-parser/blob/main/docs/r-label-metadata.md}{R label metadata guide}
for bulk setters, Stata 19 limits, and the version-specific comparison with
labelled 2.16.0.
}
