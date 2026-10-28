"""Repaint / late-fill / final-mismatch report for SwingStructure audit logs (WO-4).

CLI: python tools/repaint_report.py --live <live.csv> --final <final.csv> [--out report.md]
Python 3.10+, standard library only.
"""
import argparse
import bisect
import csv
import statistics
import sys

EMPTY = "EMPTY"
NA = "NA"


def normalise(v):
    if v == EMPTY:
        return EMPTY
    return format(float(v), ".10g")


def analyse(live_rows, final_rows):
    live = [(o, b, buf, v) for (o, b, buf, v) in live_rows if v != NA]
    final = [(b, buf, v) for (b, buf, v) in final_rows if v != NA]

    times = sorted({b for (b, _buf, _v) in final})
    pos = {t: i for i, t in enumerate(times)}

    def position(t):
        if t in pos:
            return pos[t]
        return bisect.bisect_left(times, t)

    final_map = {}
    for b, buf, v in final:
        final_map[(b, buf)] = normalise(v)

    cells = {}
    for o, b, buf, v in live:
        cells.setdefault((b, buf), []).append((o, normalise(v)))
    for obs in cells.values():
        obs.sort(key=lambda x: x[0])

    buffers = sorted({buf for (_b, buf) in cells})
    result = {}
    for buf in buffers:
        cell_keys = [k for k in cells if k[1] == buf]
        cells_observed = len(cell_keys)
        lags = []
        repaint_cells = 0
        final_mismatch_cells = 0
        for key in cell_keys:
            bar_time, _ = key
            obs = cells[key]

            # late fill: first observation EMPTY, a later one non-EMPTY
            if obs[0][1] == EMPTY:
                for o, v in obs[1:]:
                    if v != EMPTY:
                        lags.append(position(o) - position(bar_time))
                        break

            # repaint: non-EMPTY followed by a different value
            for i in range(1, len(obs)):
                prev = obs[i - 1][1]
                cur = obs[i][1]
                if prev != EMPTY and cur != prev:
                    repaint_cells += 1
                    break

            # final mismatch: last observed value vs final value
            if key not in final_map:
                final_mismatch_cells += 1
            elif obs[-1][1] != final_map[key]:
                final_mismatch_cells += 1

        if lags:
            lag_min = int(min(lags))
            lag_median = statistics.median(lags)
            lag_max = int(max(lags))
        else:
            lag_min = None
            lag_median = None
            lag_max = None

        verdict = "OK" if repaint_cells == 0 and final_mismatch_cells == 0 else "REPAINTS"
        result[buf] = {
            "cells_observed": cells_observed,
            "late_fill_cells": len(lags),
            "lag_min": lag_min,
            "lag_median": lag_median,
            "lag_max": lag_max,
            "repaint_cells": repaint_cells,
            "final_mismatch_cells": final_mismatch_cells,
            "verdict": verdict,
        }
    return result


def render(result):
    header = ("| buffer | cells_observed | late_fill_cells | lag_min | lag_median | lag_max "
              "| repaint_cells | final_mismatch_cells | verdict |")
    sep = "|" + "---|" * 9
    lines = [header, sep]
    for buf in sorted(result.keys(), key=lambda s: int(s)):
        m = result[buf]
        if m["late_fill_cells"] == 0:
            lmin = lmed = lmax = "-"
        else:
            lmin = str(m["lag_min"])
            lmed = format(m["lag_median"], "g")
            lmax = str(m["lag_max"])
        lines.append("| %s | %d | %d | %s | %s | %s | %d | %d | %s |" % (
            buf, m["cells_observed"], m["late_fill_cells"], lmin, lmed, lmax,
            m["repaint_cells"], m["final_mismatch_cells"], m["verdict"]))
    bad = sum(1 for m in result.values() if m["verdict"] != "OK")
    if bad == 0:
        lines.append("OVERALL: OK")
    else:
        lines.append("OVERALL: REPAINTS (%d buffers)" % bad)
    return "\n".join(lines) + "\n"


def read_live(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return [(r["observed_at"], r["bar_time"], r["buffer"], r["value"])
                for r in csv.DictReader(f)]


def read_final(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        return [(r["bar_time"], r["buffer"], r["value"]) for r in csv.DictReader(f)]


def main(argv=None):
    p = argparse.ArgumentParser(description="Repaint report for SwingStructure audit")
    p.add_argument("--live", required=True)
    p.add_argument("--final", required=True)
    p.add_argument("--out")
    args = p.parse_args(argv)

    result = analyse(read_live(args.live), read_final(args.final))
    text = render(result)
    sys.stdout.write(text)
    if args.out:
        with open(args.out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
