# mt5-swing-structure-audit

A small, honest swing/structure indicator for MetaTrader 5, plus the test harness that proves it does not repaint.

The point of this repo is not the indicator. It is the **audit method**: log what an indicator showed at every bar close during a Strategy Tester run, compare that with what the same indicator shows for those bars after the run, and count every cell that changed. A repainting indicator cannot pass this test. A deliberately broken copy of the same indicator is included to show the harness catching it.

## Why this matters

Most reversal and swing indicators look excellent on a chart because they are allowed to rewrite the past: a pivot is drawn, the market moves, the pivot quietly moves or disappears. A backtest built on such an indicator reports signals that no live trader ever saw. Before improving any reversal logic, you first have to know whether the values you are looking at are the values that existed at the time.

## What is in the repo

| Path | What it is |
|---|---|
| `MQL5/Indicators/SwingStructure.mq5` | Non-repainting swing high/low + market-structure indicator (reversal arrows on change of character). |
| `MQL5/Indicators/SwingStructure_RepaintDemo.mq5` | The same indicator with three deliberate defects. **Negative control. Do not trade with it.** |
| `MQL5/Experts/RepaintAuditEA.mq5` | Logger run in the Strategy Tester. No trading. Writes two CSVs: what was visible at each bar close, and the final state. |
| `tools/repaint_report.py` | Compares the two CSVs and prints a per-buffer repaint report. Standard library only. |
| `tests/test_repaint_report.py` | Fixed answer key for the report tool (synthetic data with known lag, repaint and mismatch cases). |
| `results/` | Reports from the runs below. |

## The indicator in one paragraph

A swing high at bar `p` needs `S` lower highs on each side (`InpStrength`, default 3). It can therefore only be confirmed at bar `p+S`, and the dot is drawn at `p` once that bar has closed, never earlier and never moved afterwards. A **reversal up** arrow is written on the closed bar whose close exceeds the last confirmed swing high while structure was bearish (a change of character); mirror for reversal down. Breaks in the direction of the current structure are continuation and get no arrow. The `Structure` buffer (+1 / −1 / 0) and the dotted last-swing lines are written for every closed bar.

Four rules make it non-repainting, and they are stated at the top of the source:
1. Values are written only to closed bars. The forming bar is always empty.
2. A value, once written, is never rewritten.
3. Confirmation and break detection use only data up to the bar being written.
4. Incremental calculation starts at `prev_calculated − 1`, so each closed bar is processed exactly once; a full recompute happens only on history reload and resets the state.

The price you pay for this is lag: a pivot appears `S` bars after the fact. The audit measures that lag instead of hiding it.

## The audit method

1. `RepaintAuditEA` loads the indicator through `iCustom` and runs in the Strategy Tester on real ticks.
2. At every new bar it re-reads the last `InpLookback` closed bars (default 6) for buffers 0..4 and appends `observed_at, bar_time, buffer, value` to a live CSV.
3. When the test ends it dumps the final value of every bar and buffer to a second CSV.
4. `repaint_report.py` groups observations per cell `(bar_time, buffer)` and counts:
   - **late fill**: the cell was empty when first seen and got a value later. Expected for confirmed pivots; reported as `lag` in bars.
   - **repaint**: a non-empty value changed, or was removed, between two observations. Never acceptable.
   - **final mismatch**: the last value seen live differs from the value after the run. Never acceptable.
5. Verdict per buffer is `OK` only when repaint and final-mismatch counts are both zero.

Buffers: 0 swing high, 1 swing low, 2 reversal-up arrow, 3 reversal-down arrow, 4 structure state.

## Results

Run: XAUUSD.v M15, 2026-04-01 to 2026-10-27, InterStellar Financial server data, "every tick based on real ticks" (real ticks available from 2026-08-04, M1-generated before that). 13,566 bars, 37.8 M ticks, 406,900 live observations.

### SwingStructure (honest)

| buffer | cells_observed | late_fill_cells | lag_min | lag_median | lag_max | repaint_cells | final_mismatch_cells | verdict |
|---|---|---|---|---|---|---|---|---|
| 0 | 13566 | 1300 | 3 | 3 | 3 | 0 | 0 | OK |
| 1 | 13566 | 1282 | 3 | 3 | 3 | 0 | 0 | OK |
| 2 | 13566 | 0 | - | - | - | 0 | 0 | OK |
| 3 | 13566 | 0 | - | - | - | 0 | 0 | OK |
| 4 | 13566 | 0 | - | - | - | 0 | 0 | OK |

OVERALL: OK

Reading it: 1,300 swing highs and 1,282 swing lows were confirmed, every one of them exactly 3 bars after the pivot (the configured `InpStrength`), none moved or vanished, and the arrows and structure state were final at bar close.

### SwingStructure_RepaintDemo (negative control)

Same data, same harness, same `InpStrength=3`. The only difference is the indicator file.

| buffer | cells_observed | late_fill_cells | lag_min | lag_median | lag_max | repaint_cells | final_mismatch_cells | verdict |
|---|---|---|---|---|---|---|---|---|
| 0 | 13566 | 1532 | 2 | 2 | 2 | 232 | 0 | REPAINTS |
| 1 | 13566 | 1510 | 2 | 2 | 2 | 228 | 0 | REPAINTS |
| 2 | 13566 | 0 | - | - | - | 0 | 0 | OK |
| 3 | 13566 | 0 | - | - | - | 0 | 0 | OK |
| 4 | 13566 | 0 | - | - | - | 0 | 0 | OK |

OVERALL: REPAINTS (2 buffers)

Reading it: the broken copy confirms pivots one bar early (lag 2 instead of 3) because it is allowed to look at the forming bar. About 15% of those early pivots (232 of 1,532 highs, 228 of 1,510 lows) were later erased when the forming bar moved past them. On a chart this looks like a slightly faster indicator; in the audit it is 460 signals that never existed. The signal and structure buffers of the demo happen to pass at bar-close sampling because their intrabar flicker lives on the forming bar, which the harness does not observe; see Limitations.

## How to run it yourself

1. Copy the two indicators to `MQL5/Indicators/` and the EA to `MQL5/Experts/` of your terminal's data folder and compile them (MetaEditor, or `MetaEditor64.exe /compile:<file> /log:<log>`).
2. Strategy Tester: Expert `RepaintAuditEA`, your gold symbol, M15, "Every tick based on real ticks", inputs `InpIndicatorName=SwingStructure`, `InpTag=_honest`. Run. Repeat with `SwingStructure_RepaintDemo` and `InpTag=_demo`.
3. The CSVs are written to the **common** files folder (`%APPDATA%\MetaQuotes\Terminal\Common\Files`). Then:

```
python tools/repaint_report.py --live repaint_live_SwingStructure_honest.csv --final repaint_final_SwingStructure_honest.csv --out report_honest.md
python -B tests/test_repaint_report.py      # answer key for the tool itself, expects SUMMARY 10/10
```

A headless run works too: a `[Tester]` section in an `.ini` passed as `terminal64.exe /config:file.ini` with `ShutdownTerminal=1`.

## Limitations

- Ties are not pivots (strict `>` / `<` on both sides). Change `IsSwingHigh/IsSwingLow` if you want `>=` on one side.
- If a bar breaks both the last swing high and the last swing low, the high break is evaluated first. Rare on M15 gold, documented rather than hidden.
- "Last swing" means the most recently confirmed one, even if it is lower (for highs) than the previous unbroken swing. That is a design choice for change-of-character detection, not a bug, and it is easy to change.
- The harness samples at bar close only. It proves the closed-bar values are stable; it does not measure intrabar flicker on the forming bar, which this indicator avoids by never writing to it.
- The first observation of the run can read the indicator before its first calculation (one cell per arrow buffer shows `0.00` instead of empty at the very first bar). It does not affect the counts.
- Tester data quality is the broker's. Real ticks on this server start 2026-08-04; earlier bars are generated from M1.

## License

MIT, see `LICENSE`.
