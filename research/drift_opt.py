"""Drift playbook, non-overlapping trades, parameter search on TRAIN (first 70 %), verdict on TEST (last 30 %).
Deriv drift families: Boom (SELL), Crash (BUY), Bull Market (BUY), Bear Market (SELL)."""
import gzip, json, itertools, sys
import numpy as np
sys.argv=[sys.argv[0]]
src=open('research/strategies.py').read().split('rows = defaultdict(list)')[0]
exec(src)
def drift_of(n):
    n=n.lower()
    return -1 if ('boom' in n or 'bear' in n) else 1 if ('crash' in n or 'bull' in n) else 0
def group(n):
    n=n.lower(); return 'boomcrash' if ('boom' in n or 'crash' in n) else 'bullbear'
def run(m,rsi_th,slm,rr,trend,cool,part):
    side=drift_of(m['name']); H=np.array(m['H1'],dtype=float); t,o,h,l,c=H.T
    e20,e50=ema(c,20),ema(c,50); a=atr(h,l,c); r=rsi(c); split=int(len(t)*.7)
    lo,hi=(210,split) if part=='train' else (split,len(c)-1)
    out=[]; i=lo
    while i<hi:
        tr=(e20[i]<e50[i]) if side<0 else (e20[i]>e50[i])
        pull=(r[i]>100-rsi_th) if side<0 else (r[i]<rsi_th)
        if (tr or not trend) and pull:
            sl=slm*a[i]; tp=c[i]+side*rr*sl; st=c[i]-side*sl; res=None
            for j in range(i+1,min(len(c),i+241)):
                adv=l[j] if side>0 else h[j]; fav=h[j] if side>0 else l[j]
                if (adv<=st) if side>0 else (adv>=st): res=(-1.0,j); break
                if (fav>=tp) if side>0 else (fav<=tp): res=(rr,j); break
            if res is None: break
            out.append(res[0]); i=res[1]+cool; continue
        i+=1
    return out
mk=[m for m in d['markets'] if drift_of(m['name']) and len(m['H1'])>=1500]
best={}
for g in ('boomcrash','bullbear'):
    ms=[m for m in mk if group(m['name'])==g]; rows=[]
    for rsi_th,slm,rr,trend,cool in itertools.product((30,40,45,50),(1.0,1.5,2.5),(0.3,0.5,1.0,1.5),(True,False),(1,6)):
        tr=sum((run(m,rsi_th,slm,rr,trend,cool,'train') for m in ms),[])
        if len(tr)<60: continue
        rows.append((np.mean(tr),np.mean(np.array(tr)>0),len(tr),rsi_th,slm,rr,trend,cool))
    rows.sort(reverse=True)
    print(f"== {g}: 5 meilleurs reglages sur TRAIN, verifies sur TEST")
    for exp,win,n,rsi_th,slm,rr,trend,cool in rows[:5]:
        te=sum((run(m,rsi_th,slm,rr,trend,cool,'test') for m in ms),[])
        print(f"  RSI {rsi_th} SL {slm}ATR RR {rr} trend {trend} pause {cool}h | train n={n} win {win*100:.0f}% exp {exp:+.2f}R"
              f" | test n={len(te)} win {np.mean(np.array(te)>0)*100:.0f}% exp {np.mean(te):+.2f}R")
    # highest win rate with positive train expectancy
    hw=sorted([x for x in rows if x[0]>0.03],key=lambda x:-x[1])[:3]
    print(f"   -> taux de reussite le plus eleve (esperance > 0) :")
    for exp,win,n,rsi_th,slm,rr,trend,cool in hw:
        te=sum((run(m,rsi_th,slm,rr,trend,cool,'test') for m in ms),[])
        print(f"  RSI {rsi_th} SL {slm}ATR RR {rr} trend {trend} pause {cool}h | train n={n} win {win*100:.0f}% exp {exp:+.2f}R"
              f" | test n={len(te)} win {np.mean(np.array(te)>0)*100:.0f}% exp {np.mean(te):+.2f}R")
