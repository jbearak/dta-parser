"""Score tables for one Parquet judging round, from the judges' JSON blocks.

    python docs/judging/parquet_scores.py docs/judging/parquet-round-N

Applies the pass rule of parquet-rubric.md to every judge and pair:

1. on each task the other library supports, our task score is at least
   theirs;
2. our total over the eleven tasks is higher than theirs;
3. each of our eleven task scores is at least 2.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parquet_bundle import UNSUPPORTED  # noqa: E402

JUDGES = ("sonnet", "terra")
TASKS = [str(t) for t in range(1, 12)]


def scores(path):
    text = open(path, encoding="utf-8").read()
    block = json.loads(re.search(r"```json\s*(\{.*?\})\s*```", text, re.S).group(1))
    for lib in ("A", "B"):
        missing = [t for t in TASKS if t not in block[lib]]
        if missing:
            raise SystemExit(f"{path}: library {lib} has no scores for tasks {missing}")
    return block


def mean(xs):
    return sum(xs) / len(xs)


def judge_pair(round_dir, judge, pair):
    s = scores(os.path.join(round_dir, "responses", f"{judge}-{pair['prompt']}"))
    ours, theirs = s[pair["ours"]], s["B" if pair["ours"] == "A" else "A"]
    o = {t: mean(ours[t]) for t in TASKS}
    th = {t: mean(theirs[t]) for t in TASKS}
    supported = [t for t in TASKS if int(t) not in UNSUPPORTED[pair["other"]]]
    behind = [t for t in supported if o[t] < th[t]]
    low = [t for t in TASKS if o[t] < 2]
    total_o, total_th = sum(o.values()), sum(th.values())
    ok = not behind and total_o > total_th and not low
    return {"ours": o, "theirs": th, "behind": behind, "low": low, "total_ours": total_o,
            "total_theirs": total_th, "pass": ok}


def main(round_dir):
    pairs = json.load(open(os.path.join(round_dir, "pairs.json")))["pairs"]
    results = {(j, p["prompt"]): judge_pair(round_dir, j, p) for j in JUDGES for p in pairs}
    passed = all(r["pass"] for r in results.values())

    print("| judge | pair | ours | other library | rule 1: tasks behind | rule 3: tasks below 2 | pass |")
    print("|---|---|---|---|---|---|---|")
    for j in JUDGES:
        for p in pairs:
            r = results[(j, p["prompt"])]
            print(f"| {j} | {p['language']}: {p['other']} | {r['total_ours']:.2f} | {r['total_theirs']:.2f} "
                  f"| {', '.join(r['behind']) or 'none'} | {', '.join(r['low']) or 'none'} "
                  f"| {'yes' if r['pass'] else 'no'} |")

    print("\nTask scores, ours / theirs (an asterisk marks a task the other library cannot do):\n")
    print("| judge | pair | " + " | ".join(TASKS) + " |")
    print("|---|---|" + "---|" * len(TASKS))
    for j in JUDGES:
        for p in pairs:
            r = results[(j, p["prompt"])]
            cells = []
            for t in TASKS:
                star = "*" if int(t) in UNSUPPORTED[p["other"]] else ""
                cells.append(f"{r['ours'][t]:.2f} / {r['theirs'][t]:.2f}{star}")
            print(f"| {j} | {p['other']} | " + " | ".join(cells) + " |")

    print("\nTask scores on which the two judges differ by 1 or more:\n")
    any_diff = False
    for p in pairs:
        a, b = results[("sonnet", p["prompt"])], results[("terra", p["prompt"])]
        for side in ("ours", "theirs"):
            for t in TASKS:
                if abs(a[side][t] - b[side][t]) >= 1:
                    any_diff = True
                    who = "ours" if side == "ours" else p["other"]
                    print(f"- {p['language']}: {p['other']}, {who}, task {t}: sonnet {a[side][t]:.2f}, "
                          f"terra {b[side][t]:.2f}")
    if not any_diff:
        print("- none")
    print(f"\nRound {'passes' if passed else 'fails'}.")


if __name__ == "__main__":
    main(sys.argv[1])
