"""Save every input again with dta_parser's read_dta and write_dta, for
compat/readback/check.py to read with other readers. Inputs are the
fixtures in compat/fixtures, and strls.dta and binary.dta in
compat/readback.

Run from the repository root: python3 compat/readback/write.py <out-dir>
"""

import glob
import os
import sys

from dta_parser import read_dta, write_dta

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for path in sorted(glob.glob("compat/fixtures/*.dta")) + ["compat/readback/strls.dta", "compat/readback/binary.dta"]:
    df = read_dta(path, dates=False)
    write_dta(df, os.path.join(out, os.path.basename(path)), timestamp=df.attrs["dta"]["timestamp"] or None)
