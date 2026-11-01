"""Full SMC entry model measured on real Deriv history.
BUY (SELL mirrored):
  1. liquidity sweep: candle k takes out the lowest low of the previous L candles and closes back above it;
  2. CHoCH: within W candles after the sweep, a close above the highest high between the sweep and the
     L-candle base end (the last lower high) -> market structure shift;
  3. entry: limit at the 50 % of the impulse leg (sweep low -> CHoCH high) = discount zone / FVG-OB area,
     must fill within F candles after the CHoCH, otherwise cancelled;
  4. stop: sweep low - 0.1 ATR; targets: fixed R (0.5, 1, 2) and "opposite liquidity" (highest high of the base).
Variants: all directions / only the generator drift direction. Train = first 70 % of time, test = last 30 %.
Usage: python3 research/smc_model.py [H1|M15]"""
import gzip, json, sys
import numpy as np
TF = sys.argv[1] if len(sys.argv) > 1 else "H1"
d = json.load(gzip.open("research/deriv-history.json.gz"))
L, W, F, MAXHOLD = 20, 10, 10, (240 if TF == "H1" else 96)

def fam(n):
    n = n.lower()
    for k in ("boom", "crash", "jump", "step", "range break", "basket"):
        if k in n: return k.replace(" ", "_")
    if "bull" in n or "bear" in n: return "bullbear"
    if "volatility" in n: return "vol1s" if "(1s)" in n else "vol"
    return "other"

def drift(n):
    n = n.lower()
    return -1 if ("boom" in n or "bear" in n) else 1 if ("crash" in n or "bull" in n) else 0

def atr(h, l, c, p=14):
    tr = np.maximum(h[1:] - l[1:], np.maximum(abs(h[1:] - c[:-1]), abs(l[1:] - c[:-1])))
    tr = np.concatenate([[h[0] - l[0]], tr]); out = np.empty_like(tr); out[0] = tr[0]
    for i in range(1, len(tr)): out[i] = (out[i - 1] * (p - 1) + tr[i]) / p
    return out

def outcome(h, l, c, j0, side, entry, stop, targets):
    risk = abs(entry - stop); res = {}
    # Fill candle: the order of its high/low is unknown -> only the stop can be hit there (conservative);
    # targets are checked from the next candle.
    if (l[j0] <= stop) if side > 0 else (h[j0] >= stop):
        return {name: -1.0 for name in targets}
    for name, tp in targets.items():
        r = None
        for j in range(j0 + 1, min(len(c), j0 + MAXHOLD)):
            adv = l[j] if side > 0 else h[j]; fav = h[j] if side > 0 else l[j]
            if (adv <= stop) if side > 0 else (adv >= stop): r = -1.0; break
            if (fav >= tp) if side > 0 else (fav <= tp): r = abs(tp - entry) / risk; break
        if r is None:
            if j0 + MAXHOLD >= len(c): return None
            r = side * (c[j0 + MAXHOLD - 1] - entry) / risk
        res[name] = r
    return res

rows = []
for m in d["markets"]:
    H = np.array(m[TF], dtype=float)
    if len(H) < 600: continue
    t, o, h, l, c = H.T; a = atr(h, l, c); dr = drift(m["name"]); f = fam(m["name"])
    split = t[int(len(t) * 0.7)]; busy = 0
    for k in range(L + 20, len(c) - W - F - 2):
        if k < busy: continue
        for side in (1, -1):
            base_lo = l[k - L:k].min(); base_hi = h[k - L:k].max()
            swept = (l[k] < base_lo and c[k] > base_lo) if side > 0 else (h[k] > base_hi and c[k] < base_hi)
            if not swept: continue
            # structure level to break: last swing (highest high / lowest low) of the 5 candles before the sweep
            lvl = h[k - 5:k + 1].max() if side > 0 else l[k - 5:k + 1].min()
            choch = None
            for j in range(k + 1, k + 1 + W):
                if (c[j] > lvl) if side > 0 else (c[j] < lvl): choch = j; break
            if choch is None: continue
            ext = l[k] if side > 0 else h[k]                       # sweep extreme
            leg_end = h[k:choch + 1].max() if side > 0 else l[k:choch + 1].min()
            entry = (ext + leg_end) / 2                              # 50 % of the impulse leg (discount / premium)
            stop = ext - side * 0.1 * a[k]
            risk = abs(entry - stop)
            if risk <= 0: continue
            fill = None
            for j in range(choch + 1, choch + 1 + F):
                if (l[j] <= entry) if side > 0 else (h[j] >= entry): fill = j; break
                if (h[j] >= entry + side * 3 * risk) if side > 0 else (l[j] <= entry + side * 3 * risk): break
            if fill is None: continue
            opp = base_hi if side > 0 else base_lo
            targets = {"0.5R": entry + side * 0.5 * risk, "1R": entry + side * risk, "2R": entry + side * 2 * risk,
                       "liq": opp if side * (opp - entry) > 0.3 * risk else entry + side * risk}
            # the fill candle itself may also hit the stop: check from the fill candle (stop first)
            res = outcome(h, l, c, fill, side, entry, stop, targets)
            if res is None: continue
            rows.append(dict(f=f, drift_ok=(dr == 0 and None) or (side == dr), side=side, part="train" if t[k] < split else "test", **res))
            busy = fill + 1
print(f"SMC sweep -> CHoCH -> 50 % retrace ({TF}), {len(rows)} trades")
print(f"{'famille':11} {'filtre':14} {'part':5} {'n':>5}  " + "  ".join(f"{x:>14}" for x in ("0.5R", "1R", "2R", "liq. opposee")))
def line(f, filt, part, lst):
    if len(lst) < 15: return
    cells = []
    for key in ("0.5R", "1R", "2R", "liq"):
        v = np.array([x[key] for x in lst]); cells.append(f"{(v > 0).mean() * 100:5.0f}% {v.mean():+.2f}R")
    print(f"{f:11} {filt:14} {part:5} {len(lst):5}  " + "  ".join(f"{x:>14}" for x in cells))
for f in sorted({r["f"] for r in rows}):
    for filt, cond in (("tous", lambda r: True), ("sens derive", lambda r: r["drift_ok"] is True), ("contre derive", lambda r: r["drift_ok"] is False)):
        for part in ("train", "test"):
            line(f, filt, part, [r for r in rows if r["f"] == f and r["part"] == part and cond(r)])
