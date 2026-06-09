---
number: 0000
title: Record architecture decisions
status: accepted
date: <YYYY-MM-DD>
---

# ADR-0000: Record architecture decisions

## Status

accepted

## Context

We want the *why* behind significant technical choices to live with the code, where both humans and agents read it every cycle — not buried in a wiki or lost in chat. The Lean Agentic Loop treats context as infrastructure: standing context (`CLAUDE.md`) plus a log of decisions (this folder).

## Decision

We keep Architecture Decision Records as numbered Markdown files in `docs/adr/`, one decision per file, using `.lal/adr-template.md`. New ADRs are proposed during `/lal-plan` for risky or far-reaching specs, and accepted when the work merges.

## Consequences

- Agents and reviewers can read the rationale behind the code, reducing repeated debates.
- Each significant decision costs a short write-up; trivial choices do not get an ADR.
- The `/lal-retro` digest can point at ADRs when a lesson should be encoded.
