args fixture_dir
clear all
set more off
timer clear
forvalues i = 1/7 {
    use "`fixture_dir'/using.dta", clear
    timer on `i'
    quietly merge m:1 caseid using "`fixture_dir'/master.dta"
    timer off `i'
}
timer list
exit
