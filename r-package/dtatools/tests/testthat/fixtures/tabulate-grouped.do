set more off
set linesize 80
clear
input x g str12 s
1 0 ""
2 0 ""
1 1 "alpha beta"
2 1 "alpha beta"
1 . "quoted"
2 . "quoted"
1 .a "z"
2 .a "z"
end
label define gg 0 "Domestic" 1 "Foreign" .a "Refused"
label values g gg
bysort g: tabulate x
bysort g: tabulate x, nolabel
bysort s: tabulate x
bysort g s: tabulate x
generate double day = 21915 + floor((_n-1)/2)
format day %td
bysort day: tabulate x
generate double stamp = 1893456000000 + 1000 * floor((_n-1)/2)
format stamp %tc
bysort stamp: tabulate x
format day %tdMonth_dd,_CCYY
bysort day: tabulate x
set linesize 120
label define gg 0 "This group label is much longer than the column output and would exceed a table", modify
label values g gg
bysort g: tabulate x
clear
input double(x g)
1 1.234567891
2 1.234567891
1 12345678.9
2 12345678.9
end
format g %18.10f
bysort g: tabulate x
