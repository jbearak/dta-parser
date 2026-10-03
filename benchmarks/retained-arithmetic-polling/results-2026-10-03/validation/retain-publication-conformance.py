from pathlib import Path
import shutil,sys
source=Path(sys.argv[1]); target=Path('<work>')
archives=list(source.glob('dtatools_*.tar.gz'))
if len(archives)==1: shutil.copy2(archives[0],target/'publication-conformance.tar.gz')
logs=target/'publication-conformance-retained'; logs.mkdir(exist_ok=True)
for pattern in ('*.Rcheck/*.log','*.Rcheck/tests/*.Rout','*.Rcheck/tests/*.Rout.fail','*.Rcheck/tests/*.log'):
 for path in source.glob(pattern):
  relative=path.relative_to(source); output=logs/relative; output.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(path,output)
