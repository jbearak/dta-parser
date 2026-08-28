version 18.0
clear all
set more off
set maxvar 32767

args input present_path union_path repetitions_arg output
local repetitions = real("`repetitions_arg'")

file open present_file using "`present_path'", read text
file read present_file present
file close present_file
file open union_file using "`union_path'", read text
file read union_file union
file close union_file
local expected : word count `present'

quietly use `present' using "`input'", clear
clear

file open results using "`output'", write text replace
forvalues iteration = 1/`repetitions' {
    timer clear 1
    timer on 1
    quietly use "`input'", clear
    local selected
    foreach candidate of local union {
        capture confirm variable `candidate'
        if _rc == 0 local selected `selected' `candidate'
    }
    quietly keep `selected'
    timer off 1
    quietly timer list 1
    local elapsed = r(t1)
    if c(k) != `expected' {
        file close results
        error 9
    }
    file write results "stata-load-inspect-keep" _tab %9.0f (`iteration') _tab %21.9f (`elapsed') _tab %21.0f (_N) _tab %21.0f (c(k)) _n

    timer clear 1
    timer on 1
    quietly use `present' using "`input'", clear
    timer off 1
    quietly timer list 1
    local elapsed = r(t1)
    if c(k) != `expected' {
        file close results
        error 9
    }
    file write results "stata-use-present" _tab %9.0f (`iteration') _tab %21.9f (`elapsed') _tab %21.0f (_N) _tab %21.0f (c(k)) _n
}
file close results
exit, clear
