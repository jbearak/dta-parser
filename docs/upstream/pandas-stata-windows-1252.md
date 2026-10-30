# Draft: pandas decodes text in pre-118 `.dta` files as Latin-1

Not filed. For <https://github.com/pandas-dev/pandas/issues>, as a new
issue with the bug report template. No existing report found: searching
the tracker for "read_stata encoding", "read_stata cp1252", "read_stata
windows-1252", "stata encoding", "stata latin1" and "dta cp1252" turns
up nothing about Windows-1252. The nearest are #4626 (2013, about the
old `encoding` keyword), #7286 (2014, writing non-Latin-1 text) and
#37693 (2020, a question closed without the file).

---

**Title:** BUG: `read_stata` decodes text in files before release 118 as
Latin-1, so Windows-1252 characters (€, “ ”, –) become control characters

### Pandas version checks

- [x] I have checked that this issue has not already been reported.
- [x] I have confirmed this bug exists on the latest version of pandas
  (3.1.0).
- [ ] I have confirmed this bug exists on the main branch of pandas.
  (Not run on main; the code in question is unchanged there, see below.)

### Reproducible Example

```python
import pandas as pd

# Write a release 117 file with placeholders, then put in the
# bytes a Windows-1252 writer would store: 0x93 and 0x94 for “ and ”,
# 0x80 for €.
pd.DataFrame({"s": ["{café}", "~ 5"]}).to_stata("cp1252.dta", version=117, write_index=False)
with open("cp1252.dta", "rb") as f:
    raw = f.read()
raw = raw.replace(b"{caf\xe9}", b"\x93caf\xe9\x94").replace(b"~ 5", b"\x80 5")
with open("cp1252.dta", "wb") as f:
    f.write(raw)

print([ascii(s) for s in pd.read_stata("cp1252.dta")["s"]])
# ["'\\x93caf\\xe9\\x94'", "'\\x80 5'"]
```

### Issue Description

Files before release 118 do not record their text encoding.
`StataReader` decodes them as Latin-1
([pandas/io/stata.py#L1203-L1206](https://github.com/pandas-dev/pandas/blob/092d58891fe0effeb8adf0635c52d3c6a7270670/pandas/io/stata.py#L1203-L1206)),
and `read_stata` has no option to choose another encoding.

Latin-1 and Windows-1252 agree everywhere except bytes 0x80 to 0x9F.
Latin-1 maps those to C1 control characters, which almost never occur
in text. Windows-1252 maps them to characters that occur often: curly
quotes, en and em dashes, the euro sign, the ellipsis. Text from such a
file comes back from `read_stata` with control characters in their
place (`'\x93café\x94'` above).

The example writes placeholder characters with `to_stata` and then puts
the Windows-1252 bytes in place, so the file holds what another writer
would have stored.

### Expected Behavior

`['“café”', '€ 5']`, as the other open-source readers give for the same
file:

- ReadStat decodes text before release 118 as Windows-1252 unless told
  otherwise
  ([src/stata/readstat_dta.c#L187-L188](https://github.com/WizardMac/ReadStat/blob/1434a0770a51b4fdb2c09515ea33c38f4fa51be8/src/stata/readstat_dta.c#L187-L188)).
  pyreadstat 1.3.7, which is built on it, returns `['“café”', '€ 5']`
  for this file.
- readstata13 defaults to CP1252 for these releases
  ([R/read.R#L293](https://github.com/sjewo/readstata13/blob/5c02468ef1213c86b7a86260ec6f83f7e40d7d60/R/read.R#L293))
  and returns the same. So does haven 2.5.5.

Two ways this might be handled, for the maintainers to judge:

- Decode as Windows-1252 by default. Python's `cp1252` codec leaves
  0x81, 0x8D, 0x8F, 0x90 and 0x9D undefined, so those five bytes would
  need a fallback (for instance to the Latin-1 character), or
  `read_stata` would raise on files that read today.
- Add an `encoding` argument to `read_stata`/`StataReader` for these
  releases, keeping Latin-1 as the default.

Either way, a file written by `to_stata` with real U+0080 to U+009F
control characters would read back differently under Windows-1252,
which seems a smaller loss than misreading common punctuation.

### Installed Versions

pandas 3.1.0, Python 3.14.7, macOS 26.7.1 (arm64). The lines linked
above are from `main` at 092d588 and match 3.1.0.
