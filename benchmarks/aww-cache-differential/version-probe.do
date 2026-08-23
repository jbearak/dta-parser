set more off
local stata_version = c(stata_version)
file open out using "stata-version.txt", write replace
file write out "`stata_version'" _n
file close out
exit, clear
