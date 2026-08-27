set maxvar 120000
capture noisily use "output.dta", clear
local status = cond(_rc == 0, "stata-pass", "stata-error")
local rows = cond(_rc == 0, _N, .)
local columns = cond(_rc == 0, c(k), .)
file open result using "stata-result.tsv", write text replace
file write result "`status'" _tab "`rows'" _tab "`columns'" _n
file close result
exit 0
