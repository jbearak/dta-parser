version 18
set more off

args source candidate mutation
quietly use "`source'", clear

if "`mutation'" == "dimensions" quietly drop in 1
else if "`mutation'" == "variable-names" rename price cost
else if "`mutation'" == "storage-type" recast double price
else if "`mutation'" == "display-format" format price %12.0g
else if "`mutation'" == "dataset-label" label data "changed"
else if "`mutation'" == "variable-label" label variable price "changed"
else if "`mutation'" == "value-label-assignment" label values foreign .
else if "`mutation'" == "value-label-definitions" {
    label define origin 0 "changed", modify
}
else if "`mutation'" == "dataset-notes" notes: changed
else if "`mutation'" == "stored-values" replace price = price + 1 in 1
else exit 198

quietly save "`candidate'", replace
exit 0
