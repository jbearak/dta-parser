#!/usr/bin/env python3
"""Every arithmetic include must invalidate numeric-payload.o incrementally."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'r-package/dtatools/src'


class ArithmeticDependencies(unittest.TestCase):
    def test_transitive_arithmetic_headers_rebuild_object(self):
        make = shutil.which('make')
        self.assertIsNotNone(make, 'make is required to verify native dependencies')
        headers = set()

        def visit(name):
            if name in headers:
                return
            headers.add(name)
            for child in re.findall(r'^#include "(numeric-arithmetic[^\"]*\.h)"',
                                    (SOURCE / name).read_text(), re.M):
                visit(child)

        visit('numeric-arithmetic.h')
        self.assertEqual(headers, {path.name for path in SOURCE.glob('numeric-arithmetic*.h')})
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            for path in SOURCE.glob('*.h'):
                shutil.copyfile(path, directory / path.name)
                os.utime(directory / path.name, (1000000000, 1000000000))
            shutil.copyfile(SOURCE / 'Makevars.rust', directory / 'Makevars.rust')
            # The real dependency include drives a cheap stand-in object recipe.
            # This checks make's invalidation behavior, not C compilation.
            (directory / 'Makefile').write_text(
                'OBJECTS = numeric-payload.o\nSHLIB = unused.so\nRUST_LIB = unused.a\n'
                'include Makevars.rust\n'
                'numeric-payload.o:\n\t@echo rebuilt >> rebuilds\n\t@touch $@\n')
            target = directory / 'numeric-payload.o'
            target.touch()
            for header in sorted(headers):
                with self.subTest(header=header):
                    os.utime(target, (1000000001, 1000000001))
                    os.utime(directory / header, (1000000002, 1000000002))
                    result = subprocess.run([make, '-q', 'numeric-payload.o'], cwd=directory,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                    self.assertEqual(result.returncode, 1, f'{header} did not invalidate object: {result.stderr}')
                    subprocess.run([make, 'numeric-payload.o'], cwd=directory, check=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    unchanged = subprocess.run([make, '-q', 'numeric-payload.o'], cwd=directory,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    self.assertEqual(unchanged.returncode, 0, 'Unchanged tree rebuilt repeatedly')
                    os.utime(directory / header, (1000000000, 1000000000))
            self.assertEqual((directory / 'rebuilds').read_text().splitlines(), ['rebuilt'] * len(headers))


if __name__ == '__main__':
    unittest.main()
