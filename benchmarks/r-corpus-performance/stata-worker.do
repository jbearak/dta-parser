version 18.0
set more off
set maxvar 32767

timer clear 1
timer on 1
capture confirm file "projection.txt"
if _rc == 0 {
    file open projection_file using "projection.txt", read text
    file read projection_file projection
    file close projection_file
    capture quietly use `projection' using "input.dta", clear
    local status = _rc
}
else {
    capture quietly use "input.dta", clear
    local status = _rc
}
timer off 1
quietly timer list 1
local elapsed = r(t1)

file open result using "result.tsv", write replace text
if `status' == 0 {
    file write result "ok" _tab %21.9f (`elapsed') _tab %21.0f (_N) _tab %21.0f (c(k)) _n
}
else {
    file write result "error" _tab %21.9f (`elapsed') _tab "NA" _tab "NA" _n
}
file close result
exit, clear
