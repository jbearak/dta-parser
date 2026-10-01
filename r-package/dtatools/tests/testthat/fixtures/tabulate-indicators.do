set more off
set linesize 120
clear
input double x
-1e20
-123456789
-12345.6789
-1
-.00000001
0
.00000001
.0001
.001234567
.123456789
1.23456789
1234.56789
12345.6789
123456.789
1234567.89
12345678.9
123456789
1e20
.
.a
end
tabulate x, missing generate(z)
forvalues i=1/20 {
local l : variable label z`i'
display "`l'"
}
clear
input x
1
2
3
.
.a
end
label define xx 1 "One" 3 "" .a "Refused"
label values x xx
tabulate x, missing nolabel generate(z)
forvalues i=1/5 {
local l : variable label z`i'
display "`l'"
}
tabulate x, missing generate(u)
forvalues i=1/5 {
local l : variable label u`i'
display "`l'"
}
