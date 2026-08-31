version 18
set more off
set maxvar 120000
set processors 1

args source candidate output_kind source_release
global DTATOOLS_OUTPUT_KIND "`output_kind'"

capture program drop fail
program define fail
    args category variable observation
    if "`variable'" == "" local variable "."
    if "`observation'" == "" local observation "."
    file open result using "stata-compare-result.tsv", write text replace
    file write result "mismatch" _tab "$DTATOOLS_OUTPUT_KIND" _tab ///
        "`category'" _tab "`variable'" _tab "`observation'" _n
    file close result
    exit 9
end

capture noisily use "`source'", clear
if _rc fail "source-open" "" ""
local source_n = _N
local source_k = c(k)
unab source_names : _all
local source_dlabel : data label
if `source_release' < 118 {
    local source_dlabel = ustrfrom(`"`source_dlabel'"', "windows-1252", 1)
}
else local source_dlabel = ustrfix(`"`source_dlabel'"')

capture noisily describe using "`candidate'"
if _rc fail "candidate-open" "" ""
if r(N) != `source_n' fail "dimensions" "" ""
if r(k) != `source_k' fail "dimensions" "" ""

preserve
quietly use "`candidate'", clear
unab candidate_names : _all
local candidate_dlabel : data label
restore
if `"`source_names'"' != `"`candidate_names'"' fail "variable-names" "" ""
if `"`source_dlabel'"' != `"`candidate_dlabel'"' fail "dataset-label" "" ""

local normalized_source "normalized-source-`output_kind'.dta"
capture erase "`normalized_source'"
clear
quietly copy "`source'" "`normalized_source'", replace
if `source_release' < 118 quietly unicode encoding set windows-1252
else quietly unicode encoding set utf-8
quietly unicode analyze "`normalized_source'", redo
quietly unicode translate "`normalized_source'", invalid(mark) transutf8
quietly unicode erasebackups, badidea
quietly use "`normalized_source'", clear
mata: __dtatools_source_vlabels = J(1, st_nvar(), "")
mata: for (__dtatools_i = 1; __dtatools_i <= st_nvar(); __dtatools_i++) __dtatools_source_vlabels[__dtatools_i] = st_varlabel(__dtatools_i)
mata: __dtatools_source_values = J(0, 1, .)
mata: __dtatools_source_labels = J(0, 1, "")
mata: __dtatools_candidate_values = J(0, 1, .)
mata: __dtatools_candidate_labels = J(0, 1, "")
mata:
real scalar __dtatools_value_labels_equal(
    real colvector source_values,
    string colvector source_labels,
    real colvector candidate_values,
    string colvector candidate_labels
) {
    real colvector used
    real scalar source_index, candidate_index, matched
    if (rows(source_values) != rows(candidate_values)) return(0)
    used = J(rows(candidate_values), 1, 0)
    for (source_index = 1; source_index <= rows(source_values); source_index++) {
        matched = 0
        for (candidate_index = 1; candidate_index <= rows(candidate_values); candidate_index++) {
            if (!used[candidate_index] &
                source_values[source_index] == candidate_values[candidate_index] &
                source_labels[source_index] == candidate_labels[candidate_index]) {
                used[candidate_index] = 1
                matched = 1
                break
            }
        }
        if (!matched) return(0)
    }
    return(1)
}
end
quietly use "`source'", clear

local source_index 0
foreach variable of local source_names {
    local ++source_index
    local original_source_type : type `variable'
    preserve
    quietly use "`normalized_source'", clear
    local source_type : type `variable'
    if substr("`original_source_type'", 1, 3) == "str" & ///
        "`original_source_type'" != "strL" {
        tempvar normalized_length
        quietly generate long `normalized_length' = strlen(`variable')
        quietly summarize `normalized_length', meanonly
        local source_width = max(real(substr("`original_source_type'", 4, .)), r(max))
        if `source_width' > 2045 local source_type "strL"
        else local source_type "str`source_width'"
    }
    restore
    local source_format : format `variable'
    local source_vallab : value label `variable'
    preserve
    quietly use "`candidate'", clear
    local candidate_type : type `variable'
    local candidate_format : format `variable'
    local candidate_vallab : value label `variable'
    mata: st_numscalar("__dtatools_vlabel_equal", st_varlabel(st_varindex("`variable'")) == __dtatools_source_vlabels[`source_index'])
    restore

    if "`source_type'" != "`candidate_type'" fail "storage-type" "`variable'" ""
    if "`source_format'" != "`candidate_format'" fail "display-format" "`variable'" ""
    if scalar(__dtatools_vlabel_equal) == 0 fail "variable-label" "`variable'" ""
    if "`source_vallab'" != "" & "`candidate_vallab'" == "" {
        tempfile assigned_label_probe
        capture quietly label save `source_vallab' using ///
            "`assigned_label_probe'", replace
        if _rc local source_vallab ""
        else fail "value-label-assignment" "`variable'" ""
    }
    if "`source_vallab'" == "" & "`candidate_vallab'" != "" {
        fail "value-label-assignment" "`variable'" ""
    }
    if "`source_vallab'" != "" {
        preserve
        quietly use "`normalized_source'", clear
        mata: st_vlload("`source_vallab'", __dtatools_source_values, __dtatools_source_labels)
        restore
        preserve
        quietly use "`candidate'", clear
        mata: st_vlload("`candidate_vallab'", __dtatools_candidate_values, __dtatools_candidate_labels)
        restore
        mata: st_numscalar("__dt_vldef_eq", __dtatools_value_labels_equal(__dtatools_source_values, __dtatools_source_labels, __dtatools_candidate_values, __dtatools_candidate_labels))
        if scalar(__dt_vldef_eq) == 0 {
            fail "value-label-definitions" "`variable'" ""
        }
    }
}

local source_note_count : char _dta[note0]
if "`source_note_count'" == "" local source_note_count 0
preserve
quietly use "`candidate'", clear
local candidate_note_count : char _dta[note0]
if "`candidate_note_count'" == "" local candidate_note_count 0
restore
if `source_note_count' != `candidate_note_count' fail "dataset-notes" "" ""
if `source_note_count' > 0 {
    forvalues note = 1/`source_note_count' {
        local source_note : char _dta[note`note']
        if `source_release' < 118 {
            local source_note = ustrfrom(`"`source_note'"', "windows-1252", 1)
        }
        else local source_note = ustrfix(`"`source_note'"')
        preserve
        quietly use "`candidate'", clear
        local candidate_note : char _dta[note`note']
        restore
        if `"`source_note'"' != `"`candidate_note'"' fail "dataset-notes" "" ""
    }
}

quietly use "`normalized_source'", clear
local cf_count 0
local cf_guard_index 0
foreach variable of local source_names {
    if regexm("`variable'", "^__[0-9]+$") {
        local ++cf_count
        local ++cf_guard_index
        local cf_guard "__dtcf`cf_guard_index'"
        capture confirm new variable `cf_guard'
        while _rc {
            local ++cf_guard_index
            local cf_guard "__dtcf`cf_guard_index'"
            capture confirm new variable `cf_guard'
        }
        local cf_old`cf_count' "`variable'"
        local cf_new`cf_count' "`cf_guard'"
        rename `variable' `cf_guard'
    }
}
if `cf_count' > 0 {
    tempfile cf_source cf_candidate
    quietly save "`cf_source'"
    quietly use "`candidate'", clear
    forvalues cf_index = 1/`cf_count' {
        rename `cf_old`cf_index'' `cf_new`cf_index''
    }
    quietly save "`cf_candidate'"
    quietly use "`cf_source'", clear
    capture noisily cf _all using "`cf_candidate'"
}
else capture noisily cf _all using "`candidate'"
if _rc fail "stored-values" "" ""
capture erase "`normalized_source'"

file open result using "stata-compare-result.tsv", write text replace
file write result "pass" _tab "`output_kind'" _tab "." _tab "." _tab "." _n
file close result
exit 0
