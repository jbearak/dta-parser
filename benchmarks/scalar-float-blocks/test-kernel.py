#!/usr/bin/env python3
"""Compile the actual scalar writer and test its bounded classification work."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

here = Path(__file__).resolve().parent
repository = here.parents[1]
with tempfile.TemporaryDirectory(prefix='float-scalar-kernel-') as temporary:
    executable = Path(temporary) / 'test-kernel'
    command = shlex.split(os.environ.get('CC', 'cc'))
    subprocess.run(command + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
        '-I', str(repository / 'r-package/dtatools/src'),
        str(here / 'test-kernel.c'), '-lm', '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
