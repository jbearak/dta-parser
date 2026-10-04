/**
 * @name Preserved source files
 * @description Source file presence only, separate from parsing and include diagnostics.
 * @kind table
 * @id local/preserved-source-files
 */
import cpp
from File f
where exists(f.getRelativePath()) and f.fromSource()
select f.getRelativePath() as file
