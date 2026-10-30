"""SVG charts for bench/RESULTS.md: one per dataset family, a panel per
language, a row per task, and a bar per other reader showing its time over
ours (geometric mean over the family's files) on a log scale. Bars right
of 1× mean ours is faster."""

import math
from html import escape

TASK_NAMES = {1: "full read", 2: "read + pass", 3: "5 columns", 4: "1,000 rows", 5: "metadata", 6: "write"}
# Categorical slots 1 and 2 of the reference palette, light and dark.
SERIES = [("#2a78d6", "#3987e5"), ("#eb6834", "#d95926")]
LO, HI = 0.01, 10000.0

STYLE = """
svg { font-family: -apple-system, system-ui, sans-serif; }
.bg { fill: #fcfcfb; } .t { fill: #0b0b0b; } .t2 { fill: #52514e; }
.grid { stroke: #e4e3df; stroke-width: 1; } .one { stroke: #52514e; stroke-width: 1.5; }
.s0 { fill: #2a78d6; } .s1 { fill: #eb6834; }
@media (prefers-color-scheme: dark) {
  .bg { fill: #1a1a19; } .t { fill: #f0efec; } .t2 { fill: #c3c2b7; }
  .grid { stroke: #3a3a37; } .one { stroke: #c3c2b7; }
  .s0 { fill: #3987e5; } .s1 { fill: #d95926; }
}
"""


def write(path, title, data, tasks=TASK_NAMES):
    """data: {language: {reader name: {task: ratio or None}}}; one row per
    task in `tasks`."""
    left, width, bar, gap = 120, 600, 7, 2
    row = 2 * bar + gap + 10
    panel = len(tasks) * row + 56
    height = 50 + panel * len(data) + 20
    total = left + width + 70

    def x(r):
        r = min(max(r, LO), HI)
        return left + width * (math.log10(r) - math.log10(LO)) / (math.log10(HI) - math.log10(LO))

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{total}" height="{height}" '
           f'viewBox="0 0 {total} {height}" role="img" aria-label="{escape(title)}: time of each reader over ours">',
           f"<style>{STYLE}</style>", f'<rect class="bg" width="{total}" height="{height}"/>',
           f'<text class="t" x="12" y="24" font-size="15" font-weight="600">{escape(title)}: other readers\' time '
           f"over ours (geometric mean; right of 1× = ours faster)</text>"]
    y0 = 50
    for lang, readers in data.items():
        names = list(readers)
        out.append(f'<text class="t" x="12" y="{y0 + 12}" font-size="13" font-weight="600">{escape(lang)}</text>')
        # Legend: a swatch and the reader's name.
        lx = left
        for k, name in enumerate(names):
            out.append(f'<rect class="s{k}" x="{lx}" y="{y0 + 3}" width="10" height="10" rx="2"/>')
            out.append(f'<text class="t2" x="{lx + 14}" y="{y0 + 12}" font-size="12">{escape(name)}</text>')
            lx += 24 + 7 * len(name)
        top = y0 + 24
        for tick in (0.01, 0.1, 1, 10, 100, 1000, 10000):
            out.append(f'<line class="{"one" if tick == 1 else "grid"}" x1="{x(tick):.1f}" x2="{x(tick):.1f}" '
                       f'y1="{top - 4}" y2="{top + len(tasks) * row}"/>')
            out.append(f'<text class="t2" x="{x(tick):.1f}" y="{top + len(tasks) * row + 14}" font-size="11" '
                       f'text-anchor="middle">{tick:g}×</text>')
        for i, task in enumerate(tasks):
            task_name = TASK_NAMES[task]
            ty = top + i * row
            out.append(f'<text class="t2" x="{left - 8}" y="{ty + bar + 4}" font-size="12" '
                       f'text-anchor="end">{task}. {task_name}</text>')
            for k, name in enumerate(names):
                r = readers[name].get(task)
                by = ty + k * (bar + gap)
                if r is None:
                    out.append(f'<text class="t2" x="{x(1) + 4:.1f}" y="{by + bar}" font-size="10">'
                               f"{escape(name)}: none</text>")
                    continue
                a, b = sorted((x(1), x(r)))
                out.append(f'<rect class="s{k}" x="{a:.1f}" y="{by}" width="{max(b - a, 1.5):.1f}" height="{bar}" rx="2">'
                           f"<title>{escape(lang)}, {escape(name)}, task {task}: {r:.3g}× ours</title></rect>")
                label = f"{r:.2g}×" if r < 100 else f"{r:,.0f}×"
                tx, anchor = (b + 4, "start") if r >= 1 else (a - 4, "end")
                out.append(f'<text class="t" x="{tx:.1f}" y="{by + bar}" font-size="10" text-anchor="{anchor}">{label}</text>')
        y0 += panel
    out.append("</svg>")
    path.write_text("\n".join(out) + "\n")
