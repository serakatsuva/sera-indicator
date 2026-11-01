"""Drift playbook with the EA management: 50 % closed at TP1, stop to break-even, rest at the final target.
Reports: % of trades reaching TP1, % losing trades, expectancy in R; train/test; per month."""
import gzip, json, sys
import numpy as np
sys.argv=[sys.argv[0]]
exec(open('research/strategies.py').read().split('rows = defaultdict(list)')[0])
def drift_of(n):
    n=n.lower(); return -1 if ('boom' in n or 'bear' in n) else 1 if ('crash' in n or 'bull' in n) else 0
P={'bullbear':dict(rsi=40,slm=2.5,tp1=0.3,tpf=1.5,trend=False),
   'boomcrash':dict(rsi=45,slm=1.0,tp1=0.3,tpf=1.0,trend=True)}
def grp(n): n=n.lower(); return 'boomcrash' if ('boom' in n or 'crash' in n) else 'bullbear'
def trades(m,p):
    side=drift_of(m['name']); H=np.array(m['H1'],dtype=float); t,o,h,l,c=H.T
    e20,e50=ema(c,20),ema(c,50); a=atr(h,l,c); r=rsi(c); out=[]; i=210
    while i<len(c)-1:
        tr=(e20[i]<e50[i]) if side<0 else (e20[i]>e50[i])
        pull=(r[i]>100-p['rsi']) if side<0 else (r[i]<p['rsi'])
        if pull and (tr or not p['trend']):
            sl=p['slm']*a[i]; e=c[i]; st=e-side*sl; t1=e+side*p['tp1']*sl; tf=e+side*p['tpf']*sl; hit1=False; res=None
            for j in range(i+1,min(len(c),i+241)):
                adv=l[j] if side>0 else h[j]; fav=h[j] if side>0 else l[j]
                if (adv<=st) if side>0 else (adv>=st): res=(0.5*p['tp1'] if hit1 else -1.0); break
                if not hit1 and ((fav>=t1) if side>0 else (fav<=t1)): hit1=True; st=e
                if hit1 and ((fav>=tf) if side>0 else (fav<=tf)): res=0.5*p['tp1']+0.5*p['tpf']; break
            if res is None: break
            out.append((t[i],hit1,res)); i=j+1; continue
        i+=1
    return out
stats={}
for g,p in P.items():
    allt=sorted(sum((trades(m,p) for m in d['markets'] if drift_of(m['name']) and grp(m['name'])==g and len(m['H1'])>=1500),[]))
    ts=np.array([x[0] for x in allt]); split=np.quantile(ts,.7)
    for part,sel in (('train',ts<split),('test',ts>=split),('all',ts>0)):
        v=[x for x,s in zip(allt,sel) if s]; r=np.array([x[2] for x in v]); h1=np.mean([x[1] for x in v])
        print(f"{g:9} {part:5} n={len(v):4}  TP1 atteint {h1*100:.0f}%  trades perdants {np.mean(r<0)*100:.0f}%  esperance {r.mean():+.2f}R  total {r.sum():+.0f}R")
        if part=='all': stats[g]=dict(trades=len(v),tp1_rate=round(h1*100,1),loss_rate=round(float(np.mean(r<0))*100,1),expectancy_r=round(float(r.mean()),3),
                                      from_epoch=int(ts.min()),to_epoch=int(ts.max()),params=p)
    months={}
    for x in allt: months.setdefault(int(x[0]//2629800),[]).append(x[2])
    print(f"   mois positifs : {sum(1 for v in months.values() if np.mean(v)>0)}/{len(months)}")
json.dump(stats,open('research/drift_stats.json','w'),indent=1)
