* Run from repository root with Stata 18 or newer:
* /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp -b do conformance/stata/egen/egen.do
version 18.0
clear all
set more off
capture log close _all
log using conformance/stata/egen/egen.log, text replace
display "Stata " c(stata_version) " " c(flavor) "; revision " c(born_date) "; " c(os) " " c(machine_type)
input byte obs byte g double x double y byte selected str4 s
1 2 3 . 1 "b"
2 1 . .a 1 "a"
3 2 9 2 0 "b"
4 1 .a . 0 "a"
5 3 16777217 -1 1 "é"
6 3 2 . 1 "é"
7 . 4 5 1 ""
8 .a 8 . 1 "z"
9 2 .z 7 1 "a"
end
egen double mean_x = mean(x), by(g)
egen double min_x = min(x), by(g)
egen double max_x = max(x), by(g)
egen double total_x = total(x), by(g)
egen double total_missing = total(x), by(g) missing
egen double row_max = rowmax(x y)
egen double row_total = rowtotal(x y)
egen double row_total_missing = rowtotal(x y), missing
egen double selected_total = total(x) if selected, by(g)
egen double observed = total(!missing(x)), by(g)
egen byte any_observed = max(x < .), by(g)
egen group_id = group(g s)
egen group_missing = group(g s), missing
egen tag = tag(g s)
egen tag_missing = tag(g s), missing
egen tag_selected = tag(g s) if selected
egen group_label = group(g s), label lname(group_codes) autotype
egen rounded_total = total(x), by(g)
bysort g: egen long ordered_min = min(x)
sort obs
describe
label list group_codes
notes group_label
format x y mean_x min_x max_x total_x total_missing row_max row_total row_total_missing selected_total rounded_total %24.17g
export delimited using r-package/dtatools/inst/extdata/egen_stata18.csv, replace datafmt nolabel
clear
input double number str12 text byte category
1.23456789 "éclair" 1
123456789 "東京abc" 2
-0.0000123456789 "🙂hello" 3
end
label define category_labels 1 "élève" 2 "東京語" 3 "🙂🙂abc"
label values category category_labels
egen code = group(number text category), label lname(unicode_codes) truncate(3)
decode code, gen(label_text)
label list unicode_codes
notes code
format number %24.17g
export delimited using r-package/dtatools/inst/extdata/egen_labels_stata18.csv, replace datafmt nolabel
clear
input byte case double a double b double c
1 1e16 1 -1e16
2 1e16 -1e16 1
3 1 1e16 -1e16
4 -1e16 1 1e16
5 1e20 1000 -1e20
6 1e-20 1 -1
7 1 1e-20 -1
8 1e16 3 -1e16
end
egen double row_total = rowtotal(a b c)
rename (a b c) (x1 x2 x3)
reshape long x, i(case) j(position)
egen double total = total(x), by(case)
egen double mean = mean(x), by(case)
sort case position
format x row_total total mean %26.17e
export delimited using r-package/dtatools/inst/extdata/egen_precision_stata18.csv, replace datafmt nolabel
clear
input double number
1e20
-1e20
12345678901234568
123456789012345680
1234567890123456800
1e-8
1e-20
1.234567890123456
-1.234567890123456
0.9999999999
1e21
-1e21
1e-7
1e-6
-1e-8
1234560.1
12345678.9
9999999.9
999999.99
99999999999999
999999999999999
9999999999999999
1.0000000001
0.00000099999999
1e14
1e15
-1e15
123456789012345
1234567890123456
-123456789012345
-1234567890123456
9.9e-8
1234567.8
12345678.1
-1234560.1
-1234567.8
-12345678.1
0.00001
0.0001
0.00000123456789
0.0000123456789
0.000009999999
-0.000009999999
-0.00001
-0.0001
1e100
-1e100
1e300
-1e300
1e-100
-1e-100
1e-300
-1e-300
end
egen code = group(number), label lname(precision_codes)
decode code, gen(label_text)
label list precision_codes
format number %26.17e
export delimited using r-package/dtatools/inst/extdata/egen_number_labels_stata18.csv, replace datafmt nolabel
save r-package/dtatools/inst/extdata/egen_number_labels_stata18.dta, replace
clear
set obs 1
gen 東京東京東京東京東京東京東京東 = 1
gen 京都京都京都京都京都京都京都京 = 1
gen 大阪大阪大阪大阪大阪大阪阪大 = 1
egen group_unicode = group(東京東京東京東京東京東京東京東 京都京都京都京都京都京都京都京 大阪大阪大阪大阪大阪大阪阪大)
egen tag_unicode = tag(東京東京東京東京東京東京東京東 京都京都京都京都京都京都京都京 大阪大阪大阪大阪大阪大阪阪大)
describe group_unicode tag_unicode
notes group_unicode
notes tag_unicode
gen 東京東京東京東京東京東京東京東京東京東京東京東京東京 = 1
egen tag_byte_width = tag(東京東京東京東京東京東京東京東京東京東京東京東京東京)
gen aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = 1
gen bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb = 1
gen ccccccccccccccccccccccccccccccc = 1
egen tag_ascii_long = tag(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ccccccccccccccccccccccccccccccc)
describe tag_byte_width tag_ascii_long
notes tag_byte_width
notes tag_ascii_long
save r-package/dtatools/inst/extdata/egen_unicode_names_stata18.dta, replace
log close
