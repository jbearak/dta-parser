/**
 * @name Include edges including external generated and R headers
 * @description Context-insensitive absolute edges support conservative per-source reachability checks, not exact preprocessor context equivalence.
 * @kind table
 * @id local/manual-absolute-include-edges
 */
import cpp
from Include i, string target
where target = i.getIncludedFile().getAbsolutePath()
  or not exists(i.getIncludedFile()) and target = ""
select i.getFile().getAbsolutePath() as file,
  i.getLocation().getStartLine() as line, i.getIncludeText() as include_text,
  target as resolved_file
