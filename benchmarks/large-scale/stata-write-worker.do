version 18.0
set more off
set maxvar 120000

capture noisily use "input.dta", clear
if _rc != 0 {
    file open result using "result.tsv", write text replace
    file write result "stata" _tab "error" _tab "NA" _tab "NA" _tab "NA" _tab "NA" _n
    file close result
    exit, clear
}

local rows = _N
local columns = c(k)
timer clear 1
timer on 1
capture noisily save "output.dta", replace
local status = cond(_rc == 0, "ok", "error")
timer off 1
quietly timer list 1
local elapsed = r(t1)
local bytes = .
capture confirm file "output.dta"
if _rc == 0 {
    quietly checksum "output.dta"
    local bytes = r(filelen)
}
file open result using "result.tsv", write text replace
file write result "stata" _tab "`status'" _tab %21.9f (`elapsed') _tab %21.0f (`rows') _tab %21.0f (`columns') _tab %21.0f (`bytes') _n
file close result
exit, clear
