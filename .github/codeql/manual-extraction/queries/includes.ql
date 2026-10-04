/**
 * @name Preserved source includes
 * @description Recorded source include resolution; context-insensitive file edges are not full coverage proof.
 * @kind table
 * @id local/preserved-source-includes
 */
import cpp

from Include i, string target
where exists(i.getFile().getRelativePath()) and
  (target = i.getIncludedFile().getAbsolutePath()
    or not exists(i.getIncludedFile()) and target = "")
select i.getFile().getRelativePath() as file,
  i.getLocation().getStartLine() as line, i.getIncludeText() as include_text,
  target as resolved_file
