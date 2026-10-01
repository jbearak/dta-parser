* Stata oracle for selection, weights, subpop, and category presentation.
clear
set more off
input double x y w s
1 1 .5 1
1 2 2 0
2 1 3 .
2 2 0 0
3 . 4 1
. 1 1 1
end
tabulate x [aw=w]
tabulate x y [aw=w]
tabulate x [iw=w]
tabulate x y [iw=w]
tabulate x, subpop(s)
tabulate x [aw=w], subpop(s)
tabulate x if _n<=4 in 2/5
replace w=round(w*2)
tabulate x [fw=w], sort matrow(r) matcell(c) generate(z)
matrix list r
matrix list c
list z*
tabulate x y, rowsort colsort row
label define lab 1 "Same" 2 "Same" 3 "Other"
label values x lab
tabulate x
tabulate x y
label values x
replace x=1.23456789 in 1/2
replace x=2.34567891 in 3/5
tabulate x
format x %9.2f
tabulate x
format x %td
tabulate x
