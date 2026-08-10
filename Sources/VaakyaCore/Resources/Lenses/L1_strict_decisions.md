---
id: L1_strict_decisions
title: Strict decisions
requires_llm: true
min_fidelity: A1
default_egress: B1
---

# Instructions

Apply the strict decisions lens to the meeting evidence. High trust: only claim decisions that are clearly stated or agreed in the inputs.

Output Markdown matching the required headings exactly.

# Decisions

## Confirmed decisions
For each:
- **Decision:** …
- **Who stated / agreed:** …
- **Evidence:** "…" — [mm:ss] Speaker
- **Reversibility:** reversible | hard | not stated

## Explicit non-decisions
- Topics discussed without a decision (bullets + evidence optional)

## Open questions
- …

## Gaps / unclear ASR
- …
