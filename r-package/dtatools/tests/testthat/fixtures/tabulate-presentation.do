set more off
set linesize 80
sysuse auto, clear
tabulate foreign, nofreq
tabulate foreign rep78, nofreq
tabulate foreign, plot
tabulate foreign, plot nofreq
tabulate rep78, plot
tabulate foreign rep78, row nokey
tabulate foreign rep78, key
tabulate foreign rep78, cchi2 clrchi2
tabulate foreign rep78, cchi2 clrchi2 nofreq
tabulate rep78 foreign, expected cchi2 clrchi2 row column cell
generate double aw = _n / 3
tabulate rep78 [aw=aw]
tabulate rep78 [iw=aw]
tabulate rep78 foreign [aw=aw], expected row column cell
tabulate rep78 foreign [iw=aw], expected row column cell
expand 10
tabulate foreign, plot
label define originlong 0 "Domestic car made in the United States of America" 1 "Foreign car"
label values foreign originlong
tabulate foreign, plot
clear
input double(x y w)
1 1 1.5
1 2 2.25
2 1 .25
2 2 3
3 1 1
3 2 4
end
tabulate x [iw=w]
tabulate x y [iw=w], expected row column cell
tabulate x [aw=w]
tabulate x y [aw=w], expected
set linesize 120
tabulate y x, wrap
clear
input double(x w)
1 1.23456789123
2 21.8257197696
3 21.825719769
4 2.330902111
5 1.23456789012345
6 123456789.12345
7 .000000123456789
8 1234567890123456
end
tabulate x [iw=w]
clear
input double(x y w s)
1 1 1.5 1
2 1 2.5 0
3 2 .5 .
4 2 .5 0
end
tabulate x [iw=w], plot
tabulate x y, subpop(s) row column cell expected cchi2 clrchi2 all
replace s = 0
tabulate x, subpop(s)
tabulate x, subpop(s) plot
tabulate x y, subpop(s) row column cell expected cchi2 clrchi2 all
