"""Drift playbooks: trade only in the generator's drift direction (Boom SELL, Crash BUY, Bull BUY, Bear SELL),
entry after a pull-back against the drift, on H1. Prints win% / expectancy per RR, train/test and per month."""
import gzip, json, sys
import numpy as np
sys.argv=[sys.argv[0]]
exec(open('research/strategies.py').read().split('rows = defaultdict(list)')[0])
from collections import defaultdict
DRIFT={'boom':-1,'crash':1}
def drift_of(name):
    n=name.lower()
    if 'boom' in n: return -1
    if 'crash' in n: return 1
    if 'bull' in n: return 1
    if 'bear' in n: return -1
    return 0
res=defaultdict(list); months=defaultdict(list)
for m in d['markets']:
    side=drift_of(m['name'])
    if not side: continue
    H=np.array(m['H1'],dtype=float)
    if len(H)<1500: continue
    t,o,h,l,c=H.T; e20,e50,e200=ema(c,20),ema(c,50),ema(c,200); a=atr(h,l,c); r=rsi(c)
    split=t[int(len(t)*.7)]; nxt=0
    for i in range(210,len(c)-1):
        if i<nxt: continue
        trend=(e20[i]<e50[i]) if side<0 else (e20[i]>e50[i])
        for variant,ok in (('pullback_rsi',trend and (r[i]>55 if side<0 else r[i]<45)),
                           ('pullback_ema',trend and ((h[i]>=e20[i] and c[i]<e20[i]) if side<0 else (l[i]<=e20[i] and c[i]>e20[i])))):
            if not ok: continue
            x=simulate(o,h,l,c,i,side,1.5*a[i])
            if x is None: continue
            fam_=('boomcrash' if 'boom' in m['name'].lower() or 'crash' in m['name'].lower() else 'bullbear')
            res[(fam_,variant,'train' if t[i]<split else 'test')].append(x)
            months[(fam_,variant,int(t[i]//(86400*30.4)))].append(x)
for k,v in sorted(res.items()):
    print(k,len(v),'  '.join(f"RR{rr}:{np.mean([x[rr]>0 for x in v])*100:.0f}% {np.mean([x[rr] for x in v]):+.2f}" for rr in RRS))
for key in sorted({(k[0],k[1]) for k in months}):
    ms=[np.mean([x[1.5] for x in v]) for k,v in sorted(months.items()) if (k[0],k[1])==key and len(v)>=5]
    print(key,'mois positifs RR1.5:',sum(1 for x in ms if x>0),'/',len(ms))
