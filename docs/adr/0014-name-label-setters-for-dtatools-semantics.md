# Name label setters for dtatools semantics

dtatools retains the `labelled` getter and replacement names, but names its
setters `set_var_label()`, `set_var_labels()`, and `set_val_labels()`. These
setters mutate data frames by reference, and the singular form uses an unquoted
column name like `gen()` and `replace_values()`. Distinct names prevent callers
from assuming the broader, copy-returning `labelled` setter contract. This
supersedes the bulk-setter naming decision in ADR 0003.
