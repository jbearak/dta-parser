version 18.0
clear all
set more off
set maxvar 32767

args output rows_arg columns_arg result
local rows = real("`rows_arg'")
local columns = real("`columns_arg'")
set obs `rows'

forvalues index = 1/`columns' {
    local suffix : display %05.0f `index'
    local name = "v`suffix'"
    local kind = mod(`index', 10)
    if `kind' == 0 {
        quietly generate str12 `name' = "S" + string(mod(_n + `index', 100000), "%010.0f")
    }
    else if inlist(`kind', 1, 2) {
        quietly generate byte `name' = mod(_n + `index', 100)
    }
    else if inlist(`kind', 3, 4) {
        quietly generate int `name' = mod(_n + `index', 30000)
    }
    else if inlist(`kind', 5, 6, 7) {
        quietly generate float `name' = mod(_n, 10000) / 17 + `index'
    }
    else {
        quietly generate double `name' = _n / 19 + `index'
    }
}

quietly save "`output'", replace
quietly checksum "`output'"
file open result_file using "`result'", write text replace
file write result_file "ok" _tab %21.0f (_N) _tab %21.0f (c(k)) _tab %21.0f (r(filelen)) _n
file close result_file
exit, clear
