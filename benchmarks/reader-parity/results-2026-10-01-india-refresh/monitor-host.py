"""Sample competing process load without retaining command arguments or paths."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--work", type=Path, required=True)
parser.add_argument("--log", type=Path, required=True)
parser.add_argument("--minutes", type=float, default=60)
args = parser.parse_args()
running = True

def stop(*_):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
deadline = time.monotonic() + args.minutes * 60
while running and time.monotonic() < deadline:
    raw = subprocess.check_output(["ps", "-ww", "-axo", "pid=,ppid=,pcpu=,stat=,args="], text=True)
    processes = [line.strip().split(None, 4) for line in raw.splitlines() if line.strip()]
    processes = [row for row in processes if len(row) == 5]
    owned = {os.getpid()} | {int(row[0]) for row in processes
        if ("benchmarks/reader-parity/refresh-india.py" in row[4] or "benchmarks/reader-corpus/refresh-matched.py" in row[4])}
    while True:
        expanded = owned | {int(row[0]) for row in processes if int(row[1]) in owned}
        if expanded == owned:
            break
        owned = expanded
    heavy = [dict(pid=int(pid), parent=int(parent), cpu_percent=float(cpu), state=state,
                  kind=Path(command.split()[0]).name)
             for pid, parent, cpu, state, command in processes
             if int(pid) not in owned and float(cpu) >= 50 and not state.startswith(("T", "Z"))]
    observations = args.work / "observations.csv"
    record = dict(utc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
        completed_attempts=max(0, observations.read_bytes().count(b"\n") - 1) if observations.exists() else 0,
        nonowned_heavy=heavy, source="ps pcpu", cpu_threshold=50, sample_period_seconds=5)
    with args.log.open("a") as stream:
        stream.write(json.dumps(record, sort_keys=True) + "\n")
    if (args.work / "COMPLETE").exists():
        break
    for _ in range(5):
        if not running:
            break
        time.sleep(1)
