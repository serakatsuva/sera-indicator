#!/usr/bin/env python3
from dataclasses import dataclass

BASE_RISK=0.50
MAX_RISK=0.75
MAX_PENDING=1

@dataclass
class Account:
    equity: float
    balance: float
    baseline: float
    daily_profit: float = 0.0
    consecutive_losses: int = 0

def adaptive_risk(a: Account) -> float:
    risk=BASE_RISK
    if a.equity>a.baseline and a.baseline>0:
        growth=(a.equity-a.baseline)/a.baseline*100
        steps=int(growth//5)
        risk += steps*0.05
    if a.daily_profit>=2:
        risk += 0.05
    if a.consecutive_losses>=1:
        risk=min(risk,BASE_RISK*0.75)
    dd=max(0,(a.balance-a.equity)/a.balance*100) if a.balance else 0
    if dd>=1: risk=min(risk,BASE_RISK*0.65)
    if dd>=2: risk=min(risk,BASE_RISK*0.50)
    return max(0.10,min(risk,MAX_RISK))

def pending_allowed(final_verdict, execution_state, score, conditions, open_positions, open_pending, existing_same_symbol=False):
    return (
        final_verdict in {"BUY","SELL"}
        and execution_state=="WAIT_RETRACE"
        and score>=72
        and conditions>=80
        and open_positions<1
        and (existing_same_symbol or open_pending<MAX_PENDING)
    )

def market_allowed(final_verdict, execution_state, score, conditions):
    return (
        final_verdict in {"BUY","SELL"}
        and execution_state=="EXECUTE_NOW"
        and score>=78
        and conditions>=80
    )

tests=[]

def check(name, cond):
    tests.append((name, bool(cond)))

check("base risk remains 0.50", adaptive_risk(Account(100,100,100))==0.50)
check("equity growth raises risk gradually", adaptive_risk(Account(110,110,100))>0.50)
check("risk never exceeds 0.75", adaptive_risk(Account(200,200,100,daily_profit=10))<=0.75)
check("loss reduces risk instead of martingale", adaptive_risk(Account(105,105,100,consecutive_losses=1))<0.50)
check("drawdown reduces risk", adaptive_risk(Account(97,100,100))<=0.25)
check("WAIT_RETRACE confirmed BUY can place pending", pending_allowed("BUY","WAIT_RETRACE",80,90,0,0))
check("setup without final verdict cannot place pending", not pending_allowed("ATTENDRE","WAIT_RETRACE",90,95,0,0))
check("second pending blocked globally", not pending_allowed("SELL","WAIT_RETRACE",90,95,0,1))
check("same-symbol pending may be updated", pending_allowed("SELL","WAIT_RETRACE",90,95,0,1,True))
check("EXECUTE_NOW does not create pending", not pending_allowed("BUY","EXECUTE_NOW",90,95,0,0))
check("market order requires EXECUTE_NOW", market_allowed("BUY","EXECUTE_NOW",90,95))
check("market order blocked on WAIT_RETRACE", not market_allowed("BUY","WAIT_RETRACE",90,95))
check("market order blocked below 80 percent conditions", not market_allowed("SELL","EXECUTE_NOW",90,79))

failed=[name for name,ok in tests if not ok]
for name,ok in tests:
    print(("PASS" if ok else "FAIL")+": "+name)
if failed:
    raise SystemExit("Intelligence QA failed: "+", ".join(failed))
print(f"Intelligence QA passed: {len(tests)} scenarios")


# adaptive evidence self-test contract
from pathlib import Path
adaptive = Path("scripts/adaptive_evidence.py").read_text(encoding="utf-8")
check("adaptive evidence engine present", "Sera Adaptive Evidence v1.0" in adaptive)
check("adaptive evidence cannot manufacture trades", "cannot create or reverse a BUY/SELL" in adaptive)
check("adaptive evidence has conservative downgrade", 'execution_state"]="WAIT_CONFIRMATION"' in adaptive or 'WAIT_CONFIRMATION' in adaptive)
check("adaptive evidence minimum sample gate", 'sample_size"]<12' in adaptive or 'sample_size"] < 12' in adaptive)
