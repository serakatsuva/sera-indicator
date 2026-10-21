#!/usr/bin/env python3
from pathlib import Path
import re

text = Path("mt5/Sera_EA_Swing_Intelligent.mq5").read_text(encoding="utf-8")
errors = []

version = re.search(r'#property\s+version\s+"([^"]+)"', text)
if not version:
    errors.append("EA version missing")

required = {
    "real account enabled (owner choice)": "AllowRealAccount=true",
    "fresh signals only": "MaximumSignalAgeMinutes=20",
    "broker H1/H4 confirmation": "BrokerConfirms(symbol,verdict",
    "smart exit on reversal or max holding": "SmartExit(setup_id,symbol,mode,verdict,confidence)",
    "forex weekend gap guard": "WeekendGapRisk",
    "per-signal freshness": "freshness_gate",
    "forex symbol resolution": "FRX\"+pair",
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
    "smart buy limit": "trade.BuyLimit",
    "smart sell limit": "trade.SellLimit",
    "adaptive risk": "AdaptiveRiskPercent",
    "adaptive loss cap": "AdaptiveLossCap",
    "pending cancellation": "CancelSeraPendingOrder",
    "EA intelligent name": "Sera EA Swing Intelligent",
    "local swing intelligence": "RunLocalSwingIntelligence",
    "gold profile": 'return "GOLD"',
    "crypto profile": 'return "CRYPTO"',
    "asset adaptive risk": "AssetRiskFactor",
    "ATR profit guard": "ManageLocalATRProfit",
    "H1/H4 local trend": "PERIOD_H4",
    "local MACD": "MACDHistogram",
    "local ADX": "ADXValue",
}
for name, token in required.items():
    if token not in text:
        errors.append(f"missing {name}: {token}")

# Bracket balance, ignoring strings and comments. Strings are removed first so that
# "https://..." inside a string is not mistaken for a // comment.
def strip_code(t):
    out, i, n = [], 0, len(t)
    while i < n:
        if t.startswith("//", i):
            j = t.find("\n", i); i = n if j < 0 else j; continue
        if t.startswith("/*", i):
            j = t.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if t[i] in "\"'":
            q = t[i]; i += 1
            while i < n and t[i] != q:
                i += 2 if t[i] == "\\" else 1
            i += 1; continue
        out.append(t[i]); i += 1
    return "".join(out)

clean = strip_code(text)
for opening, closing in ("()", "{}", "[]"):
    if clean.count(opening) != clean.count(closing):
        errors.append(f"bracket mismatch {opening}{closing}: {clean.count(opening)} vs {clean.count(closing)}")

if errors:
    print("\n".join("ERROR: " + e for e in errors))
    raise SystemExit(1)

print(f"EA QA passed: version {version.group(1)}")
