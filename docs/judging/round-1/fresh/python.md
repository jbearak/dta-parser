# dta_parser (Python) docs check

Only `docs.md` was used. Scripts: `t2_5.py` (tasks 2–5) and `t6_10.py` (tasks 6–10), in this directory. Run inside `venv`.

## Summary

| # | outcome | doc problem |
|---|---|---|
| 1 | succeeded (after a workaround) | `pip install ./dta-parser/python` needs network access to fetch maturin; docs give no offline route |
| 2 | succeeded | none |
| 3 | succeeded | none |
| 4 | succeeded | none (see note on "or an empty frame") |
| 5 | succeeded | no direct "list all variable labels / formats" call; you build it from `read_meta` |
| 6 | succeeded | none significant |
| 7 | succeeded | none |
| 8 | succeeded | none |
| 9 | succeeded | none |
| 10 | succeeded | docs don't say `>` on a `StataArray` does not follow Stata's "missing is larger" rule |

## Task 1: install and load: succeeded (with a workaround)

Docs: "`pip install ./dta-parser/python` … pip builds the extension with maturin and installs it."

Ran, with `<checkout>` standing for the worktree path in the brief:
```sh
pip install <checkout>/python
```
Result: failed. pip's isolated build env tried to download `maturin<2,>=1.5` from PyPI and got `SSLCertVerificationError`. That is a sandbox/network problem, not a docs error. But the venv did not contain maturin either: it lives in the base `pyenv`, and `--system-site-packages` pointed at the Homebrew Python, not pyenv.

Workaround that worked:
```sh
export PATH=/private/tmp/claude-501/pyenv/bin:$PATH PYTHONPATH=/private/tmp/claude-501/pyenv/lib/python3.14/site-packages
pip install --no-build-isolation <checkout>/python
unset PYTHONPATH
```
Built a `cp310-abi3-macosx_11_0_arm64` wheel and installed it. Then `python -c "import dta_parser; print(dta_parser.read_dta)"` printed `<function read_dta at 0x...>`, and `dta_parser.__file__` is inside the scratch venv.

Doc gap: nothing says what to do when the machine can't reach PyPI (`pip install --no-build-isolation` with maturin already installed). The check command also only passes if run from outside `dta-parser/python`; the docs do cover that in Troubleshooting (`cannot import name '_native'`).

## Task 2: write a small table, read it back: succeeded

```python
df = pd.DataFrame({"i": [1,2,3,4,5,6], "f": [1.5,...], "t": ["a","bb","ccc","d","e","f"],
                   "d": pd.to_datetime([... six days from 2024-01-01 ...])})
dp.write_dta(df, "t2.dta"); back = dp.read_dta("t2.dta"); print(back.dtypes)
```
Saw: `i int8`, `f float64`, `t str` (pandas 3 string dtype), `d datetime64[s]`. The returned object is a `pandas.DataFrame`. All of this matches the table in "Read a file".

## Task 3: select columns, reversed: succeeded

```python
dp.read_dta("t2.dta", columns=["t", "i"])      # ['t', 'i']
dp.read_dta("t2.dta", columns=["f", 0])        # ['f', 'i']  (name + position)
dp.read_dta("t2.dta", columns=["i", "nope"])   # ValueError: the file has no column named 'nope'
dp.read_dta("t2.dta", columns=[99])            # IndexError: there is no column 99; the file has 4
```
Order is the order requested, not file order. Errors match the docs ("A name the file does not have raises `ValueError`; a position out of range raises `IndexError`").

## Task 4: rows 3 to 5: succeeded

```python
dp.read_dta("t2.dta", skip=2, n_max=3)["i"].tolist()   # [3, 4, 5], index [0, 1, 2]
dp.read_dta("t2.dta", skip=4, n_max=10)                 # 2 rows: [5, 6]
dp.read_dta("t2.dta", skip=100)                         # shape (0, 4), columns i f t d, dtypes kept
```
No error past the end, as documented: fewer rows, or an empty frame with the right columns and dtypes. Doc note: the text says "fewer rows, or an empty frame" but does not say that a `skip` beyond the end is the case that gives the empty frame. Minor.

## Task 5: metadata without data: succeeded

Wrote a file with `attrs["dta"] = {"label": "My data label", "columns": {"i": {"label": "Integer var", "format": "%8.0g"}, "f": {"label": "Float var"}}}`, then:
```python
meta = dp.read_meta("t5.dta")
meta["label"]                                            # 'My data label'
{c: m["label"] for c, m in meta["columns"].items()}      # {'i': 'Integer var', 'f': 'Float var', 't': '', 'd': ''}
{c: (m["format"], m["storage"]) for c, m in meta["columns"].items()}
```
Saw storage `byte/double/str3/long`; formats `%8.0g`, `%10.0g`, `%-3s`, `%td`; `nobs` 6. `read_meta` does not read the rows.

Doc gap: there is no call that returns just the variable labels or just the formats. The docs give the dict comprehension only in the pandas/pyreadstat comparison tables ("Coming from pandas.read_stata"), not in the Metadata section. It is easy to infer, but a reader looking in "Metadata" has to know to look there.

## Task 6: value labels and categorical: succeeded

```python
df.attrs["dta"] = {"columns": {"sex": {"value_labels": "sexlbl"}}, "value_labels": {"sexlbl": {1: "female", 2: "male"}}}
dp.write_dta(df, "t6.dta"); back = dp.read_dta("t6.dta")
labels = back.attrs["dta"]["value_labels"]["sexlbl"]      # {1: 'female', 2: 'male'}
labels[2]                                                 # 'male'
pd.Categorical(back["sex"].map(labels), categories=[labels[c] for c in sorted(labels)])
```
Saw `['female', 'male', 'male', 'female']`, dtype `category`. Writing the categorical column back gave a long column with a new set named after the column, coded `{0: 'female', 1: 'male'}` and codes `[0, 1, 1, 0]`, as the docs warn.

Note: a stray extra set (`sexlbl`) was still written because `attrs` carried over the old set. That matches "A set that no column uses is still written" in the guide, but a reader might not expect it.

## Task 7: dates: succeeded

```python
dp.write_dta(pd.DataFrame({"when": pd.to_datetime(["2024-03-01", "2024-03-02"])}), "t7.dta")
dp.read_dta("t7.dta")["when"]                 # datetime64[s]
dp.read_dta("t7.dta", dates=False)["when"]    # int32 [23436, 23437]
```
Default read gives `datetime64[s]`. With `dates=False` the column is the raw day count (`int32`, long storage with `%td`). It matches the docs (23436 = 2024-03-01).

## Task 8: write, release, storage types, errors: succeeded

Wrote bool, small int, int needing int16, int needing int32, int beyond long, float32, float64, text, datetime with a time part, and a `Categorical`. `read_meta` gives `release` 118 and:

| column | storage |
|---|---|
| bool | byte |
| 1..3 | byte |
| 1,300,5 | int |
| 1,70000,5 | long |
| 1,3e9,5 | double |
| float32 | float |
| float64 | double |
| text | str3 |
| datetime with time | double, `%tc` |
| categorical | long |

All as in the docs' tables. Errors seen:

- column `1abc` → `ValueError: column '1abc' is not a name Stata can hold: 1 to 32 letters, digits or _, not starting with a digit, and not a reserved word`
- column `long` → the same `ValueError` (reserved word)
- `2**60` → `ValueError: column 'x': 1152921504606846976 is beyond ±2^53, which Stata cannot store exactly`
- mixed object column `[1, "a"]` → `ValueError: x row 1: cannot write a int as a string` (the docs' Troubleshooting entry says this, with the same wording)
- complex or timedelta column → `TypeError: column 'x': cannot write a column of dtype ...` (docs: "Anything else raises `TypeError` naming the column")

Also checked: widening a read column (`id * 1000` as int64) is rewritten as `int`; a column marked `storage: float` holding 0.1 reads back as `[0.1]` printed from a float32 column. Doc problem: I tried to get float storage for 0.1 by setting `attrs["dta"]["columns"]["x"]["storage"] = "float"` on a float64 column. `read_meta` showed `storage: double` and the value read back as exactly `0.1`. The docs say `storage` is "used if the values fit it", and `storage-types.md` says "a double written as float is rounded to the nearest float … so `0.1` reads back as `0.10000000149011612`". Together those leave it unclear whether a float64 `0.1` "fits" float, and the only way I found to get float storage is a `float32` column (checked: `f32` → `float`). The docs never say how to ask for float storage from float64 data, and the stated 0.10000000149011612 example did not reproduce by the attrs route.

## Task 9: labels written and read back: succeeded

Ran the docs' example:
```python
dp.write_dta(out, "t9.dta", label="Smoking", variable_labels={"id": "Person"})
```
Read back: data label `Smoking`; variable labels `Person` and `Smokes daily`; value labels `{'yesno': {0: 'No', 1: 'Yes', .d: "Don't know"}}`; column's set name `yesno`. `read_meta` agrees. Also confirmed `label=` and `variable_labels=` work with no `attrs` at all (`Only arg`, `Person id`). The docs' example works verbatim.

## Task 10: `.`, `.a`, `.z`: succeeded

```python
inc = pd.Series([1.0, np.nan, missing.a, 5.0, missing.z, 3.0, missing.a], dtype="stata[double]")
```
After write and read: dtype `stata[double]`, codes `[0 1 2 0 27 0 2]`.

- Told apart per value: `v is missing.a` / `missing.z` identify the letters; `.` is `nan`; `dp.missing_codes(col)` gives codes.
- `rb[rb["inc"] == missing.a]["id"]` → `[3, 7]`; `== missing.z` → `[5]`.
- `isna()` is true for all 27 kinds: `[F, T, T, F, T, F, T]`.
- Filter `id >= 3` kept codes `[2 0 27 0 2]`; `sort_values("inc")` gave ids `[6, 4, 3, 7, 5]`, codes `[0 0 2 2 27]`.
- Wrote the sorted frame and read it back: codes `[0 0 2 2 27]`, values `3.0, 5.0, .a, .a, .z`. Letters survive.

Doc gap: `rb[rb["inc"] > 2]` returned ids `[4, 6]` — it excludes every missing value. The guide's missing-values page says "in Stata, `income > 1000` is true for every missing income" and says dta-parser gives a Stata key for that, but nowhere says that ordinary pandas `>` on a `StataArray` does not follow it; you must use `dp.stata_keys(col) > 2`. I did not test the latter. The Python page only shows `==` against a letter and `sort_values`.

## Other notes

- Pyright diagnostics in the editor ("Import dta_parser could not be resolved", `.codes` on `ExtensionArray`) are only the editor not seeing the venv and pandas typing `.array` as the base class; the scripts run.
- The docs' claim that text reads as `str` on pandas 3 matched (`<StringDtype(storage='python', na_value=nan)>`).
