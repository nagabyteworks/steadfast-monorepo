# Trading decisions

These entries record decisions from the current conversation. They were recorded
on 2026-11-26; exact decision times and earlier decision dates are not captured.
They do not imply that the implementation is complete.

| Decision | Status | Reason / effect |
| --- | --- | --- |
| Broker-side protective SL using SL-LMT | SUPERSEDED | Initially discussed after learning NSE options reject SL-M. The later explicit decision is virtual SL and target only; do not maintain broker-side protective orders. |
| One-lot maximum entry per order | SUPERSEDED | User clarified 1–10 whole lots per order, with additional orders permitted. It is not a position-size or daily-loss limit. |
| LTP, weighted average, last fill or last submitted order as initial reference | SUPERSEDED | User clarified that the first executed fill of the current open lifecycle is the SL/target reference; weighted average remains separate for P&L. |
| Unproven carry-forward continuity | ACTIVE | Matching quantities and a persisted opening fill do not prove a position stayed open while offline. Do not recover from them without complete authoritative history; flag unidentifiable positions when reconciliation is attempted. |
| API MKT exits | SUPERSEDED | User chose marketable LMT exits, with fresh bid/ask and bounded repricing, because the existing integration encounters API MKT rejection. |
| Virtual risk monitoring | ACTIVE | Rules are internal; communicate that exchange-side protection is absent and that monitoring and execution can fail. The desired authority is the backend; the current UI monitor remains a gap. |
| Repricing | ACTIVE | Three total attempts, two seconds between checks, one additional tick per attempt, maximum three ticks adverse from the initial bid/ask, with confirmed cancellation and remaining quantity before replacement. No LTP fallback. |
| Live configuration and verification | ACTIVE | Preserve existing live configuration; do not deploy, enable trading or place real orders during development/testing. Use mocked broker responses. The checked-in production unit's live-enabled setting is a documented deviation from the desired explicit-startup safeguard, not an instruction to change it. |
| Continuous documentation | ACTIVE | Maintain implementation, architecture, trading rules, decisions and test status with each applicable task. Preserve superseded decisions and report actual test evidence. |
