/**
 * @name Preserved compilation statuses
 * @description Recorded translation units and normal termination; termination is not parsing success.
 * @kind table
 * @id local/preserved-compilation-statuses
 */
import cpp

from Compilation c, string file, string termination, string mode
where
  (file = c.getAFileCompiled().getAbsolutePath()
    or not exists(c.getAFileCompiled()) and file = "") and
  (if c.normalTermination() then termination = "normal" else termination = "aborted") and
  (if c.buildModeNone() then mode = "none" else mode = "other")
select file, termination, mode,
  concat(int i | | c.getArgument(i), " " order by i) as arguments
