* Records what Stata's `tabulate` prints for the one-way and two-way forms
* dtatools::tab() reproduces, so the R printer is compared against a
* measurement rather than against recollection. Run with:
*
*     cd r-package/dtatools/tests/testthat/fixtures
*     stata -q -b do tabulate.do
*
* and compare the result against tabulate.log beside it, which was produced
* by Stata 19 MP. test-tab-stata-parity.R reads that log: every `tabulate`
* command below has an R counterpart there, in the same order, and the
* printed lines must match exactly. The cases where tab() intentionally
* prints differently are in docs/r-tab-stata-parity.md, not here.
set more off
sysuse auto, clear

* One-way: frequency, percent, cumulative percent, total; missing; sort;
* nolabel; string variables sized by their storage width.
tabulate rep78
tabulate rep78, missing
tabulate foreign
tabulate foreign, nolabel
tabulate rep78, sort
tabulate make if _n <= 3
tabulate mpg if mpg >= 40

* Two-way: totals, percentages, expected frequencies, nofreq, missing.
tabulate rep78 foreign
tabulate rep78 foreign, missing
tabulate rep78 foreign, nolabel
tabulate rep78 foreign, row
tabulate rep78 foreign, column
tabulate rep78 foreign, cell
tabulate rep78 foreign, row column cell
tabulate rep78 foreign, expected
tabulate rep78 foreign, expected nofreq
tabulate rep78 foreign, nofreq row
tabulate rep78 foreign, cell nofreq
tabulate rep78 foreign, row column nofreq
tabulate rep78 foreign, missing row
tabulate rep78 foreign, missing expected
tabulate rep78 foreign, nolabel missing cell
tabulate foreign rep78
tabulate foreign rep78, column
tabulate make foreign if _n <= 3
tabulate rep78 foreign if _n <= 3

* Extended missing values keep Stata's order after the observed values.
gen r2 = rep78
replace r2 = .a in 1/2
replace r2 = .b in 3
tabulate r2
tabulate r2, missing
tabulate r2 foreign, missing
tabulate r2 foreign, missing expected nofreq

* Sort: descending frequency, ties in value order, missing sorted with the rest.
gen t = 1 in 1/2
replace t = 2 in 3/4
replace t = 3 in 5
replace t = 0 in 6/7
tabulate t, sort
tabulate t, sort missing
label define tl 0 "Zero" 1 "One" 2 "Two" 3 "Three"
label values t tl
tabulate t, sort
gen e = .a in 1/3
replace e = .b in 4
replace e = 1 in 5/9
tabulate e, missing
tabulate e, missing sort

* The empty string is a string missing: excluded, or one blank category.
gen str s = make
replace s = "" in 1/3
tabulate s if _n <= 6
tabulate s if _n <= 6, missing
gen str1 u = "b" in 1/2
replace u = "a" in 3/4
replace u = "c" in 5
tabulate u, sort
tabulate u if _n <= 6, missing
tabulate u foreign if _n <= 6
tabulate u foreign if _n <= 6, missing

* Percent rounding on thirds and sevenths.
gen q = 1 in 1/1
replace q = 2 in 2/3
tabulate q
gen r = _n in 1/7
tabulate r

* No observations, and a variable that is entirely missing.
tabulate rep78 if mpg > 1000
gen z = .
tabulate z
tabulate z, missing
tabulate z foreign

* Header layout: long labels wrap by word, or are cut, and long level
* labels widen the stub up to its limit; column levels are cut to nine.
label define rp 1 "Very poor rating text long" 2 "Poor" 3 "Average" 4 "Good" 5 "Excellent"
label values rep78 rp
tabulate rep78
tabulate rep78 foreign
label define lg 1 "This is a label that is much longer than twenty one chars" 2 "Poor"
label values rep78 lg
tabulate rep78 if rep78 <= 2
tabulate rep78 foreign if rep78 <= 2
label values rep78 repair
label define fo 0 "Domestic car" 1 "Foreign car built abroad"
label values foreign fo
tabulate rep78 foreign
tabulate foreign rep78
label values foreign origin
label var rep78 "Repairrecordfor1978automobiles"
tabulate rep78 if _n <= 20
tabulate rep78 foreign if _n <= 20
label var foreign "Originofthecarlongword"
tabulate rep78 foreign if _n <= 20
label var rep78 "Repair record 1978"
label var foreign "Car origin"
gen c11 = foreign
label var c11 "abcdefghijk"
tabulate rep78 c11 if _n <= 3
gen c10 = foreign
label var c10 "abcdefghij"
label define ten 0 "Domestic10" 1 "ForeignXYZ"
label values c10 ten
tabulate rep78 c10
gen g = mod(_n, 3)
gen h = mod(_n, 2)
tabulate g h, row
gen str3 fo3 = substr(cond(foreign, "Foreign", "Domestic"), 1, 3)
tabulate rep78 fo3

* Large counts print with thousands separators.
expand 2000
tabulate foreign
tabulate g h
