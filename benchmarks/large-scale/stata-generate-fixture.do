version 18.0
clear all
set more off
set maxvar 120000

args output rows_arg dataset result
local rows = real("`rows_arg'")
set obs `rows'

generate long id = _n
generate long household_id = floor((_n - 1) / 3) + 1
generate byte wave = mod(_n - 1, 12) + 1
generate double income = 18000 + mod(_n, 250000) * 1.17
replace income = .a if mod(_n, 997) == 0
generate double expenditure = 9000 + mod(_n, 140000) * 0.83
replace expenditure = . if mod(_n, 991) == 0
generate float sampling_weight = 0.25 + mod(_n, 10000) / 1000
generate float latitude = -44.5 + mod(_n, 134000) / 1000
generate double longitude = -179.5 + mod(_n, 359000) / 1000
generate float score_physical = sin(_n / 113) * 12 + 50
generate float score_mental = cos(_n / 127) * 11 + 51
generate double score_economic = ln(1 + mod(_n, 50000))
generate double score_environment = sqrt(mod(_n, 100000))
generate int age = 18 + mod(_n, 83)
generate byte household_size = 1 + mod(_n, 8)
generate byte children = mod(_n, 5)
generate int visits = mod(_n, 24)
generate int survey_year = 2000 + mod(_n, 25)
generate byte survey_month = 1 + mod(_n, 12)
generate int status_code = mod(_n, 17)
generate long provider_count = mod(_n, 12)
generate long event_count = mod(_n, 200)
generate long quality_flag = mod(_n, 4)

generate long region = mod(_n - 1, 6) + 1
label define region_values 1 "Northeast" 2 "Midwest" 3 "South" 4 "West" 5 "Territory" 6 "Overseas"
label values region region_values
generate long education = mod(_n * 7, 5) + 1
label define education_values 1 "Primary" 2 "Secondary" 3 "College" 4 "Graduate" 5 "Unknown"
label values education education_values
generate long employment = mod(_n * 11, 5) + 1
label define employment_values 1 "Employed" 2 "Unemployed" 3 "Student" 4 "Retired" 5 "Other"
label values employment employment_values
generate long self_rated_health = mod(_n * 13, 5) + 1
label define health_values 1 "Excellent" 2 "Good" 3 "Fair" 4 "Poor" 5 "Missing"
label values self_rated_health health_values

generate double birth_date = mdy(1, 1, 1940) + mod(_n, 25000)
format birth_date %td
generate double interview_date = mdy(1, 1, 2010) + mod(_n, 5500)
format interview_date %td
generate double created_at = clock("01jan2018 00:00:00", "DMYhms") + mod(_n, 10000000) * 1000
format created_at %tc
generate double updated_at = clock("01jan2020 00:00:00", "DMYhms") + mod(_n, 15000000) * 1000
format updated_at %tc

generate str13 case_code = "CASE-" + string(mod(_n, 100000), "%08.0f")
generate str2 state_code = word("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY", mod(_n - 1, 50) + 1)
generate str8 county = word("Kings Queens Cook Harris Maricopa Orange Wayne Clark Franklin Fairfax", mod(_n - 1, 10) + 1)
generate str14 occupation = word("Education Healthcare Construction Retail Manufacturing Technology Hospitality Transportation Government Agriculture", mod(_n - 1, 10) + 1)
generate str22 industry = "Public administration"
replace industry = "Professional services" if mod(_n - 1, 6) == 1
replace industry = "Health and social care" if mod(_n - 1, 6) == 2
replace industry = "Wholesale and retail" if mod(_n - 1, 6) == 3
replace industry = "Information services" if mod(_n - 1, 6) == 4
replace industry = "Accommodation and food" if mod(_n - 1, 6) == 5
generate str11 product_code = "P" + string(mod(_n, 100000), "%05.0f") + "-" + string(mod(_n * 17, 10000), "%04.0f")
generate str12 cohort = word("pre-1965 1965-1979 1980-1994 1995-2009 2010-present", mod(_n - 1, 5) + 1)
generate str10 language = word("English Spanish French Mandarin Arabic Portuguese Hindi Other", mod(_n - 1, 8) + 1)
generate str76 description = "Household survey record " + string(mod(_n, 100000), "%08.0f") + " in rotating panel " + string(mod(_n, 24), "%02.0f") + " with verified response"
generate str127 note = "Quality-controlled synthetic microdata row " + string(mod(_n, 100000), "%08.0f") + "; source wave " + string(mod(_n, 12), "%02.0f") + "; deterministic benchmark payload."

label data "Stata-authored synthetic primary benchmark"
local columns = c(k)

timer clear 1
timer on 1
capture noisily save "`output'", replace
local status = cond(_rc == 0, "ok", "error")
timer off 1
quietly timer list 1
local elapsed = r(t1)
local bytes = .
capture confirm file "`output'"
if _rc == 0 {
    quietly checksum "`output'"
    local bytes = r(filelen)
}
file open result_file using "`result'", write text replace
file write result_file "stata" _tab "`status'" _tab %21.9f (`elapsed') _tab %21.0f (`rows') _tab %21.0f (`columns') _tab %21.0f (`bytes') _n
file close result_file
exit, clear
