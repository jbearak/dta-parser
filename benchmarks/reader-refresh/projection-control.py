#!/usr/bin/env python3
"""Run the retained India projection thread protocol, with source/build linkage."""
import argparse
import csv
import json
from pathlib import Path
import statistics
from driver_common import add_binding_arguments, child_environment, require, run_child, sha, source_binding
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("library",type=Path)
parser.add_argument("output",type=Path)
parser.add_argument("--threads",default="1,2,4,8,12,16,0")
parser.add_argument("--repetitions",type=int,default=10)
add_binding_arguments(parser)
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
source=args.source_root.resolve() if args.source_root else root
base=Path(__file__).resolve().parent
args.library=args.library.resolve();args.output=args.output.resolve()
args.output.mkdir(parents=True,exist_ok=False)
directory=args.data_root.resolve()/"projection-introspection/run-india-20260828T203157Z/india-2021-wm"
paths=[directory/"input.dta",directory/"present.txt",directory/"union.txt"]
scripts=[Path(__file__),base/"driver_common.py",base/"projection-threads.R",base/"workers/benchmark-common.R"]
def binding():
    """Bind the projection input, selection lists, workers and installation."""
    value=source_binding(source,args.library,args.build_record,scripts)
    value["inputs"]={p.name:dict(bytes=p.stat().st_size,sha256=sha(p)) for p in paths}
    value["threads"]=args.threads;value["repetitions"]=args.repetitions
    return value
before=binding()
(args.output/"binding.json").write_text(json.dumps(before,indent=2)+"\n")
run_child(args.output,"control",base/"projection-threads.R",
          [*paths,args.repetitions,args.output/"projection",args.threads],child_environment(args.library))
require(binding() == before, "projection bindings changed during measurement")
with (args.output/"projection-observations.csv").open() as stream: observations=list(csv.DictReader(stream))
summary=[]
for threads,method in sorted(set((int(r["threads"]),r["method"]) for r in observations)):
    rows=[r for r in observations if int(r["threads"])==threads and r["method"]==method]
    require(len(rows) == args.repetitions, "projection repetition count differs")
    result=dict(threads=threads,method=method,iterations=len(rows))
    for field in ("elapsed_seconds","user_cpu_seconds","system_cpu_seconds","cpu_seconds"):
        values=[float(r[field]) for r in rows]
        for label,fn in [("median",statistics.median),("min",min),("max",max)]:result[label+"_"+field]=fn(values)
    summary.append(result)
with (args.output/"summary.csv").open("w") as stream:
    writer=csv.DictWriter(stream,fieldnames=list(summary[0]));writer.writeheader();writer.writerows(summary)
(args.output/"COMPLETE").write_text("Projection controls complete; final bindings matched.\n")
