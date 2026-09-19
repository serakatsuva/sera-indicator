#!/usr/bin/env python3
from pathlib import Path
import re

text = Path("mt5/Sera_Swing_Executor.mq5").read_text(encoding="utf-8")
errors = []

version = re.search(r'#property\s+version\s+"([^"]+)"', text)
if not version:
    errors.append("EA version missing")

required = {
    "real account enabled": "AllowRealAccount=true",
    "automatic trading enabled": "EnableAutomaticTrading=true",
    "execute now guard": 'execution_state=="EXECUTE_NOW"',
    "OSS guard": "UseOpenSourceModelGuard=true",
    "daily loss circuit": "MaximumDailyLossUSD=3.00",
    "drawdown circuit": "MaximumDailyDrawdownPercent=3.00",
    "consecutive-loss circuit": "MaximumConsecutiveLosses=2",
    "margin check": "OrderCalcMargin",
    "broker stop check": "BrokerStopsValid",
    "smart position management": "ManageSeraPosition",
    "five targets": 'JsonNumber(levels,"tp5")',
}
for name, token in required.items():
    if token not in text:
        errors.append(f"missing {name}: {token}")

# lightweight brace balance ignoring quoted strings/comments sufficiently for regression checks
clean = re.sub(r'//.*', '', text)
clean = re.sub(r'/\*.*?\*/', '', clean, flags=re.S)
clean = re.sub(r'"(?:\\.|[^"\\])*"', '""', clean)
if clean.count('{') != clean.count('}'):
    errors.append("brace count mismatch")

if errors:
    print("\n".join("ERROR: " + e for e in errors))
    raise SystemExit(1)

print(f"EA QA passed: version {version.group(1)}")
