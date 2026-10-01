# Stata summarize in R

`dtatools::summarize()`, `dtatools::summarise()`, and `dtatools::summ()` are
the same function. They calculate each variable separately, using Stata's
missing-value, weighting, percentile, and moment conventions.

| Stata | R |
| --- | --- |
| `summarize` | `summarize(data)` |
| `summarize x y` | `summarize(data, x, y)` |
| `summarize x-z` | `summarize(data, "x-z")` or `summarize(data, x:z)` |
| `summarize x if eligible` | `summarize(data, x, where = eligible)` |
| `summarize x in 2/10` | `summarize(data, x, rows = 2:10)` |
| `by group: summarize x` | `summarize(data, x, by = group)` |
| `summarize x [aw=w]` | `summarize(data, x, weights = w, weight = "aweight")` |
| `summarize x [fw=w]` | `summarize(data, x, weights = w, weight = "fweight")` |
| `summarize x [iw=w]` | `summarize(data, x, weights = w, weight = "iweight")` |
| `summarize x, detail` | `summarize(data, x, detail = TRUE)` |
| `summarize x, meanonly` | `summarize(data, x, meanonly = TRUE)` |
| `summarize i.group##c.x` | `summarize(data, "i.group##c.x")` |
| `summarize L(1/3).x` after `tsset time` | `summarize(data, "L(1/3).x", time = "time")` |
| `summarize L.x` after `xtset id time` | `summarize(data, "L.x", time = "time", panel = "id")` |

The manual page `?summarize` documents display options, return values, and
calendar formats. Grouping follows the package's existing `by` convention,
visiting groups in order of first appearance without sorting or modifying
the input. Time-series operators match time values, including gaps, rather
than relying on the input's row order. Their source observations remain
available even when `where` or `rows` excludes those observations from the
summary sample.

`result$statistics` retains all evaluated variables and groups, including
factor rows hidden by display options. `result$r` contains Stata's stored
scalars for the last evaluated variable. This distinction matters when the
last variable is a hidden factor base or a string. `as.data.frame(result)`
combines statistics and group keys for further R calculations.

Stata's surrounding command environment is expressed through R calls.
Collect results with `as.data.frame()`, and repeat calls over samples or
windows for the roles of `statsby`, `rolling`, or resampling prefixes.
The function does not parse Stata prefix programs. Use
`dplyr::summarise()` explicitly for dplyr aggregation when both packages
are attached.

## Verification

[Stata's command manual](https://www.stata.com/manuals/rsummarize.pdf)
defines the command options and statistical formulas. The checked-in
[generator](../conformance/stata/summarize/summarize.do) records 420 native
Stata 18 runs across 35 datasets, four weight settings, and three command
modes. Tests compare error acceptance, stored scalar presence, and values.
Nonzero values use relative comparisons so underflow cases cannot pass as
zero through an absolute tolerance.

The fixtures cover missing values and weights, zero and negative weights,
frequency-weight validation, percentile boundaries, empty and constant
samples, single observations, cancellation, and moment overflow and
underflow. Separate tests check factor expansion, hidden bases, interactions,
grouped samples, time operators, printed tables, formats, aliases, input
containers, and integration with existing dplyr methods.

## Ties with extreme weights

Stata 18's weighted percentiles can depend on `set sortseed` when tied
values have weights with very different magnitudes. For example, the
following native commands give `p25 = 2` with seed 1 and `p25 = 1.5` with
seed 2:

```stata
clear
input double(x w)
1 1
2 1e16
1 1e16
3 1e16
4 2
4 1e16
2 2
end
forvalues seed = 1/2 {
    set sortseed `seed'
    quietly summarize x [aw=w], detail
    display r(p25)
}
```

The R implementation uses a stable value order and returns deterministic
percentiles. It does not reproduce Stata's random tie ordering, so these
extreme-weight cases can differ from an individual native run. Native
regressions use cases whose results do not depend on the sort seed.

Native weighted percentiles also use a boundary tolerance of `1e-5`
percentage points. The implementation checks the selected weight interval
before applying that tolerance, so a percentile inside a small positive
weight retains that observation. At the tolerance cutoff itself, the final
floating-point rounding can differ from Stata's compiled calculation.
Probes with weights around `1e-200` and `1e200` found such differences when
the cumulative percentage was within one double-precision step of the
cutoff. Values safely inside or outside the tolerance match the native
boundary rule.

Plain-column grouped summaries reuse their variable expansion. Factor and
time-series varlists expand against each group's sample while retaining the
full dataset for lag and lead lookup. Those varlists can take more time
when the number of groups is large.
