capture noisily set maxvar 120000
local maxvar_rc = _rc
local stata_release = c(stata_version)
local status = cond(`maxvar_rc' == 0 & `stata_release' >= 18, "ok", "error")
file open result using "stata-preflight-result.tsv", write text replace
file write result "`status'" _n
file close result
exit 0
