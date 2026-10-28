"""Answer key for tools/repaint_report.py (written by the controller; do not edit).

Run:  python -B tests/test_repaint_report.py   (from the repo root)
Expected last line:  SUMMARY 10/10
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from repaint_report import analyse  # noqa: E402

# 10 bars, M15, 2026.01.01 00:00 .. 02:15
T = ["2026.01.01 %02d:%02d" % (m // 60, m % 60) for m in range(0, 150, 15)]

# final.csv rows: (bar_time, buffer, value)
FINAL = []
for i, t in enumerate(T):
    FINAL.append((t, "0", "100.5" if i == 2 else ("300.0" if i == 7 else "EMPTY")))
for i, t in enumerate(T):
    FINAL.append((t, "4", ["0", "0", "0", "0", "1", "1", "1", "-1", "-1", "-1"][i]))

# live.csv rows: (observed_at, bar_time, buffer, value)
# Observation pattern: at each closed bar t[j] (j = 3..9) the EA re-reads bars j-1, j-2, j-3.
LIVE = []


def obs(j, k, buf, val):
    LIVE.append((T[j], T[j - k], buf, val))


for j in range(3, 10):
    for k in (1, 2, 3):
        i = j - k
        # buffer 0: pivot at T2 appears late at observation T5 (lag 3) -> late fill, no repaint
        if i == 2:
            v = "100.5" if j >= 5 else "EMPTY"
        # buffer 0: cell T6 appears at T8 (lag 2) then is removed at T9 -> repaint
        elif i == 6:
            v = {7: "EMPTY", 8: "200.0", 9: "EMPTY"}[j]
        # buffer 0: cell T7 never fills while observed, but final says 300.0 -> final mismatch
        else:
            v = "EMPTY"
        obs(j, k, "0", v)
        # buffer 4: stable copy of final, except cell T4 observed 0 at T5 then 1 afterwards -> repaint (numeric change)
        fv = ["0", "0", "0", "0", "1", "1", "1", "-1", "-1", "-1"][i]
        if i == 4 and j == 5:
            fv = "0"
        obs(j, k, "4", fv)

# an NA row must be ignored entirely
LIVE.append((T[9], T[8], "0", "NA"))

RESULTS = []


def check(name, actual, expected):
    ok = actual == expected
    RESULTS.append(ok)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  expected=%r actual=%r" % (expected, actual)))


res = analyse(LIVE, FINAL)
b0 = res["0"]
b4 = res["4"]

check("buffers present", sorted(res.keys()), ["0", "4"])
check("b0 cells_observed", b0["cells_observed"], 9)
check("b0 late_fill_cells", b0["late_fill_cells"], 2)
check("b0 lag min/median/max", (b0["lag_min"], b0["lag_median"], b0["lag_max"]), (2, 2.5, 3))
check("b0 repaint_cells", b0["repaint_cells"], 1)
check("b0 final_mismatch_cells", b0["final_mismatch_cells"], 1)
check("b0 verdict", b0["verdict"], "REPAINTS")
check("b4 cells_observed / late_fill", (b4["cells_observed"], b4["late_fill_cells"]), (9, 0))
check("b4 repaint / mismatch", (b4["repaint_cells"], b4["final_mismatch_cells"]), (1, 0))
check("b4 verdict", b4["verdict"], "REPAINTS")

print("SUMMARY %d/%d" % (sum(RESULTS), len(RESULTS)))
