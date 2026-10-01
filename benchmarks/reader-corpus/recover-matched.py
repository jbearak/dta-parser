#!/usr/bin/env python3
"""Reconstruct the historical matched set from exact counts and byte sums."""
import argparse
import csv
from decimal import Decimal
import hashlib
import itertools
import json
import math
from pathlib import Path

EXPECTED_INVENTORY_SHA256 = "8f8964891ab2d9429988a8bcddf8ddb3a32338b3a4399ad154dc70df8a370367"
EXPECTED_TOTALS = {"DHS": (641, 46903402101), "MICS": (949, 3690394621),
                   "NSFG": (222, 5771879262)}
EVIDENCE = Path(__file__).parent / "results-2026-10-01-matched/recovery"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_table(path, delimiter=","):
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter=delimiter))


def reconstruct(inventory, summaries):
    """Fail unless every format group has exactly one compatible membership."""
    require(inventory and len({r["id"] for r in inventory}) == len(inventory),
            "empty inventory or duplicate IDs")
    require(all(str(int(r["bytes"])) == r["bytes"] and int(r["bytes"]) >= 0
                for r in inventory), "invalid inventory byte count")
    grouped = {}
    for row in inventory:
        grouped.setdefault((row["corpus"], row["release"]), []).append(row)
    formats = [s for s in summaries if s["release"] != "all"]
    keys = [(s["corpus"], s["release"]) for s in formats]
    require(len(keys) == len(set(keys)) and set(keys) == set(grouped),
            "missing, duplicate, or added format summary")
    common, proofs = set(), []
    for summary in formats:
        key = summary["corpus"], summary["release"]
        group = grouped[key]
        count, excluded = int(summary["files"]), int(summary["excluded_files"])
        wanted = Decimal(summary["input_gb"]) * Decimal(10**9)
        require(wanted.is_finite() and wanted >= 0 and wanted == wanted.to_integral_value(),
                "historical size does not express an exact nonnegative byte count")
        wanted = int(wanted)
        require(count >= 0 and excluded >= 0 and len(group) == count + excluded,
                "historical format count differs from inventory")
        use_excluded = excluded < count
        choose = excluded if use_excluded else count
        target = sum(int(r["bytes"]) for r in group) - wanted if use_excluded else wanted
        possibilities = math.comb(len(group), choose)
        require(possibilities <= 100000, "unexpectedly large membership search")
        solutions = []
        for subset in itertools.combinations(group, choose):
            if sum(int(r["bytes"]) for r in subset) == target:
                solutions.append({r["id"] for r in subset})
        require(len(solutions) == 1, "format membership is missing or ambiguous")
        selected = solutions[0]
        members = {r["id"] for r in group} - selected if use_excluded else selected
        require(len(members) == count, "incorrect recovered membership count")
        common.update(members)
        proofs.append(dict(corpus=key[0], release=key[1], inventory_files=len(group),
                           common_files=count, common_bytes=wanted, excluded_files=excluded,
                           enumerated_subsets=possibilities, matching_subsets=1))
    return common, proofs


def private_membership(original, cache, inventory, common):
    require(sha(original) == EXPECTED_INVENTORY_SHA256,
            "original inventory does not match its published historical SHA-256")
    rows = read_table(original, "\t")
    public = {r["id"]: r for r in inventory}
    require(len(rows) == len(public) and len({r["id"] for r in rows}) == len(rows)
            and {r["id"] for r in rows} == set(public), "original inventory IDs differ")
    result = []
    for row in rows:
        expected = public[row["id"]]
        require((row["corpus"], row["bytes"]) == (expected["corpus"], expected["bytes"]),
                "original inventory corpus or size differs")
        relative = Path(row["relative_path"])
        require(not relative.is_absolute() and ".." not in relative.parts,
                "invalid inventory relative path")
        path = cache / relative
        require(path.is_file() and not path.is_symlink(), "missing or symlinked input")
        stat = path.stat()
        require(stat.st_size == int(row["bytes"]) and
                abs(stat.st_mtime - float(row["mtime"])) < 1e-5, "input metadata changed")
        with path.open("rb") as stream:
            header = stream.read(100)
        if header.startswith(b"<stata_dta>"):
            release = header.split(b"<release>", 1)[1].split(b"</release>", 1)[0].decode("ascii")
        elif header and header[0] in (105, 108, 110, 111, 113, 114, 115):
            release = str(header[0])
        else:
            release = "unknown"
        require(release == expected["release"], "input format differs from recovery inventory")
        result.append(dict(row, release=release, common=row["id"] in common))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, default=EVIDENCE)
    parser.add_argument("--output", type=Path, required=True, help="new output directory")
    parser.add_argument("--original-inventory", type=Path)
    parser.add_argument("--cache", type=Path)
    args = parser.parse_args()
    require(bool(args.original_inventory) == bool(args.cache),
            "original inventory and cache must be supplied together")
    require(not args.output.exists(), "output directory must be new")
    inventory_path = args.evidence / "inventory.csv"
    summary_path = args.evidence / "historical-format-summary.tsv"
    inventory = read_table(inventory_path)
    summaries = read_table(summary_path, "\t")
    published_path = Path(__file__).parent / "results-2026-09-16-base-r/corpus-summary.csv"
    published = read_table(published_path)
    require(len(inventory) == 1823, "expected historical 1823-file inventory")
    common, proofs = reconstruct(inventory, summaries)
    require(len(common) == 1812, "expected historical 1812-file matched set")
    totals = []
    for corpus, expected in EXPECTED_TOTALS.items():
        members = [r for r in inventory if r["corpus"] == corpus and r["id"] in common]
        total = len(members), sum(int(r["bytes"]) for r in members)
        require(total == expected, "recovered corpus aggregate differs from published evidence")
        archived_rows = [r for r in published if r["corpus"] == corpus]
        require(len(archived_rows) == 4 and all(
            (int(r["files"]), int(r["dta_bytes"])) == total for r in archived_rows),
            "recovered membership differs from retained four-reader comparison coverage")
        totals.append(dict(corpus=corpus, files=total[0], bytes=total[1]))
    private = private_membership(args.original_inventory, args.cache, inventory, common) \
        if args.original_inventory else None
    args.output.mkdir(parents=True)
    matched_path = args.output / "matched.csv"
    with matched_path.open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=["corpus", "id", "release", "bytes"],
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows({k: r[k] for k in writer.fieldnames}
                         for r in inventory if r["id"] in common)
    if private is not None:
        (args.output / "membership-private.json").write_text(json.dumps(private, indent=2) + "\n")
    audit = dict(inventory_files=1823, matched_files=1812, groups=proofs, totals=totals,
                 inventory_csv_sha256=sha(inventory_path), summary_sha256=sha(summary_path),
                 retained_comparison_csv_sha256=sha(published_path),
                 matched_csv_sha256=sha(matched_path), script_sha256=sha(Path(__file__)),
                 original_inventory_sha256=sha(args.original_inventory) if private is not None else None,
                 original_raw_tsv_recovered=False,
                 method="Unique exhaustive membership reconstruction from historical counts and exact byte sums")
    (args.output / "audit.json").write_text(json.dumps(audit, indent=2) + "\n")
    print(json.dumps(dict(matched_files=1812, totals=totals)))


if __name__ == "__main__":
    main()
