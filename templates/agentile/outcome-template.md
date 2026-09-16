<!-- Frontmatter hygiene: every value must be valid YAML. No unquoted colons in `title` — reword with a dash or comma, or quote the value. -->
---
title: <what becomes true, not what gets built>
slug: <kebab-case-slug>
status: open                  # open | achieved | abandoned
rank:                         # integer set by /ag-prioritise; blank = unranked
created: <YYYY-MM-DD>
# Transition fields — set by the store, never by hand:
# achieved_at:                # ISO8601, via `ag-store outcome_achieve`
# abandoned_at:               # ISO8601, via `ag-store outcome_abandon`
# abandoned_reason:           # free text, via `ag-store outcome_abandon`
---

# <Title>

## Claim

<What will be true when this is achieved. A claim describes an outcome, not a
deliverable: "a buyer cannot reject us on identity grounds" passes; "provide
SSO" fails. Test — can you state the measure below without listing the specs?>

## Measure

<The observable evidence a human will judge this against. Not a spec count.>

## Stop rule

<The evidence that would make us abandon this line of work entirely.>

## Notes

<Optional. Evidence gathered, links, what changed the assessment over time.>
