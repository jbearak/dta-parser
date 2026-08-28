args fixture_dir
clear all
set more off
capture log close benchmark
log using "`fixture_dir'/stata-m1.log", text replace name(benchmark)
timer clear
forvalues i = 1/7 {
    use "`fixture_dir'/using.dta", clear
    timer on `i'
    quietly merge m:1 caseid using "`fixture_dir'/master.dta"
    timer off `i'
    assert _N == 440044
    isid caseid bidx
    quietly count if _merge == 1
    assert r(N) == 0
    quietly count if _merge == 2
    assert r(N) == 80000
    quietly count if _merge == 3
    assert r(N) == 360044
}
timer list
log close benchmark
exit
