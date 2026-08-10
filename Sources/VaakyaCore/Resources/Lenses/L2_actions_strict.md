---
id: L2_actions_strict
title: Strict action items
requires_llm: true
min_fidelity: A1
default_egress: B1
---

# Instructions

Apply the strict actions lens. High trust: do not invent owners, due dates, or commitments.

**Owner rule:** Owner must appear as a name in the inputs or be `unassigned`.

Output Markdown matching the required headings and table exactly.

# Action items

| ID | Action | Owner | Due | Source | Evidence |
|----|--------|-------|-----|--------|----------|
| A1 | … | name or unassigned | date or not stated | notes/transcript | quote |

## Blocked / waiting on
- …

## Not actions (explicitly deferred)
- …
