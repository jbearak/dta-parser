version 18.0
set more off

capture program drop aww_open
program define aww_open
    syntax, INPUT(string) OUTPUT(string)
    quietly describe using "`input'", varlist
    global AWW_INPUT "`input'"
    global AWW_VARLIST "`r(varlist)'"
    global AWW_N "`r(N)'"
    global AWW_K "`r(k)'"
    global AWW_DATALABEL `"`r(datalabel)'"'
    mata: aww_out = fopen("`output'", "w")
    mata: fput(aww_out, "id" + char(9) + "status" + char(9) + "kind" + char(9) + "index" + char(9) + "value")
end

capture program drop aww_load
program define aww_load
    syntax, COLUMNS(numlist integer >0) FIRST(integer) LAST(integer)
    local wanted
    foreach index of numlist `columns' {
        local name : word `index' of $AWW_VARLIST
        local wanted `wanted' `name'
    }
    if $AWW_N == 0 {
        quietly use `wanted' using "$AWW_INPUT", clear
    }
    else {
        quietly use `wanted' in `first'/`last' using "$AWW_INPUT", clear
    }
    global AWW_FIRST "`first'"
end

capture program drop aww_cell
program define aww_cell
    syntax, ID(integer) COLUMN(integer) OBSERVATION(integer)
    local name : word `column' of $AWW_VARLIST
    local row = `observation' - $AWW_FIRST + 1
    local type : type `name'
    if substr("`type'", 1, 3) == "str" {
        mata: aww_string(`id', "cell", st_sdata(`row', st_varindex("`name'")))
    }
    else {
        mata: aww_number(`id', "cell", st_data(`row', st_varindex("`name'")))
    }
end

capture program drop aww_meta
program define aww_meta
    syntax, ID(integer) KIND(string) [COLUMN(integer 0) INDEX(integer 0)]
    if "`kind'" == "nobs" {
        mata: aww_plain(`id', "nobs", "$AWW_N")
        exit
    }
    if "`kind'" == "nvar" {
        mata: aww_plain(`id', "nvar", "$AWW_K")
        exit
    }
    if "`kind'" == "dataset_label" {
        mata: aww_string(`id', "dataset_label", st_global("AWW_DATALABEL"))
        exit
    }
    if "`kind'" == "note_entry" {
        local count : char _dta[note0]
        if "`count'" == "" local count 0
        if `index' >= 1 & `index' <= `count' {
            local value : char _dta[note`index']
            mata: aww_string(`id', "note_entry", st_local("value"))
        }
        else {
            mata: aww_plain(`id', "note_absent", "")
        }
        exit
    }
    if "`kind'" == "names" {
        forvalues index = 1/$AWW_K {
            local value : word `index' of $AWW_VARLIST
            mata: aww_string_index(`id', "names", `index', "`value'")
        }
        exit
    }
    local name : word `column' of $AWW_VARLIST
    if "`kind'" == "name" {
        mata: aww_string(`id', "name", "`name'")
    }
    else if "`kind'" == "storage" {
        local value : type `name'
        mata: aww_string(`id', "storage", st_local("value"))
    }
    else if "`kind'" == "format" {
        local value : format `name'
        mata: aww_string(`id', "format", st_local("value"))
    }
    else if "`kind'" == "variable_label" {
        local value : variable label `name'
        mata: aww_string(`id', "variable_label", st_local("value"))
    }
    else if "`kind'" == "value_label_name" {
        local value : value label `name'
        mata: aww_string(`id', "value_label_name", st_local("value"))
    }
    else if "`kind'" == "value_label_entry" {
        local value : value label `name'
        mata: aww_value_label_entry(`id', st_local("value"), `index')
    }
end

capture program drop aww_close
program define aww_close
    mata: fclose(aww_out)
    macro drop AWW_INPUT AWW_VARLIST AWW_N AWW_K AWW_DATALABEL AWW_FIRST
end

mata:
aww_out = .

string scalar aww_hex(string scalar value) {
    real rowvector bytes
    string scalar result
    real scalar index
    // Convert through Stata's Unicode semantics before emitting UTF-8.  A
    // direct ascii(value) leaks malformed source bytes instead of U+FFFD.
    bytes = ascii(ustrto(value, "utf-8", 1))
    result = ""
    for (index = 1; index <= cols(bytes); index++) {
        result = result + substr("0123456789abcdef", floor(bytes[index] / 16) + 1, 1) +
            substr("0123456789abcdef", mod(bytes[index], 16) + 1, 1)
    }
    return(result)
}

void aww_line(real scalar id, string scalar status, string scalar kind,
              real scalar index, string scalar value) {
    external real scalar aww_out
    fput(aww_out, strofreal(id) + char(9) + status + char(9) + kind + char(9) +
         strofreal(index) + char(9) + value)
}

void aww_plain(real scalar id, string scalar kind, string scalar value) {
    aww_line(id, "ok", kind, 0, value)
}

void aww_string(real scalar id, string scalar kind, string scalar value) {
    aww_line(id, "ok", kind, 0, aww_hex(value))
}

void aww_string_index(real scalar id, string scalar kind, real scalar index,
                      string scalar value) {
    aww_line(id, "ok", kind, index, aww_hex(value))
}

void aww_number(real scalar id, string scalar kind, real scalar value) {
    if (missing(value)) aww_line(id, "ok", kind, 0, strofreal(value))
    else aww_line(id, "ok", kind, 0, strtrim(strofreal(value, "%24.17g")))
}

void aww_value_label_entry(real scalar id, string scalar label_name,
                           real scalar index) {
    real colvector values
    string colvector texts
    if (label_name == "") {
        aww_line(id, "ok", "value_label_absent", 0, "")
        return
    }
    values = .
    texts = ""
    st_vlload(label_name, values, texts)
    if (index < 1 | index > rows(values)) {
        aww_line(id, "ok", "value_label_absent", 0, "")
        return
    }
    aww_line(id, "ok", "value_label_code", index,
             missing(values[index]) ? strofreal(values[index]) :
             strtrim(strofreal(values[index], "%24.17g")))
    aww_line(id, "ok", "value_label_text", index, aww_hex(texts[index]))
}
end
