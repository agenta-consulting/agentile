# Plan — <spec title>

Written by the plan stage into the spec's directory as `plan.md`. Review and
amend this file directly — the build stage follows what it says.

## Fit since shaping

<The spec was shaped against commit `<shaped_against>`. How many commits trunk
has moved since, which of them touched the spec's affected areas, and whether
the spec still fits the code as it is now. Adjust the approach here, or say
"Re-shape recommended: <why>" on the first line of this section when the
spec's assumptions no longer hold. "Shaped before shaping context was
recorded" when the spec has no `shaped_against`.>

## Files to touch

<The files this change creates or modifies, and why each.>

## Approach

<The implementation approach, in enough detail that a fresh-context builder
cannot misread the intent.>

## Test strategy

<Which gates from `.agentile/gates.json` prove this work, plus any new tests
to write.>

## Risks and unknowns

<What could go wrong; what is assumed; what to check before merging.>

## ADR

<Link any ADR drafted for this plan, or "none".>
