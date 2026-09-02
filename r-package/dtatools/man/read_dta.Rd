\name{read_dta}
\alias{read_dta}
\title{Read a Stata DTA file}
\usage{
read_dta(file, encoding = NULL, col_select = NULL, skip = 0,
  n_max = Inf, .name_repair = "unique",
  output = c("default", "dibble", "tibble", "data.table"),
  threads = getOption("dtatools.threads", 0L),
  use_numeric_altrep = getOption("dtatools.numeric_altrep", TRUE),
  datasig = FALSE)
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
\item{output}{Output container. \code{"default"} uses the
\code{dtatools.output} option, falling back to \code{"dibble"}. Supply
\code{"dibble"}, \code{"tibble"}, or \code{"data.table"} to override the
option. Data-table output requires the suggested data.table package.}
\item{threads}{Number of decoder threads. Zero selects an automatic count for
sufficiently large files in any supported Stata release. One always uses the
serial decoder. For selected \code{strL} columns, workers decode observation
references before the coordinator resolves their payloads.}
\item{use_numeric_altrep}{Whether byte, int, long, and float columns should retain
their compact Stata storage through ALTREP. Set to \code{FALSE} to create eager
R double vectors during decoding, which uses more memory but avoids later
widening when a workload requires a contiguous double data pointer.
Character-column ALTREP is unaffected.}
\item{datasig}{Whether to record the file's \code{\link{datasig}} signature in
the result's \code{datasig} attribute, as a load-time record of what the file
on disk signed as; it is never updated afterwards, so it is not a claim about
the object's current content. Computing it costs one hash pass over the
decoded columns (no second read of the file) and equals \code{datasig(file)}.
Requires reading the complete file: incompatible with \code{col_select},
\code{skip}, and \code{n_max}.}
}
\value{A \link{dibble}, tibble, or data table containing native numeric and
owned Stata string vectors. Numeric
columns carry their declared Stata storage type. Byte, int, long, and float
columns retain their compact Stata storage width until R requests a
materialized double vector; source doubles are created eagerly.
\code{\%td} columns and legacy or custom formats beginning \code{\%d} have class
\code{Date}; \code{\%tc} and \code{\%tC} columns have classes \code{POSIXct}
and \code{POSIXt} in UTC. Other Stata temporal formats remain numeric with
their \code{format.stata} attribute. String storage and metadata survive
supported vector operations.}
\description{
Reads Stata releases 105, 108, 110--111, 113--115, and 117--119 through the native Rust parser,
retaining dataset and variable labels, dataset notes, formats, value labels,
long strings, temporal classes, and Stata tagged missing values.
Stata stores named value-label definitions at dataset scope and assigns a
definition to each labelled variable. \code{read_dta()} instead gives each
variable its resolved code-to-text mapping in \code{labels}. An imported table
name may also appear in \code{value.label.name} when it differs from the source
variable name or the source table is shared. That attribute is a serialization
hint, not a live shared table or a semantic namespace. Changing one variable's
mapping does not change another variable that came from the same Stata
definition. Projection checks all source variables when deciding whether to
retain the name hint.
}
\section{Stata missing values}{
Stata system missing (\code{.}) is returned as \code{NA_real_}; in releases
supporting extended missings (113 and newer), \code{.a} through \code{.z} use
haven-compatible tagged-NA payloads. Base \code{is.na()} therefore identifies
every code present. Use \code{missing_tag()} to recover their letters,
\code{is_tagged_missing()} to select tagged values, and
\code{tagged_missing()} to create them. Use ordinary \code{NA_real_}, rather
than a tagged value, to create Stata system missing. Missing tags are part of
the numeric values and are distinct from Stata value labels stored in a
column's \code{labels} attribute.
Tagged missings can be stored in any R double vector; the missing payload
itself does not require a Stata-specific class. Imported Stata numerics carry
a class so their storage declaration survives supported operations. Assigning
one to an R integer vector widens that vector to double
because R integers have only \code{NA_integer_}. This does not reflect a Stata
limitation: Stata \code{byte}, \code{int}, and \code{long} storage each encode
all 27 missing codes in reserved high values.

\code{dtatools} therefore presents Stata numeric columns as R doubles. A
double can retain the tag in the payload bits of an IEEE-754 missing value, so
base \code{is.na()} works without a package-specific class or method and
haven's tag helpers remain interoperable. R integers have only one missing
encoding and could not expose \code{.a} through \code{.z} losslessly. The
R-facing double type does not require eight bytes per source value while the
column remains ALTREP: source \code{byte}, \code{int}, \code{long}, and
\code{float} values stay in their compact Stata storage and are converted to
doubles on access. Supported mutations validate and re-encode the result. A
full materialization widens the backing to R doubles but retains the declared
storage class. This combines lossless missing-code semantics with compact
steady-state storage.
For example:
\preformatted{x <- c(1, NA_real_, tagged_missing("a"), tagged_missing("z"))
is.na(x)
missing_tag(x)
is_tagged_missing(x)
is_tagged_missing(x, "a")
is_tagged_missing(x, c("a", "f"))

x[1] <- NA_real_                 # Stata .
x[2] <- tagged_missing("a")       # Stata .a
x[3] <- tagged_missing("f")       # Stata .f
}

Imported Stata-backed numeric and temporal vectors compare missing codes as
Stata does, so \code{x == value} returns definite logical values for \code{.},
\code{.a} through \code{.z}. Base subassignment, \code{replace()},
\code{ifelse()}, and \code{dplyr::if_else()} therefore retain unselected
missing-code identities. Bare double vectors keep ordinary R
missing-propagating comparison behavior.

When recoding, \code{dplyr::case_when()} preserves values returned by its
default branch. For a condition built from bare R values that can be \code{NA},
supply \code{missing = x} to \code{dplyr::if_else()}. Once the dtatools
namespace is loaded, \code{recode()} and
\code{dplyr::recode()} preserve unmatched tags in bare numeric,
\code{haven_labelled}, \code{Date}, and \code{POSIXct} columns, including
inside \code{dplyr::mutate()}. Missing-value replacement helpers match all 27
codes; select particular extended missing codes with
\code{is_tagged_missing(x, tag)}
instead. A transformation may materialize an ALTREP column and may drop Stata
metadata attributes when it constructs a new vector, following the same
behavior as haven-compatible vectors.
}

\section{Stata storage declarations}{
\code{stata_storage_type()} reports \code{"byte"}, \code{"int"},
\code{"long"}, \code{"float"}, or \code{"double"} without materializing
compact backing. Use \code{stata_byte()}, \code{stata_int()},
\code{stata_long()}, \code{stata_float()}, and \code{stata_double()} to
declare storage for derived vectors. Constructors and explicit casts reject
unrepresentable values and name the wider constructor to use. Float
construction rounds to binary32, as Stata does.

Subassignment, \code{replace()}, \code{dplyr::if_else()}, and
\code{dplyr::mutate()} retain declared storage and re-encode compact results.
Arithmetic starts at the operands' common Stata storage type and widens only
when the result values require it. Imported \code{Date} and \code{POSIXct}
columns validate on Stata's source scale, including Stata's 1960 epoch and
millisecond datetime unit, while continuing to expose ordinary R temporal
values. Base \code{ifelse()} takes attributes from its condition and therefore
returns a bare vector. Pass that result to a storage constructor to declare and
compact it again. Re-encoding temporarily materializes doubles, so the memory
saving applies after construction and across columns held in memory.
}

\section{Labels and missing-code helpers}{
Reading DTA files and working with their labels does not require haven or
labelled. Use \code{var_label()}, \code{val_labels()}, \code{dataset_label()},
\code{set_var_label()}, \code{set_var_labels()}, and \code{set_val_labels()} to
inspect or change package-owned Stata metadata without materializing compact
numeric columns or dropping unrelated attributes. For example:
\preformatted{data <- data.frame(status = c(1, 2, 1))
var_label(data$status)
var_label(data$status) <- "Interview status"
val_labels(data$status)
val_labels(data$status) <- c(Complete = 1, Refused = 2)
}

The package-owned missing-code helpers also work without haven:
\preformatted{missing_tag(data$status)
is_tagged_missing(data$status, "a")
data$status[1] <- tagged_missing("a")
}
Use \code{factor_from_labels()} for an intentional one-way conversion to an
ordinary factor. Haven can be installed separately to write older DTA
releases or read other statistical formats.
See the
\href{https://github.com/jbearak/dta-parser/blob/main/docs/r-label-metadata.md}{R label metadata guide}
for bulk setters, Stata 19 limits, and the version-specific comparison with
labelled 2.16.0.
}
