args fixture_dir
clear all
set more off
timer clear
forvalues i = 1/7 {
    use "`fixture_dir'/master.dta", clear
    timer on `i'
    quietly merge 1:m caseid using "`fixture_dir'/using.dta"
    timer off `i'
}
timer list
exit
