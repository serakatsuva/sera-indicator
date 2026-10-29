#!/usr/bin/env python3
from pathlib import Path
import re

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from ea_files import check as check_ea_files, ea_path

deriv_path = ea_path("Deriv")
text = deriv_path.read_text(encoding="utf-8")
errors = list(check_ea_files())

version = re.search(r'#property\s+version\s+"([^"]+)"', text)
if not version:
    errors.append("EA version missing")

required = {
    "real account enabled (owner choice)": "AllowRealAccount=true",
    "fresh signals only": "MaximumSignalAgeMinutes=20",
    "broker H1/H4 confirmation": "BrokerConfirms(symbol,verdict",
    "smart exit on reversal or max holding": "SmartExit(setup_id,symbol,mode,verdict,confidence,object)",
    "forex weekend gap guard": "WeekendGapRisk",
    "balance-based position scaling": "AllowedOpenPositions()",
    "no fixed position cap (signals + risk budget decide)": "MaximumOpenPositionsCap=0",
    "balance-proportional lots (no USD cap)": "MaximumLossUSD=0.0",
    "minimum lot fallback": "UseMinimumLotWhenRiskTooSmall=true",
    "Day M15/H1 signals traded by default": "TradeDaySignals=true",
    "on-chart dashboard": "RenderDashboard();",
    "dashboard shows every entry check": "#define SERA_GATES 11",
    "dashboard explains WebRequest 4014": "BLOQUES par MT5 (erreur 4014)",
    "Day/Swing share a symbol: only the owner cancels a limit order": "SERA_PENDOWNER_",
    "total open risk budget": "TotalRiskAllows(",
    "one position per symbol": "HasSeraPositionOn(symbol)",
    "signals decide (no profit-based sizing)": "BalancePerPositionUSD=0.0",
    "compact EA feed": "data/ea-signals.json",
    "full feed fallback": "FetchUrl(FallbackSignalsUrl,json)",
    "management independent of signals": "ManageAllSeraPositions();",
    "levels stored for limit fills": "StoreTradeLevels(setup_id,symbol,pending_entry",
    "partial close at TP1": "trade.PositionClosePartial(ticket,part)",
    "emergency equity stop": "if(EmergencyEquityStop()) return;",
    "clear WebRequest permission message": "error==4014",
    "cut on market reversal (broker)": "CutReversedPositions();",
    "cut on market reversal (server H1+H4)": "JsonFlagTrue(confirmation,\"trendStrong\")",
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

executor = Path("mt5/Sera_Swing_Executor.mq5")
if executor.exists() and executor.read_text(encoding="utf-8") != text:
    errors.append("mt5/Sera_Swing_Executor.mq5 differs from the Deriv EA (keep both copies identical)")

swx_path = ea_path("Weltrade")
if swx_path.exists():
    swx = swx_path.read_text(encoding="utf-8")
    for name, token in {
        "SyntX: emergency equity stop first": "if(EmergencyEquityStop()) return;",
        "SyntX: positions managed every cycle": "ManageAllSeraPositions();",
        "SyntX: reversal cut": "CutReversedPositions();",
        "SyntX: total risk budget": "TotalRiskAllows(PositionRiskUSD(",
        "SyntX: one trade per signal bar": "SWX_TRADEDBAR_",
        "SyntX: 2-candle confirmation": "cycles>=2",
        "SyntX: high-conviction score": "d.score>=84",
        "SyntX: own magic number": "MagicNumber=26102101",
        "SyntX: own global-variable namespace": '"SWX_',
    }.items():
        if token not in swx:
            errors.append(f"missing {name}: {token}")
    if '"SERA_' in swx:
        errors.append("SyntX EA must not share SERA_ global variables with the Sera EA")

if errors:
    print("\n".join("ERROR: " + e for e in errors))
    raise SystemExit(1)

print(f"EA QA passed: version {version.group(1)}")
