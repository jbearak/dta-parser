* Native Stata oracle for tab1, tab2, and immediate tabulations.
* Regenerate from this directory: stata -q -b do tabulate-multiple.do
set more off
set linesize 80
clear
input x y z
1 1 1
1 2 2
2 1 3
2 2 1
3 . 2
. 3 2
end
tab1 x y z, missing
tab1 x y if z > 1, missing sort
tab2 x y z, firstonly chi2
tab2 x y z, missing row
tabi 30 18 \ 38 14
tabi 30 18 \ 38 14, row
tabi 1 2 3 \ 4 5 6
tabi 2 2 \ 0 0
tabi 2 1 0 \ 0 3 2 \ 0 0 5, all exact nolog rowsort colsort
generate g = 1 + (_n > 3)
bysort g: tab1 x y, missing
