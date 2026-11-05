# Analyse des événements produits par scripts/backtest.mjs (jsonl) : calibration, setups, régimes, familles.
# Usage : python3 research/analyze_events.py research/events.jsonl
import json,sys,math,collections
def load(p):
    return [json.loads(l) for l in open(p) if l.strip()]
def wilson(k,n,z=1.96):
    if not n:return (0,0)
    p=k/n;d=1+z*z/n;c=p+z*z/(2*n);m=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n));return ((c-m)/d,(c+m)/d)
def stat(rows):
    n=len(rows)
    if not n:return None
    r=[e['r'] for e in rows];w=sum(1 for x in r if x>0);l=sum(1 for x in r if x<0)
    tp1=sum(1 for e in rows if e.get('tp1'))
    avg=sum(r)/n
    sd=math.sqrt(max(0,sum((x-avg)**2 for x in r)/n))
    t=avg/(sd/math.sqrt(n)) if sd>0 else 0
    lo,hi=wilson(w,w+l)
    return dict(n=n,win=100*w/max(1,w+l),lo=100*lo,hi=100*hi,tp1=100*tp1/n,avg=avg,tot=sum(r),t=t)
def line(label,rows):
    s=stat(rows)
    if not s:return f"{label:42s} —"
    return f"{label:42s} n={s['n']:5d} TP1 {s['tp1']:4.0f}%  gagnants {s['win']:4.0f}% [{s['lo']:2.0f}-{s['hi']:2.0f}]  R moy {s['avg']:+.3f}  R tot {s['tot']:+8.1f}  t={s['t']:+.1f}"
def table(title,rows,keyf,minn=40,order=None):
    print(f"\n## {title}")
    g=collections.defaultdict(list)
    for e in rows:g[keyf(e)].append(e)
    keys=order or sorted(g,key=lambda k:-len(g[k]))
    for k in keys:
        if len(g.get(k,[]))>=minn:print(line(str(k),g[k]))
def bucket(v,edges):
    for lo,hi in edges:
        if lo<=v<hi:return f"{lo}-{hi-1}"
    return "?"
if __name__=="__main__":
    ev=[]
    for p in sys.argv[1:]:ev+=load(p)
    print("TOTAL événements",len(ev))
    print(line("TOUS",ev))
    sig=[e for e in ev if e['signal']]
    print(line("SIGNAUX (verdict BUY/SELL)",sig))
    print(line("SETUPS détectés seulement",[e for e in ev if not e['signal']]))
    for m in ("day","swing"):
        print(line(f"mode {m} · signaux",[e for e in sig if e['mode']==m]))
        print(line(f"mode {m} · tous",[e for e in ev if e['mode']==m]))
    table("Signaux · par confiance",sig,lambda e:bucket(e['confidence'],[(0,70),(70,80),(80,85),(85,90),(90,95),(95,101)]),minn=20,order=["0-69","70-79","80-84","85-89","90-94","95-100"])
    table("Signaux · par score exec",sig,lambda e:bucket(e['exec_score'],[(0,70),(70,80),(80,90),(90,101)]),minn=20,order=["0-69","70-79","80-89","90-100"])
    table("Signaux · par état d'exécution",sig,lambda e:e.get('state'),minn=20)
    table("Signaux · par type de setup",sig,lambda e:e['setup'],minn=20)
    table("Signaux · par régime d'entrée",sig,lambda e:e['regime'],minn=20)
    table("Signaux · par famille",sig,lambda e:e['family'],minn=20)
    table("Signaux · par sens",sig,lambda e:e['side'],minn=20)
    table("Signaux · balayage de liquidité",sig,lambda e:"sweep" if e['sweep'] else "sans",minn=20)
    table("Signaux · par ADX",sig,lambda e:bucket(int(e['adx']),[(0,20),(20,30),(30,40),(40,100)]),minn=20)
    table("Signaux · par qualité de tendance",sig,lambda e:bucket(e['tq'],[(0,60),(60,72),(72,85),(85,101)]),minn=20)
    # moitiés temporelles pour tester la stabilité
    if sig:
        ts=sorted(e['t'] for e in sig);mid=ts[len(ts)//2]
        print("\n## Stabilité (1re / 2e moitié du temps)")
        print(line("signaux · 1re moitié",[e for e in sig if e['t']<mid]))
        print(line("signaux · 2e moitié",[e for e in sig if e['t']>=mid]))
    # meilleurs/pires marchés (n>=25)
    g=collections.defaultdict(list)
    for e in sig:g[e['market']].append(e)
    rows=[(k,stat(v)) for k,v in g.items() if len(v)>=25]
    rows.sort(key=lambda x:x[1]['avg'])
    print("\n## Marchés (signaux, n>=25) : 6 pires / 6 meilleurs par R moyen")
    for k,s in rows[:6]+rows[-6:]:print(f"{k:34s} n={s['n']:4d} gagnants {s['win']:3.0f}%  R moy {s['avg']:+.3f}  R tot {s['tot']:+.1f}")
