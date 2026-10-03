"""Extract code from the actual receipt-bound installed candidate DLL."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
BUILD=HERE/'candidate-final-v1'
ROOT=Path('<repository>')
PIN='452ac7232ef6e47c398bcd22c7bb2800b55932c3'
RECORDER=ROOT/'benchmarks/native-operations/run.py'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def need(condition,message):
    if not condition:raise RuntimeError(message)
spec=importlib.util.spec_from_file_location('records',RECORDER)
records=importlib.util.module_from_spec(spec);spec.loader.exec_module(records)
before=records.inventory(BUILD,'baseline')
need(before['receipt']['base_commit']==PIN,'Wrong candidate commit')
environment={key:value for key,value in os.environ.items() if not key.startswith('GIT_')}
source={}
for path in sorted((BUILD/'source/src').glob('numeric-arithmetic*.h')):
    relative='src/'+path.name
    blob=subprocess.check_output(['git','--no-replace-objects','show',PIN+':r-package/dtatools/'+relative],cwd=ROOT,env=environment)
    need(blob==path.read_bytes(),'Source differs from immutable commit: '+relative)
    source[relative]=sha(path)
tool=Path('/Library/Developer/CommandLineTools/usr/bin/llvm-otool')
dll=BUILD/'library/dtatools/libs/dtatools.so'
before_tool=sha(tool);before_dll=sha(dll);controller=sha(Path(__file__))
output=HERE/'candidate-otool.txt'
need(not output.exists(),'Refusing to replace existing extraction')
command=[str(tool),'-tvV',str(dll)]
with output.open('wb') as stream:subprocess.run(command,cwd=HERE,stdout=stream,check=True)
need(before==records.inventory(BUILD,'baseline'),'Build binding changed')
need(before_tool==sha(tool) and before_dll==sha(dll) and controller==sha(Path(__file__)),'Codegen inputs changed')
record=dict(status='PASS',commit=PIN,build_receipt_sha256=before['receipt_sha256'],dll_sha256=before_dll,
    disassembler_sha256=before_tool,controller_sha256=controller,recorder_sha256=sha(RECORDER),
    command=command,cwd=str(HERE),output_sha256=sha(output),source=source,
    scope='Fresh installed-DLL extraction with complete source/build inventory verification and immutable relevant source checks; no timing inference.')
(HERE/'candidate-codegen-binding.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')
print('PASS installed candidate codegen binding')
