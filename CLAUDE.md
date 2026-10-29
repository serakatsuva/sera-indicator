# Sera Indicator — rules for changes

- Two MT5 EAs live in `mt5/`: `Sera_EA_Swing_Intelligent_Deriv_vX.YY.mq5` and `Sera_EA_Swing_Intelligent_Weltrade_vX.YY.mq5`.
  **Every improvement must be applied to both EAs** (shared modules: risk, orders, TP1-TP5 management, reversal cut,
  emergency stop, dashboard helpers), unless it only concerns the Deriv web feed (the Weltrade EA analyses inside MT5).
  `scripts/qa_ea.py` fails when a shared function differs between the two files.
- Each change bumps the version in the file name and in `#property version` (`git mv`), then:
  copy the Deriv EA to `mt5/Sera_Swing_Executor.mq5`, run `python3 scripts/build_ea_set.py`,
  update the download links / version text in `index.html` and the version section in `README.md`.
- QA before pushing: `ea_files.py`, `qa_ea.py`, `qa_mql_static.py`, `qa_mql_cpp.py`, `qa_ea_parser.py`,
  `qa_ea_dashboard.py`, `qa_ea_dashboard_weltrade.py`, `qa_swx_engine.py`, `build_ea_set.py --check`.
- The Weltrade engine section (between "MOTEUR D'ANALYSE" and "SCANNER") must stay equivalent to `scripts/update-signals.mjs`.
