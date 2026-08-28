capture noisily set maxvar 120000
local status = cond(_rc == 0, "ok", "error")
file open result using "stata-preflight-result.tsv", write text replace
file write result "`status'" _n
file close result
exit 0
