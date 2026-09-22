<!-- Frontmatter hygiene: the store parses this line by line, not as YAML — everything after the first `:` on a line is the value, verbatim. A colon inside a value (e.g. `title: Foo: bar`) is fine. Do NOT quote values: quotes are kept as part of the value and will show up on the dashboard. -->
---
title: <short imperative title>
slug: <kebab-case-slug>
status: ready                 # ready | in_progress | shipped | abandoned
depends_on: []                # slugs of specs that must ship first (by slug, not filename); blank = none
type: feature
route: <foreground | background | spike>
business_value: <high | medium | low>
technical_certainty: <high | medium | low>
# created_at:                 # ISO8601 — the store stamps this itself when the spec is created; leave unset
outcome: <one observable metric or check that will prove the change worked in production>
# model:                      # optional — the Claude model a factory worker should use for this spec (an alias like sonnet or opus, or a full model name); absent = the project's route table
# Claim fields — set by /ag-next when the item is pulled; KEPT after ship so the
# claim→ship interval (cycle time) survives for /ag-retro:
claimed_by:                   # session id (the resume handle: claude --resume <id>)
label:                        # optional human label for the loop
claimed_at:                   # ISO8601, e.g. 2026-06-10T12:04:00Z
# Abandon fields — set by /ag-abandon when the spec is dropped; absent otherwise:
# abandoned_reason:           # why it was dropped (free text)
# abandoned_at:               # ISO8601
# Ship fields — set by the ship stage; absent until shipped:
# shipped_at:                 # ISO8601
---

<!-- The spec itself lives in Agentile Projects — there is no repo file
     until planning starts. /ag-plan creates docs/agentile/specs/<slug>/,
     holding a read-only SPEC.md snapshot, plan.md and supporting findings. -->

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
