"""Render XAUUSD.v M15 candles with SwingStructure buffers from the Strategy Tester CSV.
Read-only use of the MetaTrader5 API (copy_rates_range only)."""
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd
import MetaTrader5 as mt5
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from matplotlib.lines import Line2D

ROOT = Path(r"D:\Claude\Freelance\_Assets\Showcase\Code\mt5-swing-structure-audit")
IND_CSV = ROOT / "results" / "repaint_final_SwingStructure_honest.csv"
RATES_CSV = ROOT / "results" / "xauusd_v_m15_window.csv"
OUT_PNG = Path(r"D:\Claude\Freelance\_Assets\Portfolio\shots\swing_chart_rendered.png")
SYMBOL = "XAUUSD.v"
BG, FG = "#0b0e11", "#9aa4b2"
UP, DN = "#26a69a", "#ef5350"
WIN = 220

# ---- (a)(b) read rates
if not mt5.initialize(path=r"C:\Program Files\InterStellar MT5-1\terminal64.exe", timeout=90000):
    print("initialize failed:", mt5.last_error())
    sys.exit(1)
mt5.symbol_select(SYMBOL, True)
rates = mt5.copy_rates_range(SYMBOL, mt5.TIMEFRAME_M15, datetime(2026, 9, 1), datetime(2026, 10, 27))
err = mt5.last_error()
mt5.shutdown()
if rates is None or len(rates) == 0:
    print("rates empty:", err)
    sys.exit(1)
r = pd.DataFrame(rates)
r["time"] = pd.to_datetime(r["time"], unit="s")
r = r[["time", "open", "high", "low", "close"]]
r.to_csv(RATES_CSV, index=False)
print("rates rows:", len(r), r["time"].min(), "->", r["time"].max())

# ---- (c) indicator pivot + join
ind = pd.read_csv(IND_CSV)
ind["value"] = pd.to_numeric(ind["value"], errors="coerce")
ind["time"] = pd.to_datetime(ind["bar_time"], format="%Y.%m.%d %H:%M")
pv = ind.pivot_table(index="time", columns="buffer", values="value", aggfunc="first")
pv.columns = [f"b{c}" for c in pv.columns]
pv = pv.reset_index()
df = r.merge(pv, on="time", how="inner").sort_values("time").reset_index(drop=True)
print("joined rows:", len(df))
if len(df) <= 1000:
    print("join too small")
    sys.exit(1)

# ---- (d) pick window
arrows = (df["b2"].notna() | df["b3"].notna()).astype(int).to_numpy()
cs = np.concatenate([[0], np.cumsum(arrows)])
best, best_i = -1, 0
for i in range(0, len(df) - WIN + 1):
    s = cs[i + WIN] - cs[i]
    if s >= best:
        best, best_i = s, i
w = df.iloc[best_i:best_i + WIN].reset_index(drop=True)
n_arrows = int(w["b2"].notna().sum() + w["b3"].notna().sum())
n_swings = int(w["b0"].notna().sum() + w["b1"].notna().sum())
t0, t1 = w["time"].iloc[0], w["time"].iloc[-1]
span = f"{t0:%Y-%m-%d %H:%M} to {t1:%Y-%m-%d %H:%M}"
print("window:", span, "| arrows:", n_arrows, "(buy", int(w["b2"].notna().sum()), "sell", int(w["b3"].notna().sum()), ") | swing dots:", n_swings,
      "(high", int(w["b0"].notna().sum()), "low", int(w["b1"].notna().sum()), ")")

# ---- (e) draw
x = np.arange(len(w))
fig, (ax, axs) = plt.subplots(2, 1, figsize=(14.4, 9), dpi=100, sharex=True,
                              gridspec_kw={"height_ratios": [88, 12], "hspace": 0.03})
fig.patch.set_facecolor(BG)
for a in (ax, axs):
    a.set_facecolor(BG)
    for sp in a.spines.values():
        sp.set_color("#2a313b")
    a.tick_params(colors=FG, labelsize=9)
    a.grid(True, color="#ffffff", alpha=0.06, lw=0.6)
ax.yaxis.tick_right()
axs.yaxis.tick_right()

o, h, l, c = (w[k].to_numpy() for k in ("open", "high", "low", "close"))
col = np.where(c >= o, UP, DN)
ax.vlines(x, l, h, colors=col, lw=1.0, zorder=2)
ax.bar(x, np.where(c >= o, c - o, o - c), bottom=np.minimum(o, c), width=0.7, color=col, zorder=3,
       linewidth=0)

# dashed levels
for i in range(len(w)):
    if pd.notna(w["b0"].iloc[i]):
        lvl = h[i]
        j = next((k for k in range(i + 1, len(w)) if c[k] > lvl), len(w) - 1)
        ax.hlines(lvl, i, j, colors="#ff5252", linestyles="--", lw=0.9, alpha=0.6, zorder=1)
    if pd.notna(w["b1"].iloc[i]):
        lvl = l[i]
        j = next((k for k in range(i + 1, len(w)) if c[k] < lvl), len(w) - 1)
        ax.hlines(lvl, i, j, colors="dodgerblue", linestyles="--", lw=0.9, alpha=0.6, zorder=1)

m0, m1, m2, m3 = (w[f"b{k}"].notna().to_numpy() for k in range(4))
ax.scatter(x[m0], w["b0"].to_numpy()[m0], s=36, c="#ff5252", marker="o", zorder=5, linewidths=0)
ax.scatter(x[m1], w["b1"].to_numpy()[m1], s=36, c="dodgerblue", marker="o", zorder=5, linewidths=0)
ax.scatter(x[m2], w["b2"].to_numpy()[m2], s=110, c="lime", marker="^", zorder=6, linewidths=0)
ax.scatter(x[m3], w["b3"].to_numpy()[m3], s=110, c="#ff8c00", marker="v", zorder=6, linewidths=0)

pad = (h.max() - l.min()) * 0.05
ax.set_ylim(l.min() - pad, h.max() + pad * 2.5)
ax.set_xlim(-1, len(w))

# structure band
st = w["b4"].fillna(0).to_numpy()
axs.fill_between(x, 0, 1, where=st > 0, step="mid", color="#26a69a", alpha=0.85, linewidth=0)
axs.fill_between(x, 0, 1, where=st < 0, step="mid", color="#ef5350", alpha=0.85, linewidth=0)
axs.set_ylim(0, 1)
axs.set_yticks([])
axs.set_ylabel("structure", color=FG, fontsize=9, rotation=270, labelpad=12)
axs.yaxis.set_label_position("right")

# x labels
ticks = np.linspace(0, len(w) - 1, 7).astype(int)
axs.set_xticks(ticks)
axs.set_xticklabels([f"{w['time'].iloc[t]:%m-%d %H:%M}" for t in ticks], color=FG)

# titles
fig.text(0.012, 0.975, f"SwingStructure (InpStrength=3) \u00b7 XAUUSD.v M15 \u00b7 {span}",
         color="white", fontsize=15, ha="left", va="top")
fig.text(0.012, 0.945,
         "Values are the indicator's own buffers as logged bar-by-bar in the MT5 Strategy Tester \u2014 "
         "dots = confirmed swing (3 bars late by design), arrows = change of character, no repaint",
         color=FG, fontsize=11, ha="left", va="top")

handles = [
    Line2D([], [], marker="o", ls="", color="#ff5252", markersize=6, label="Swing high"),
    Line2D([], [], marker="o", ls="", color="dodgerblue", markersize=6, label="Swing low"),
    Line2D([], [], marker="^", ls="", color="lime", markersize=9, label="Buy arrow"),
    Line2D([], [], marker="v", ls="", color="#ff8c00", markersize=9, label="Sell arrow"),
    Line2D([], [], ls="--", color="#ff5252", alpha=0.6, label="High level until close above"),
    Line2D([], [], ls="--", color="dodgerblue", alpha=0.6, label="Low level until close below"),
]
leg = ax.legend(handles=handles, loc="upper right", facecolor=BG, edgecolor="#2a313b", labelcolor=FG,
                fontsize=9, framealpha=0.9)

fig.subplots_adjust(left=0.04, right=0.94, top=0.88, bottom=0.07)
OUT_PNG.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(OUT_PNG, facecolor=BG, pad_inches=0.2)
print("saved:", OUT_PNG)
