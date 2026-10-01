* Stata 18 tabulate, summarize() oracle. Run from this directory:
* /Applications/Stata/StataMP.app/Contents/MacOS/stata-mp -bq do tabulate-summary.do
set more off
set linesize 80
clear
input g h double y double w
1 1 10 1
1 1 20 2
1 2 40 3
2 1 50 4
2 2 . 2
3 2 . 1
. 1 60 1
end
label variable y "Outcome measure"
tabulate g, summarize(y)
tabulate g h, summarize(y)
tabulate g [fw=w], summarize(y)
tabulate g [aw=w], summarize(y)
tabulate g h [fw=w], summarize(y)
tabulate g h [aw=w], summarize(y)
tabulate g, summarize(y) means
tabulate g, summarize(y) standard
tabulate g, summarize(y) freq obs
tabulate g, summarize(y) nofreq
tabulate g h, summarize(y) obs
tabulate g h, summarize(y) missing
tabulate g [fw=w], summarize(y) means
tabulate g [aw=w], summarize(y) freq
tabulate g h, summarize(y) means standard
tabulate g h, summarize(y) nomeans nostandard nofreq
tabulate g h if g == 3, summarize(y)
label variable g "A very long label for this factor"
label define g 1 "ABCDEFGHIJKLMNOQRSTUVWXYZABCDEFGHIJKLMNOPQRST" 2 "B"
label values g g
tabulate g, summarize(y)
tabulate g h, summarize(y)
clear
input str45 g h double y
"ABCDEFGHIJKLMNOQRSTUVWXYZABCDEFGHIJKLMNOPQRST" 1 10
"B" 2 20
end
label variable g "A long grouping label"
label variable y "A very long outcome label with a trailing word"
tabulate g, summarize(y)
tabulate g, summarize(y) means
tabulate g h, summarize(y)
tabulate g h, summarize(y) means
clear
set obs 12
gen g = 1
gen h = _n
gen y = _n
tabulate g h, summarize(y) means
set linesize 120
tabulate g h, summarize(y) means
set linesize 255
tabulate g h, summarize(y) means wrap
set linesize 80
clear
input g str20 h double y
1 "ABCDEFGHIJKLMNO" 10
1 "Short" 20
2 "B" 30
end
label variable h "A very long column heading this is"
tabulate g h, summarize(y)
clear
set obs 2
gen g = 1
gen double y = 1e100
tabulate g, summarize(y)
replace y = 1e-100
tabulate g, summarize(y)
clear
input g h double y
1 1 10
2 1 20
end
label define duplicate 1 "Same" 2 "Same"
label values g duplicate
tabulate g, summarize(y)
tabulate g h, summarize(y)
label values g
replace g = g / 10
format g %9.2f
tabulate g, summarize(y)
replace g = td(01jan2020) + _n - 1
format g %td
tabulate g, summarize(y)
