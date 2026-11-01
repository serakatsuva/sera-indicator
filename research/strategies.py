"""Family playbooks measured on real Deriv history (H1), win rate vs reward:risk, train (70 %) / test (30 %).
Usage: python3 research/strategies.py research/deriv-history.json.gz"""
import gzip, json, sys, math
from collections import defaultdict
import numpy as np

d = json.load(gzip.open(sys.argv[1] if len(sys.argv) > 1 else "research/deriv-history.json.gz"))

def fam(n):
    n = n.lower()
    for k in ("boom", "crash", "jump", "step", "range break", "basket"):
        if k in n: return k.replace(" ", "_")
    if "bull" in n or "bear" in n: return "bullbear"
    if "volatility" in n: return "vol1s" if "(1s)" in n else "vol"
    return "other"

def ema(x, p):
    a = 2 / (p + 1); out = np.empty_like(x); out[0] = x[0]
    for i in range(1, len(x)): out[i] = a * x[i] + (1 - a) * out[i - 1]
    return out

def atr(h, l, c, p=14):
    tr = np.maximum(h[1:] - l[1:], np.maximum(abs(h[1:] - c[:-1]), abs(l[1:] - c[:-1])))
    tr = np.concatenate([[h[0] - l[0]], tr]); out = np.empty_like(tr); out[0] = tr[0]
    for i in range(1, len(tr)): out[i] = (out[i - 1] * (p - 1) + tr[i]) / p
    return out

def rsi(c, p=14):
    dlt = np.diff(c, prepend=c[0]); up = np.where(dlt > 0, dlt, 0); dn = np.where(dlt < 0, -dlt, 0)
    au = np.empty_like(c); ad = np.empty_like(c); au[0] = ad[0] = 1e-9
    for i in range(1, len(c)): au[i] = (au[i-1]*(p-1)+up[i])/p; ad[i] = (ad[i-1]*(p-1)+dn[i])/p
    return 100 - 100 / (1 + au / np.maximum(ad, 1e-12))

RRS = [0.2, 0.35, 0.5, 1.0, 1.5, 2.0, 3.0]

def simulate(o, h, l, c, i, side, sl_dist, maxhold=240):
    """returns dict rr->result in R (+rr win, -1 loss, else mark-to-market at timeout); stop checked first."""
    entry = c[i]; res = {}
    for rr in RRS:
        tp = entry + side * rr * sl_dist; sl = entry - side * sl_dist; r = None
        for j in range(i + 1, min(len(c), i + 1 + maxhold)):
            adv = l[j] if side > 0 else h[j]; fav = h[j] if side > 0 else l[j]
            if (adv <= sl) if side > 0 else (adv >= sl): r = -1.0; break
            if (fav >= tp) if side > 0 else (fav <= tp): r = rr; break
        if r is None:
            j = min(len(c) - 1, i + maxhold)
            if j >= len(c) - 1 and i + maxhold >= len(c): return None
            r = side * (c[j] - entry) / sl_dist
        res[rr] = r
    return res

def signals(name, o, h, l, c):
    f = fam(name); e20, e50, e200 = ema(c, 20), ema(c, 50), ema(c, 200); a = atr(h, l, c); r = rsi(c)
    rng = h - l; out = []
    for i in range(210, len(c) - 1):
        up = e20[i] > e50[i] > e200[i]; dn = e20[i] < e50[i] < e200[i]
        hh = h[i-20:i].max(); ll = l[i-20:i].min()
        # 1. trend pullback (classic)
        if up and l[i] <= e20[i] and c[i] > e20[i] and c[i] > o[i]: out.append(("trend_pullback", i, 1, 1.5 * a[i]))
        if dn and h[i] >= e20[i] and c[i] < e20[i] and c[i] < o[i]: out.append(("trend_pullback", i, -1, 1.5 * a[i]))
        # 2. SMC break of structure + order-block retest: break of the 20-bar high, then first pullback to the broken level
        if up and c[i-1] > hh and l[i] <= h[i-21:i-1].max() and c[i] > o[i]: out.append(("smc_bos_retest", i, 1, 1.5 * a[i]))
        if dn and c[i-1] < ll and h[i] >= l[i-21:i-1].min() and c[i] < o[i]: out.append(("smc_bos_retest", i, -1, 1.5 * a[i]))
        # 3. liquidity sweep + reversal (SMC): wick through the 20-bar extreme, close back inside
        if l[i] < ll and c[i] > ll and c[i] > o[i]: out.append(("smc_sweep", i, 1, max(c[i] - l[i], 0.5 * a[i])))
        if h[i] > hh and c[i] < hh and c[i] < o[i]: out.append(("smc_sweep", i, -1, max(h[i] - c[i], 0.5 * a[i])))
        # 4. RSI mean reversion
        if r[i] < 25: out.append(("rsi_revert", i, 1, 1.5 * a[i]))
        if r[i] > 75: out.append(("rsi_revert", i, -1, 1.5 * a[i]))
        # 5. Boom / Crash: ride the drift right after a spike (Boom SELL after an up spike, Crash BUY after a down spike)
        if f == "boom" and rng[i] > 3 * a[i-1] and c[i] > o[i]: out.append(("spike_drift", i, -1, 1.0 * a[i-1]))
        if f == "crash" and rng[i] > 3 * a[i-1] and c[i] < o[i]: out.append(("spike_drift", i, 1, 1.0 * a[i-1]))
        # 6. Boom / Crash: always with the drift, trend filter
        if f == "boom" and dn and i % 6 == 0: out.append(("drift_trend", i, -1, 1.0 * a[i]))
        if f == "crash" and up and i % 6 == 0: out.append(("drift_trend", i, 1, 1.0 * a[i]))
    return out

rows = defaultdict(list)
for m in d["markets"]:
    H = np.array(m["H1"], dtype=float)
    if len(H) < 1500: continue
    t, o, h, l, c = H.T
    split = t[int(len(t) * 0.7)]
    last = -99
    for strat, i, side, sl in signals(m["name"], o, h, l, c):
        res = simulate(o, h, l, c, i, side, sl)
        if res is None or sl <= 0: continue
        rows[(fam(m["name"]), strat, "train" if t[i] < split else "test")].append(res)

print(f"{'family':10} {'strategy':15} {'set':5} {'n':>5}  " + "  ".join(f"RR{rr:<4} win% expR" for rr in RRS))
summary = []
for (f, s, part), lst in sorted(rows.items()):
    if len(lst) < 20: continue
    cells = []
    for rr in RRS:
        v = np.array([x[rr] for x in lst]); win = (v > 0).mean() * 100; cells.append(f"{win:5.0f}% {v.mean():+.2f}")
        summary.append(dict(family=f, strategy=s, part=part, rr=rr, n=len(v), win=round(win, 1), exp=round(float(v.mean()), 3)))
    print(f"{f:10} {s:15} {part:5} {len(lst):5}  " + "  ".join(cells))
json.dump(summary, open("research/strategies_summary.json", "w"))
