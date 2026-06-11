---
title: <short imperative title>
slug: <kebab-case-slug>
status: ready                 # ready | in_progress | shipped | abandoned
depends_on: []                # slugs of specs that must ship first (by slug, not filename); blank = none
type: feature
route: <foreground | background | spike>
business_value: <high | medium | low>
technical_certainty: <high | medium | low>
created: <YYYY-MM-DD>
# Claim fields — set by /ag-next when the item is pulled; blank until claimed:
claimed_by:                   # session id (the resume handle: claude --resume <id>)
label:                        # optional human label for the loop
claimed_at:                   # ISO8601, e.g. 2026-06-10T12:04:00Z
# Abandon fields — set by /ag-abandon when the spec is dropped; absent otherwise:
# abandoned_reason:           # why it was dropped (free text)
# abandoned_at:               # ISO8601
---

# <Title>

## Problem / why now

<Who is this for, what hurts, and why it matters this cycle.>

## Acceptance criteria

<Observable, checkable statements of what "done" looks like.>

- [ ] <criterion>
- [ ] <criterion>

## Scope boundary

**In scope:** <what this work covers.>

**Out of scope:** <what is explicitly excluded so the work can't balloon.>

## Edge cases and failure paths

<What must not be assumed; what happens when things go wrong.>

## Affected areas

<Files, services, or data the change likely touches.>

## Open questions

<Anything still unknown. If any survive, this becomes a spike rather than a build.>

## Verification

<How we will prove the outcome — the test(s) and the metric from the problem statement.>
