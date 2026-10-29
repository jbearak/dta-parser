"""Score tables for one judging round, from the judges' JSON blocks.

    python docs/judging/scores.py docs/judging/round-N
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bundle import COMMON  # noqa: E402


def scores(path):
    text = open(path, encoding="utf-8").read()
    return json.loads(re.search(r"```json\s*(\{.*?\})\s*```", text, re.S).group(1))


def main(round_dir):
    pairs = json.load(open(os.path.join(round_dir, "pairs.json")))["pairs"]
    passed = True
    print("| judge | pair | ours | competitor | lowest common task of ours | pass |")
    print("|---|---|---|---|---|---|")
    for judge in ("sonnet", "terra"):
        for p in pairs:
            s = scores(os.path.join(round_dir, "responses", f"{judge}-{p['prompt']}"))
            ours, theirs = s[p["ours"]], s["B" if p["ours"] == "A" else "A"]
            common = [str(t) for t in COMMON[p["language"]]]
            mean = lambda t, lib: sum(lib[t]) / 4  # noqa: E731
            ours_total = sum(mean(t, ours) for t in common)
            their_total = sum(mean(t, theirs) for t in common)
            low = min(common, key=lambda t: mean(t, ours))
            ok = ours_total > their_total and mean(low, ours) >= 2
            passed &= ok
            print(f"| {judge} | {p['language']}: {p['competitor']} | {ours_total:.2f} | {their_total:.2f} "
                  f"| {low}: {mean(low, ours):.2f} | {'yes' if ok else 'no'} |")
    print(f"\nRound {'passes' if passed else 'fails'}.")


if __name__ == "__main__":
    main(sys.argv[1])
