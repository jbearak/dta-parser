* Native Stata oracle for association measures and stored results.
* Regenerate, never edit tabulate-association.log:
* cd r-package/dtatools/tests/testthat/fixtures
* stata -q -b do tabulate-association.do
set more off
set linesize 120
tabi 30 18 \ 38 14, all exact nolog
return list
tabi 20 10 2 \ 16 12 4 \ 10 16 6, all exact nolog
return list
tabi 0 8 \ 5 0, all exact nolog
return list
tabi 1 1 \ 1 1, all exact nolog
return list
tabi 1 2 \ 2 4, exact nolog
return list
tabi 3 1 \ 9 3, exact nolog
return list
tabi 30 18 \ 38 14, V
return list
tabi 30 18 \ 38 14, gamma
return list
tabi 30 18 \ 38 14, taub
return list
tabi 30 18 \ 38 14, all nochi2 nogamma notaub noV
return list
tabi 30 18 \ 38 14, all rowsort colsort
return list
tabi 1 0 0 \ 0 1 0 \ 0 0 1, all exact nolog
return list
tabi 30 18 38 \ 13 7 22, all exact nolog
return list
tabi 1 2 0 1 3 \ 4 1 2 0 1 \ 0 2 3 2 1 \ 1 0 2 1 4, all exact nolog
return list
tabi 1 0 0 \ 2 0 0 \ 0 0 5, all exact nolog
return list
tabi 300000 180000 \ 380000 140000, all
return list
tabi 2 2 \ 0 0, all exact nolog
return list
tabi 1 0 \ 0 0, all exact nolog
return list
tabi 1 0 \ 0 1, all exact nolog
return list
tabi 2 1 0 \ 0 3 2 \ 0 0 5, all exact(2) nolog
return list
