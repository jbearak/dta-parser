"""Words Stata reserves, which it cannot use as variable names (the list
the R, Julia and TypeScript writers check too). Plain Python, so
datakit's `save_dta` uses it without importing pandas."""

import re
import warnings

RESERVED = {
    "_all", "_b", "byte", "_coef", "_cons", "double", "float", "if", "in", "int", "long", "_n", "_N",
    "_pi", "_pred", "_rc", "_skip", "strL", "using", "with",
}


def reserved_warning(names, who):
    """One warning naming the columns called by a word Stata reserves (or
    str followed by digits); the file is still written, but Stata cannot
    use them until they are renamed."""
    reserved = [n for n in names if isinstance(n, str) and (n in RESERVED or re.fullmatch(r"str\d+", n))]
    if reserved:
        one = len(reserved) == 1
        listed = ", ".join(f'"{n}"' for n in reserved)
        warnings.warn(f"{who}: {listed} {'is a word' if one else 'are words'} Stata reserves; rename "
                      f"{'it' if one else 'them'} before using the file in Stata", UserWarning, stacklevel=3)
