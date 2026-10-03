<!-- Frontmatter hygiene: every value here must be valid YAML. No unquoted colons in `title`, `outcome` or any other field — `title: Foo: bar` fails to parse and the claim tooling (bin/ag-claim, a real YAML parser) cannot pull the spec. Prefer rewording with a dash or comma ("Foo — bar"); quoting the value also works. -->
---
number: <NNNN>
title: <short decision title>
status: proposed
date: <YYYY-MM-DD>
---

# ADR-<NNNN>: <Title>

## Status

<proposed | accepted | superseded by ADR-NNNN>

## Context

<The forces at play: the problem, the constraints, the options considered. Written so a future reader understands *why* without needing the meeting.>

## Decision

<The choice made, stated plainly.>

## Consequences

<What becomes easier, what becomes harder, and what we are now committed to. Include the trade-offs we accepted.>
