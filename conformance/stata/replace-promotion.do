* Records what Stata's `replace` does to a variable's storage type, so the
* promotion rule in dtatools can be compared against a measurement rather
* than against recollection. Run with:
*
*     stata -b do conformance/stata/replace-promotion.do
*
* and compare the result against replace-promotion.log, which was produced
* by Stata 18.0 MP.
clear
set obs 3

* Out of range for the declared type: Stata widens to the next type that
* holds the value, and says so.
gen byte  range_byte = 1
replace   range_byte = 200
describe  range_byte

gen int   range_int = 1
replace   range_int = 40000
describe  range_int

gen long  range_long = 1
replace   range_long = 3000000000
describe  range_long

* Not an integer, in an integer type: Stata widens byte and int to float,
* and long to double, because a long can exceed float's precision.
gen byte  frac_byte = 1
replace   frac_byte = 1.5
describe  frac_byte

gen int   frac_int = 1
replace   frac_int = 1.5
describe  frac_int

gen long  frac_long = 1
replace   frac_long = 1.5
describe  frac_long

* Precision alone never promotes: a float keeps float and rounds, silently.
gen float prec_float = 1
replace   prec_float = 1.234567890123456
describe  prec_float
display %20.15f prec_float[1]

* Documentation policy examples: Stata keeps float for 2^24 + 1, and
* widens byte to float for 0.1. Both values round to binary32.
gen float integer_precision = 1
replace   integer_precision = 16777217 in 1
local integer_storage : type integer_precision
assert "`integer_storage'" == "float"
assert integer_precision == 16777216 in 1
assert integer_precision == 1 in 2/3
describe  integer_precision
display %20.0f integer_precision[1]

gen byte  decimal_precision = 1
replace   decimal_precision = 0.1 in 1
local decimal_storage : type decimal_precision
assert "`decimal_storage'" == "float"
assert decimal_precision == float(0.1) in 1
assert decimal_precision != 0.1 in 1
assert decimal_precision == 1 in 2/3
describe  decimal_precision
display %20.17f decimal_precision[1]

* Beyond float's range: no promotion either, and the value becomes missing.
gen float over_float = 1
replace   over_float = 1e40
describe  over_float
display   over_float[1]

* Strings widen to the smallest str# that fits.
gen str3  s = "abc"
replace   s = "abcdefgh"
describe  s

* No rows selected: no promotion, no message beyond the change count.
gen byte  none_byte = 1
replace   none_byte = 1000 if 0
describe  none_byte

* Stata's `generate` default is float, so a literal above 2^24 loses digits
* at creation. This is the precision trap `dtatools.generate_type` exists
* to escape; it is not a promotion.
gen       gen_default = 16777217
describe  gen_default
display %20.0f gen_default[1]
