version 18.0
set more off
use in 1/1 using "input.dta", clear
file open aww_probe using "open-ok.txt", write replace text
file write aww_probe "ok" _n
file close aww_probe
exit, clear
