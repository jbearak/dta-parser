# dtaparser's accessors take haven's and labelled's names

Plan 0013 gives dtaparser five functions to read back what `read_dta`
keeps: `na_tag` and `is_tagged_na` for `.a` to `.z`, and `var_label`,
`val_labels` and `val_label` for labels. They take the names haven and
labelled use for the same jobs, so an R user who knows those packages
knows what these do. They work on dtaparser's columns as they are: no
class, the letters in tagged NAs, the labels in attributes.

Three of the names are also exported by other packages, and the
results differ:

- **labelled's `val_labels` and `val_label`** read only class
  `haven_labelled`, so on a dtaparser column they give `NULL`. With
  labelled attached after dtaparser, a bare `val_labels(x)` gives
  `NULL` without an error.
- **dtatools' `val_labels` and `val_label`** work on `dta_num`.
  `val_labels` wraps the codes in a `dta_num` where dtaparser's returns
  the attribute (the same numbers), and `val_label` needs `values`,
  so a bare `val_label(x)` errors when dtatools was attached last.
- **haven's `na_tag` and `is_tagged_na`** stop on anything that is not
  a double. dtaparser's give `NA` and `FALSE` for integers, logicals
  and factors, because a byte, int or long column is an integer only
  when the rows read held no `.a` to `.z` (ADR 0017); they still stop
  on characters and lists.

The help pages and `docs/r.md` say to write `dtaparser::val_label()`
when another of these packages is attached.

## Considered options

- **Names of our own** (`dta_var_label`, `missing_letter`, ...). No
  masking, but a new vocabulary for things R users already have words
  for, and one that dtatools does not share.
- **S3 generics in dtaparser with `dta_num` methods in dtatools.** One
  `val_labels` that does the right thing on either package's columns,
  but dtatools would import dtaparser's namespace and its R functions
  would depend on dtaparser's, where today the packages meet only at
  the C callables (ADR 0016).
- **No accessors; document `attr()` and `haven::na_tag()`.** haven is
  only in Suggests, its `na_tag` fails on integer columns, and matching
  `.a` against `.b` by hand needs care, since `match()` treats every
  `NA` alike.

## Consequences

- Which function a bare name finds depends on the order packages were
  attached; the tests do not cover that, since it is R's behaviour.
- dtaparser's exports grow from two to seven. dtatools' docs test also
  checks that each has a help page and appears in `docs/r.md`.
