#!/usr/bin/env python3
"""Regenerate both producer bodies from the receipt-bound installed binaries."""
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('audit', HERE / 'mixed-add-control-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


def main():
    tool = Path('/Library/Developer/CommandLineTools/usr/bin/otool').resolve()
    bindings = []
    for name, recorded in [('pair-prototype', 'pair-prototype-disassembly.txt'),
                           ('float-product-prototype', 'float-product-otool-disassembly.txt')]:
        receipt_path = HERE / name / 'build-receipt.json'
        receipt = json.loads(receipt_path.read_text())
        binary = HERE / name / 'library/dtatools/libs/dtatools.so'
        expected = receipt['installed_inventory']['libs/dtatools.so']
        before = audit.sha(binary)
        if before != expected:
            raise RuntimeError('Installed binary differs from recorded build receipt')
        tool_before = audit.sha(tool)
        target = HERE / (name + '-regenerated-otool.txt')
        command = [str(tool), '-tvV', str(binary)]
        with target.open('w') as output:
            subprocess.run(command, stdout=output, check=True, cwd=HERE)
        if audit.sha(binary) != before or audit.sha(tool) != tool_before:
            raise RuntimeError('Binary or disassembler changed')
        current, original = audit.body(target), audit.body(HERE / recorded)
        if current != original:
            raise RuntimeError('Regenerated complete pair producer differs from recorded disassembly')
        bindings.append({'build': name, 'build_receipt_sha256': audit.sha(receipt_path),
                         'binary_sha256': before, 'command': command,
                         'disassembler_sha256': tool_before, 'regenerated_sha256': audit.sha(target),
                         'recorded_sha256': audit.sha(HERE / recorded),
                         'verified_function': 'arithmetic_pair_write', 'instruction_count': len(current[0])})
    report = {'status': 'PASS', 'scope': 'Fresh installed-binary disassembly binding for the entire compared producer body; no performance measurements',
              'bindings': bindings, 'script_sha256': audit.sha(Path(__file__).resolve()),
              'comparison_script_sha256': audit.sha(HERE / 'mixed-add-control-audit.py'),
              'comparison_receipt_sha256': audit.sha(HERE / 'mixed-add-control-audit.json')}
    target = HERE / 'mixed-add-disassembly-binding.json'
    target.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': 'PASS', 'receipt': str(target)}))


if __name__ == '__main__':
    main()
