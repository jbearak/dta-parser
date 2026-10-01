#!/usr/bin/env python3
"""Sample competing CPU without publishing process arguments or input paths."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import time


def competitors(processes, work):
    owned = {os.getpid()} | {int(row[0]) for row in processes
        if "refresh-matched.py measure" in row[4] and str(work) in row[4]}
    while True:
        expanded = owned | {int(row[0]) for row in processes if int(row[1]) in owned}
        if expanded == owned:
            break
        owned = expanded
    return [dict(pid=int(pid), parent=int(parent), cpu_percent=float(cpu), state=state,
                 kind=Path(command.split()[0]).name)
            for pid, parent, cpu, state, command in processes
            if int(pid) not in owned and float(cpu) >= 50 and not state.startswith(("T", "Z"))]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=lambda x: Path(x).resolve(), required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--minutes", type=float, default=120)
    args = parser.parse_args()
    if args.log.exists():
        raise ValueError("Monitor log must be new")
    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    deadline = time.monotonic() + args.minutes * 60
    while running and time.monotonic() < deadline:
        raw = subprocess.check_output(["ps", "-ww", "-axo", "pid=,ppid=,pcpu=,stat=,args="], text=True)
        processes = [line.strip().split(None, 4) for line in raw.splitlines() if line.strip()]
        processes = [row for row in processes if len(row) == 5]
        observations = args.work / "observations.jsonl"
        record = dict(utc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            completed_attempts=observations.read_bytes().count(b"\n") if observations.exists() else 0,
            nonowned_heavy=competitors(processes, args.work), source="ps pcpu",
            cpu_threshold=50, sample_period_seconds=30)
        with args.log.open("a") as stream:
            stream.write(json.dumps(record, sort_keys=True) + "\n")
        if (args.work / "COMPLETE").exists():
            break
        for _ in range(30):
            if not running:
                break
            time.sleep(1)


if __name__ == "__main__":
    main()
