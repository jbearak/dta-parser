* Run from the repository root with Stata 18 or newer:
* /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp -b do conformance/stata/summarize/summarize.do
* The CSV files contain native summarize results, not R-derived expectations.
version 18.0
clear all
set more off
set linesize 80
capture log close _all
log using /tmp/dtatools-summarize-oracle.log, text replace
input str32 case double x double w byte selected
"ordinary" -3 1 1
"ordinary" 0 2 1
"ordinary" 1 1 1
"ordinary" 2 3 1
"ordinary" 9 2 1
"ordinary" 13 1 1
"ordinary" . 1 1
"empty" 1 1 0
"singleton" 7 3 1
"constant" 5 1 1
"constant" 5 2 1
"constant" 5 3 1
"mixed_missing" . 1 1
"mixed_missing" .a 2 1
"mixed_missing" -4 2 1
"mixed_missing" .z 1 1
"mixed_missing" 8 3 1
"all_missing" . 1 1
"all_missing" .a 2 1
"all_missing" .z 3 1
"zero_weights" -10 0 1
"zero_weights" 1 1 1
"zero_weights" 4 2 1
"zero_weights" 100 0 1
"all_zero_weights" 1 0 1
"all_zero_weights" 2 0 1
"missing_weights" 1 . 1
"missing_weights" 2 .a 1
"missing_weights" 3 2 1
"missing_weights" 6 1 1
"missing_weights" 10 .z 1
"fractional_weights" 1 .25 1
"fractional_weights" 2 .25 1
"fractional_weights" 10 .5 1
"small_total_weights" 1 .1 1
"small_total_weights" 2 .2 1
"small_total_weights" 10 .2 1
"negative_weights" 1 -1 1
"negative_weights" 2 2 1
"negative_weights" 10 3 1
"negative_total_weights" 1 -3 1
"negative_total_weights" 2 1 1
"negative_total_weights" 10 1 1
"zero_total_weights" 1 -2 1
"zero_total_weights" 2 1 1
"zero_total_weights" 10 1 1
"weighted_ties" 0 2 1
"weighted_ties" 0 1 1
"weighted_ties" 1 3 1
"weighted_ties" 2 2 1
"weighted_ties" 2 2 1
"quantile_boundaries" 1 1 1
"quantile_boundaries" 2 1 1
"quantile_boundaries" 3 1 1
"quantile_boundaries" 4 1 1
"quantile_boundaries" 5 1 1
"quantile_boundaries" 6 1 1
"quantile_boundaries" 7 1 1
"quantile_boundaries" 8 1 1
"quantile_boundaries" 9 1 1
"quantile_boundaries" 10 1 1
"unequal_weights" -3 1 1
"unequal_weights" 1 49 1
"unequal_weights" 4 49 1
"unequal_weights" 100 1 1
"large_weights" 1 1000000000 1
"large_weights" 2 2000000000 1
"large_weights" 10 3000000000 1
"cancellation" 1e16 1 1
"cancellation" 1 1 1
"cancellation" -1e16 1 1
"large_location" 1000000000000 1 1
"large_location" 1000000000001 2 1
"large_location" 1000000000002 3 1
"large_location" 1000000000004 4 1
"excluded_negative" 1 -1 0
"excluded_negative" 2 2 1
"excluded_negative" 10 3 1
"excluded_fractional" 1 .5 0
"excluded_fractional" 2 2 1
"excluded_fractional" 10 3 1
"missing_x_negative" . -1 1
"missing_x_negative" 2 2 1
"missing_x_negative" 10 3 1
"missing_x_fractional" . .5 1
"missing_x_fractional" 2 2 1
"missing_x_fractional" 10 3 1
"negative_zero_sum" 1 -1 1
"negative_zero_sum" 2 1 1
"negative_singleton" 3 -1 1
"overflow_variance" 1e300 1 1
"overflow_variance" 2e300 1 1
"underflow_variance" 1e-200 1 1
"underflow_variance" 2e-200 1 1
"overflow_sum" 8e307 1 1
"overflow_sum" 8e307 1 1
"overflow_sum" 8e307 1 1
"intermediate_overflow" 8e307 1 1
"intermediate_overflow" 8e307 1 1
"intermediate_overflow" 8e307 1 1
"intermediate_overflow" -8e307 1 1
"intermediate_overflow" -8e307 1 1
"overflow_fourth_moment" 1e100 1 1
"overflow_fourth_moment" 2e100 1 1
"underflow_fourth_moment" 1e-100 1 1
"underflow_fourth_moment" 2e-100 1 1
"overflow_asymmetric_moments" 1e100 1 1
"overflow_asymmetric_moments" 2e100 1 1
"overflow_asymmetric_moments" 4e100 1 1
"underflow_asymmetric_moments" 1e-100 1 1
"underflow_asymmetric_moments" 2e-100 1 1
"underflow_asymmetric_moments" 4e-100 1 1
"rounded_weight_boundary" 1 1e16 1
"rounded_weight_boundary" 2 1 1
"rounded_weight_boundary" 3 1e16 1
end
format x w %26.17e
export delimited using r-package/dtatools/inst/extdata/summarize_stata18_input.csv, replace datafmt nolabel
local scalars N sum_w sum mean Var sd min max skewness kurtosis p1 p5 p10 p25 p50 p75 p90 p95 p99
tempfile results
tempname output
postfile `output' str32 case str8 weight str8 mode int rc str160 returned double (`scalars') using `results', replace
quietly levelsof case, local(cases)
foreach sample of local cases {
    foreach weight in none aweight fweight iweight {
        local weight_clause
        if "`weight'" != "none" local weight_clause "[`weight'=w]"
        foreach mode in default detail meanonly {
            local options
            if "`mode'" != "default" local options ", `mode'"
            capture quietly summarize x if case == "`sample'" & selected `weight_clause' `options'
            local rc = _rc
            local returned : r(scalars)
            local values
            foreach scalar of local scalars {
                if `rc' == 0 local values "`values' (r(`scalar'))"
                else local values "`values' (.)"
            }
            if `rc' != 0 local returned
            post `output' ("`sample'") ("`weight'") ("`mode'") (`rc') ("`returned'") `values'
        }
    }
}
postclose `output'
use `results', clear
format `scalars' %26.17e
export delimited using r-package/dtatools/inst/extdata/summarize_stata18.csv, replace datafmt nolabel
log close
