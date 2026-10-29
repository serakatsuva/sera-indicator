#!/usr/bin/env python3
"""Static checks a MQL5 compiler would reject first, for files we cannot compile in CI:
unbalanced brackets, calls to functions that are neither defined in the file nor MQL5
built-ins, and CamelCase identifiers that are not declared (typo in an input name...).
Usage: qa_mql_static.py file.mq5 [file2.mq5 ...]"""
import re
import sys

BUILTIN_FUNCS = set("""Print Alert Comment SendNotification StringFind StringSubstr StringLen StringReplace StringToUpper
StringTrimLeft StringTrimRight StringSplit StringGetCharacter StringToDouble StringToTime IntegerToString DoubleToString
CharArrayToString MathMax MathMin MathAbs MathFloor MathRound MathSqrt ArrayResize ArraySize ArraySetAsSeries CopyRates
CopyClose CopyBuffer SymbolInfoDouble SymbolInfoInteger SymbolInfoTick SymbolSelect SymbolsTotal SymbolName
AccountInfoDouble AccountInfoInteger PositionsTotal PositionGetTicket PositionGetInteger PositionGetDouble PositionGetString
PositionSelect OrdersTotal OrderGetTicket OrderGetInteger OrderGetString OrderGetDouble OrderCalcMargin HistorySelect
HistoryDealsTotal HistoryDealGetTicket HistoryDealGetInteger HistoryDealGetDouble GlobalVariableCheck GlobalVariableGet
GlobalVariableSet TimeCurrent TimeGMT TimeToStruct StructToTime iTime EventSetTimer EventKillTimer GetLastError
ResetLastError TerminalInfoInteger MQLInfoInteger WebRequest NormalizeDouble IndicatorRelease iMA iRSI iATR iADX iMACD
Buy Sell BuyLimit SellLimit PositionClose PositionClosePartial PositionModify OrderDelete SetExpertMagicNumber
SetDeviationInPoints SetAsyncMode ResultRetcodeDescription ObjectCreate ObjectSetInteger ObjectSetString ObjectFind
ObjectDelete ObjectsDeleteAll ChartRedraw ChartGetInteger""".split())
KEYWORDS = set("if for while return else switch case break continue sizeof new delete void bool int long ulong uint "
               "double string datetime char ushort short".split())
KNOWN_TYPES = {"CTrade", "MqlTick", "MqlRates", "MqlDateTime", "Trade", "PanelRow"}


def strip(text: str) -> str:
    out, i, n = [], 0, len(text)
    while i < n:
        if text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j; continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        if text[i] in "\"'":
            q = text[i]; i += 1
            while i < n and text[i] != q:
                i += 2 if text[i] == "\\" else 1
            i += 1; out.append('""'); continue
        out.append(text[i]); i += 1
    return "".join(out)


def check(path: str) -> list[str]:
    code = strip(open(path, encoding="utf-8").read())
    errors = []
    for a, b in ("()", "{}", "[]"):
        if code.count(a) != code.count(b):
            errors.append(f"bracket mismatch {a}{b}: {code.count(a)} vs {code.count(b)}")
    funcs = set(re.findall(r"^\s*(?:[A-Za-z_]\w*\s+)+([A-Za-z_]\w*)\s*\(", code, re.M))
    inputs = set(re.findall(r"^\s*input\s+\w+\s+(\w+)", code, re.M))
    structs = set(re.findall(r"\bstruct\s+(\w+)", code))
    globals_ = set(re.findall(r"^(?:\w+)\s+(\w+)\s*(?:=|;|\[)", code, re.M))
    calls = set(re.findall(r"\b([A-Za-z_]\w*)\s*\(", code))
    undefined = sorted(c for c in calls if c not in funcs | BUILTIN_FUNCS | KEYWORDS | structs)
    if undefined:
        errors.append(f"undefined functions: {undefined}")
    idents = set(re.findall(r"\b([A-Z][A-Za-z0-9]*[a-z][A-Za-z0-9]*)\b(?!\s*\()", code))
    unknown = sorted(i for i in idents if i not in inputs | globals_ | structs | funcs | KNOWN_TYPES)
    if unknown:
        errors.append(f"undeclared identifiers: {unknown}")
    return errors


def main() -> int:
    failed = False
    for path in sys.argv[1:]:
        errors = check(path)
        print(f"{path}: {'OK' if not errors else 'ERRORS'}")
        for e in errors:
            print("  ERROR:", e)
        failed |= bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
