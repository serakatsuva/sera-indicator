#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_SIGNALS=Path("data/signals.json")
DEFAULT_CANDLES=Path("/tmp/sera-candles.json")
DEFAULT_MEMORY=Path("data/adaptive-evidence.json")
VERSION="Sera Adaptive Evidence v1.0"
MAX_RECORDS=600


def load(path:Path,default:Any):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def save(path:Path,value:Any):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2),encoding="utf-8")


def num(value:Any,default:float=0.0)->float:
    try:
        value=float(value)
        return value if math.isfinite(value) else default
    except Exception:
        return default


def candle_rows(candles:dict[str,Any],symbol:str,mode:str):
    tf="H1" if mode=="swing" else "M15"
    rows=(candles.get("series") or {}).get(f"{symbol}:{tf}") or []
    return rows if isinstance(rows,list) else []


def simulate(record:dict[str,Any],rows:list[dict[str,Any]])->dict[str,Any]|None:
    direction=record.get("direction")
    levels=record.get("levels") or {}
    if direction not in {"BUY","SELL"}:
        return None
    keys=["entry","sl","tp1","tp2","tp3","tp4","tp5"]
    if not all(isinstance(levels.get(k),(int,float)) for k in keys):
        return None

    entry=num(levels["entry"]); stop=num(levels["sl"])
    targets=[num(levels[f"tp{i}"]) for i in range(1,6)]
    opened=int(record.get("opened_epoch") or 0)
    horizon=168*3600 if record.get("mode")=="swing" else 48*3600
    expiry=opened+horizon

    stage=0
    current_stop=stop
    last_epoch=opened

    for candle in rows:
        epoch=int(candle.get("epoch") or 0)
        if epoch<=opened:
            continue
        if epoch>expiry:
            break
        high=num(candle.get("high")); low=num(candle.get("low"))
        last_epoch=epoch

        # Conservative ordering: if stop and next target are both touched inside
        # one candle, assume stop happened first because intrabar order is unknown.
        stop_hit=(low<=current_stop) if direction=="BUY" else (high>=current_stop)
        if stop_hit:
            if stage==0:
                result="LOSS"; r=-1.0
            elif stage==1:
                result="BREAKEVEN"; r=0.0
            else:
                result=f"LOCKED_TP{stage-1}"; r=[0,0,1.5,2.4,3.6][stage]
            return {"status":"resolved","result":result,"r":r,"max_stage":stage,"resolved_epoch":epoch}

        while stage<5:
            target=targets[stage]
            hit=(high>=target) if direction=="BUY" else (low<=target)
            if not hit:
                break
            stage+=1
            if stage==1:
                current_stop=entry
            elif stage==2:
                current_stop=targets[0]
            elif stage==3:
                return {"status":"resolved","result":"WIN_TP3","r":3.6,"max_stage":3,"resolved_epoch":epoch}
            elif stage==4:
                current_stop=targets[2]
            elif stage==5:
                return {"status":"resolved","result":"WIN_TP5","r":6.0,"max_stage":5,"resolved_epoch":epoch}

    latest=int(rows[-1].get("epoch") or 0) if rows else 0
    if latest>=expiry:
        if stage>=2:
            return {"status":"resolved","result":f"TIMEOUT_TP{stage}","r":2.4 if stage==2 else 1.5,"max_stage":stage,"resolved_epoch":latest}
        if stage==1:
            return {"status":"resolved","result":"TIMEOUT_BE","r":0.0,"max_stage":1,"resolved_epoch":latest}
        return {"status":"resolved","result":"TIMEOUT_FLAT","r":0.0,"max_stage":0,"resolved_epoch":latest}

    return {"status":"open","max_stage":stage,"last_epoch":last_epoch}


def profile_key(record:dict[str,Any])->str:
    return "|".join([
        str(record.get("market") or ""),
        str(record.get("mode") or ""),
        str(record.get("setup_type") or "GENERIC"),
        str(record.get("regime") or "UNKNOWN"),
    ])


def build_profiles(records:list[dict[str,Any]])->dict[str,Any]:
    grouped:dict[str,list[dict[str,Any]]]={}
    for record in records:
        if record.get("status")!="resolved":
            continue
        grouped.setdefault(profile_key(record),[]).append(record)

    profiles={}
    for key,items in grouped.items():
        recent=sorted(items,key=lambda r:int(r.get("resolved_epoch") or 0))[-100:]
        rs=[num(x.get("r")) for x in recent]
        decisive=[r for r in recent if num(r.get("r"))!=0]
        wins=[r for r in decisive if num(r.get("r"))>0]
        n=len(recent)
        decisive_n=len(decisive)
        win_rate=(len(wins)/decisive_n) if decisive_n else None
        avg_r=sum(rs)/n if n else 0.0
        profiles[key]={
            "samples":n,
            "decisive_samples":decisive_n,
            "win_rate":round(win_rate*100,1) if win_rate is not None else None,
            "avg_r":round(avg_r,3),
            "losses":sum(1 for r in recent if num(r.get("r"))<0),
            "breakeven_or_flat":sum(1 for r in recent if num(r.get("r"))==0),
            "wins":sum(1 for r in recent if num(r.get("r"))>0),
        }
    return profiles


def evidence_adjustment(profile:dict[str,Any]|None)->dict[str,Any]:
    if not profile:
        return {"sample_size":0,"maturity":"NONE","confidence_adjustment":0,"execution_adjustment":0,"gate":"NEUTRAL"}

    n=int(profile.get("samples") or 0)
    decisive=int(profile.get("decisive_samples") or 0)
    win_rate=profile.get("win_rate")
    avg_r=num(profile.get("avg_r"))

    if n<12 or decisive<8 or win_rate is None:
        return {"sample_size":n,"maturity":"LEARNING","confidence_adjustment":0,"execution_adjustment":0,"gate":"NEUTRAL"}

    shrink=n/(n+30.0)
    win_edge=(num(win_rate)/100.0-.50)
    raw=(win_edge*14.0 + max(-1.5,min(1.5,avg_r))*2.0)*shrink
    conf=max(-4,min(4,round(raw)))
    exec_adj=max(-6,min(6,round(raw*1.35)))

    gate="NEUTRAL"
    if n>=20 and decisive>=14 and num(win_rate)<35 and avg_r<0:
        gate="CAUTION"
        conf=min(conf,-2)
        exec_adj=min(exec_adj,-4)
    elif n>=25 and decisive>=18 and num(win_rate)>=58 and avg_r>=0.45:
        gate="SUPPORTED"

    return {
        "sample_size":n,
        "decisive_samples":decisive,
        "maturity":"MATURE" if n>=20 else "DEVELOPING",
        "win_rate":win_rate,
        "avg_r":avg_r,
        "confidence_adjustment":conf,
        "execution_adjustment":exec_adj,
        "gate":gate,
    }


def record_from_row(row:dict[str,Any])->dict[str,Any]|None:
    direction=row.get("final_verdict")
    levels=row.get("levels")
    if row.get("mode") not in {"day","swing"} or direction not in {"BUY","SELL"} or not isinstance(levels,dict):
        return None
    opened=int(((row.get("entry_tf") or {}).get("closedAt")) or 0)
    if opened<=0:
        return None
    return {
        "key":f"{row.get('id')}|{opened}|{direction}",
        "id":row.get("id"),
        "market":row.get("market"),
        "symbol":row.get("symbol"),
        "mode":row.get("mode"),
        "direction":direction,
        "opened_epoch":opened,
        "setup_type":((row.get("decision_engine") or {}).get("setup_type") or "GENERIC"),
        "regime":((row.get("entry_tf") or {}).get("regime") or "UNKNOWN"),
        "confidence":row.get("final_confidence"),
        "execution_score":row.get("execution_score"),
        "active_strategies":((row.get("decision_engine") or {}).get("active_strategies") or []),
        "levels":{k:levels.get(k) for k in ("entry","sl","tp1","tp2","tp3","tp4","tp5")},
        "status":"open",
        "created_at":datetime.now(timezone.utc).isoformat().replace("+00:00","Z"),
    }


def apply_evidence(row:dict[str,Any],profiles:dict[str,Any]):
    pseudo={
        "market":row.get("market"),"mode":row.get("mode"),
        "setup_type":((row.get("decision_engine") or {}).get("setup_type") or "GENERIC"),
        "regime":((row.get("entry_tf") or {}).get("regime") or "UNKNOWN"),
    }
    profile=profiles.get(profile_key(pseudo))
    evidence=evidence_adjustment(profile)
    row["adaptive_evidence"]={"version":VERSION,"profile_key":profile_key(pseudo),**evidence}

    if evidence["sample_size"]<12:
        return

    row["final_confidence"]=int(max(18,min(96,num(row.get("final_confidence"))+evidence["confidence_adjustment"])))
    row["execution_score"]=int(max(0,min(98,num(row.get("execution_score"))+evidence["execution_adjustment"])))
    if isinstance(row.get("execution"),dict):
        row["execution"]["score"]=row["execution_score"]

    if evidence["gate"]=="CAUTION" and row.get("execution_state")=="EXECUTE_NOW":
        row["execution_state"]="WAIT_CONFIRMATION"
        row["execution_ready"]=0
        if isinstance(row.get("execution"),dict):
            row["execution"]["state"]="WAIT_CONFIRMATION"
            row["execution"]["ready"]=False
            row["execution"]["reason"]=(str(row["execution"].get("reason") or "")+" Historical evidence for this market/regime/setup is weak; execution downgraded to WAIT_CONFIRMATION.").strip()


def run(signals_path:Path,candles_path:Path,memory_path:Path):
    signals=load(signals_path,{})
    candles=load(candles_path,{})
    memory=load(memory_path,{"version":VERSION,"records":[]}) or {"version":VERSION,"records":[]}
    records=memory.get("records") if isinstance(memory.get("records"),list) else []

    for record in records:
        if record.get("status")!="open":
            continue
        rows=candle_rows(candles,str(record.get("symbol") or ""),str(record.get("mode") or ""))
        outcome=simulate(record,rows)
        if outcome:
            record.update(outcome)

    known={str(r.get("key")) for r in records}
    for row in signals.get("markets") or []:
        record=record_from_row(row)
        if record and record["key"] not in known:
            records.append(record)
            known.add(record["key"])

    records=sorted(records,key=lambda r:int(r.get("opened_epoch") or 0))[-MAX_RECORDS:]
    profiles=build_profiles(records)

    for row in signals.get("markets") or []:
        apply_evidence(row,profiles)

    signals["adaptive_learning"]={
        "version":VERSION,
        "records":len(records),
        "resolved_records":sum(1 for r in records if r.get("status")=="resolved"),
        "profiles":len(profiles),
        "policy":"Evidence may modestly adjust confidence/execution scores and can downgrade EXECUTE_NOW. It cannot create or reverse a BUY/SELL.",
    }
    signals["model"]=str(signals.get("model") or "Sera")+" + Adaptive Evidence"

    save(signals_path,signals)
    save(memory_path,{
        "version":VERSION,
        "updated_at":datetime.now(timezone.utc).isoformat().replace("+00:00","Z"),
        "records":records,
        "profiles":profiles,
    })


def self_test():
    base={
        "market":"Test","mode":"swing","setup_type":"BREAKOUT_CONTINUATION","regime":"TRENDING"
    }
    records=[]
    for i in range(20):
        r={**base,"status":"resolved","resolved_epoch":i,"r":3.6 if i<12 else -1.0}
        records.append(r)
    p=build_profiles(records)
    e=evidence_adjustment(p[profile_key(base)])
    assert e["sample_size"]==20
    assert e["confidence_adjustment"]>=0

    rec={"direction":"BUY","mode":"swing","opened_epoch":100,"levels":{"entry":100,"sl":95,"tp1":107.5,"tp2":112,"tp3":118,"tp4":124,"tp5":130}}
    rows=[{"epoch":200,"high":108,"low":99},{"epoch":300,"high":113,"low":107},{"epoch":400,"high":119,"low":111}]
    out=simulate(rec,rows)
    assert out and out["result"]=="WIN_TP3" and out["r"]==3.6
    print(VERSION+" self-test passed")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--signals",default=str(DEFAULT_SIGNALS))
    parser.add_argument("--candles",default=str(DEFAULT_CANDLES))
    parser.add_argument("--memory",default=str(DEFAULT_MEMORY))
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        self_test(); return
    run(Path(args.signals),Path(args.candles),Path(args.memory))


if __name__=="__main__":
    main()
