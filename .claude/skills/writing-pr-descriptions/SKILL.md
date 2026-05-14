---
name: writing-pr-descriptions
description: Use when drafting or writing a pull request description, PR summary, or GitHub PR body. Use when the user asks you to write, draft, or fill in a PR description for their changes.
---

# Writing PR Descriptions

## Overview

Follow a flexible section palette: pick the sections the PR needs, skip the rest. Output as a markdown code block so the user can copy it directly into GitHub.

**Required sub-skill:** Apply `humanizer` to the draft internally, then present only the final humanized result as a markdown code block. Do not show the intermediate draft or the humanizer audit steps to the user.

Write in NZ English (organise, behaviour, colour, analyse).

---

## Section Palette

Use `###` headings for all sections. Never use bold text as a section heading.

### Summary (always include)

2-4 sentences or short bullets. What changed at a high level, focused on the user-visible or system-visible outcome. Write in plain, direct English — no jargon, no technical terms unless essential. A non-technical reader should understand the gist.

### Problem / Why / Problem & motivation (always include)

Why the change was needed, with a concrete failure mode. Include actual error output, data structures, or a before/after example when they make the problem tangible. Name the specific consequences ("kills the worker", "exceeds PostgreSQL's 256MB JSONB ceiling"). Be honest about edge cases.

For simple bugs: one paragraph with an error block is enough.
For larger motivation: explain the sequence of events that exposed the gap.

### Approach (include when the technical choice was not obvious)

Justify the solution with data: measurements, percentages, error bounds. Name the alternatives considered and say explicitly why each was set aside. Example: projected worst-case size (119MB vs 256MB limit), max error introduced (5.2x10^-8 metres).

### Notable changes (always include)

One bullet per meaningful file or component. Format:

```
- `filepath`: imperative description
```

Use imperative verbs: Adds, Drops, Replaces, Removes, Rounds, Promotes. Describe what changed and why in the same line when the why is not clear from Summary or Problem. No em dashes in descriptions -- use a comma or rewrite as two phrases.

### Further changes (include when there are many small related changes)

Overflow from Notable changes for a cluster of small modifications that would clutter the main list. Same imperative bullet style.

### End to end testing / TODO (include when there is meaningful testing to document)

High-level functional scenarios, not unit test outcomes. Already-checked boxes are the norm. Be honest about gaps:

```
- [x] Calculates exposure
- [x] Exports to development
- [ ] Did not test export_to_merit.py -- that script is deprecated
```

### Deployment notes (include for breaking changes or ops-required steps)

Specific commands, not vague instructions. Ordered checklist when sequence matters. Include timing or scale when relevant: "The migration completed in about 8 minutes using 4 cores with 16GB RAM." Note any backup or rollback strategy.

### References (include when external resources exist)

Links to Basecamp cards, Slack threads, related PRs. No descriptions needed.

---

## Style Rules

- No "What stays the same" or "No breaking changes" sections. Omit what did not change.
- No opening paragraph like "This PR introduces..." -- start with the Summary heading.
- Concrete nouns: name the file, function, column, or class. Not "the relevant module".
- Numbers over vague claims: "61% reduction", not "significantly smaller".
- State what was not tested and why. Reviewers trust this over silence.
- Scale length to the change: 150-250 words for a focused bugfix, 500-700 words for a large refactor.
- No em dashes (—) anywhere in the description. Use a comma, a period, or rewrite as two sentences.

---

## Section Selection by PR Type

| PR type | Sections |
|---|---|
| Bug fix, new exception, small QA check | Summary, Problem, Notable changes, References |
| Data or algorithm change with non-obvious approach | Summary, Problem, Approach, Notable changes, Deployment notes |
| Large refactor removing or replacing a concept | Summary, Why, Notable changes, Further changes, E2E testing, Deployment notes, References |
