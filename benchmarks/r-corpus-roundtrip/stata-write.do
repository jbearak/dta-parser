set maxvar 120000
use "input.dta", clear
timer clear 1
timer on 1
capture noisily save "stata-output.dta", replace
local status = cond(_rc == 0, "ok", "error")
timer off 1
quietly timer list 1
local elapsed = r(t1)
local bytes = .
capture confirm file "stata-output.dta"
if _rc == 0 {
    quietly checksum "stata-output.dta"
    local bytes = r(filelen)
}
file open result using "stata-write-result.tsv", write text replace
file write result "`status'" _tab "`elapsed'" _tab "`bytes'" _n
file close result
exit 0
