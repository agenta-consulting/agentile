# The Agentile Store Protocol, version 1

Status: **normative** from plugin 0.24.0. This document is the contract between
Agentile and the place a project's backlog lives. Anything that implements it is
an Agentile store: Agentile Projects (the hosted web app), the local store that
ships with the plugin (`bin/ag-store-local`), or one you write over your own
database or tracker. Every skill reaches the store through one client,
`bin/ag-store`; a store that passes the conformance suite
(`dev/test-store-conformance.rb`) behaves, as far as every skill can tell,
exactly like every other.

The key words MUST, MUST NOT, SHOULD and MAY are used as in RFC 2119. Where this
document and an implementation disagree, this document wins and the
implementation has a bug; section 12 lists the known ones.

Contents:

1. What a store is for
2. Choosing a store: transports
3. Principles
4. The data model
5. State machines
6. Algorithms: claim, rank, dependencies, abandon, map, flow, brief
7. Canonical markdown
8. The HTTP binding: every endpoint
9. The process binding
10. Errors
11. Conformance and capabilities
12. Known gaps in current stores
13. Versioning

Appendix A maps every `ag-store` operation to its endpoint.

## 1. What a store is for

A store holds the **events** of the loop: things that are captured, decided,
claimed, asked and answered, possibly by people on other machines. The repo
holds the **artefacts**: `plan.md`, the `SPEC.md` snapshot, findings, ADRs and
the deploy log, which are reviewed as diffs and live beside the code.

| In the store | In the repo |
|---|---|
| Inbox stubs | `docs/agentile/specs/<slug>/plan.md` and `SPEC.md` |
| Specs: fields, status, rank, claim, dependencies | ADRs under `docs/adr/` |
| Outcomes | `docs/agentile/deploys.md` |
| Runs and run events | `.agentile/` configuration and playbooks |
| Checkpoints and their answers | `docs/agentile/brief.md` (a read-only copy) |
| The brief | |

A store MUST be the single source of truth for what it holds. Clients do not
cache between invocations, and a store that cannot be reached is an error, never
a reason to fall back to files. A silent fallback forks the backlog.

A store serves one or more **projects**. Every resource except the user belongs
to exactly one project, addressed by its slug.

## 2. Choosing a store: transports

A repo links to its store in `.agentile/store.md`. The frontmatter `url` picks
the transport; `project` names the project.

```markdown
---
url: https://agentile-projects.agentaconsulting.com    # HTTP binding (section 8)
project: my-app
---
```

| `url` | Transport | Store |
|---|---|---|
| `https://host[/prefix]` | HTTP (section 8) | any server implementing section 8 |
| `http://localhost…`, `http://127.0.0.1…`, `http://[::1]…`, `http://*.localhost…` | HTTP | a store running on this machine |
| `local` or `local:<path>` | process (section 9) | the bundled local store; data in `<path>` |
| `exec:<command line>` | process (section 9) | any program implementing section 9 |

The environment variable `AGENTILE_STORE_URL` overrides `url`.
`AGENTILE_PROJECTS_URL` is honoured as an older name for it.

**HTTP credentials.** The bearer token comes from `AGENTILE_STORE_TOKEN`, else
`AGENTILE_PROJECTS_TOKEN`, and is never written to a tracked file. Because
`store.md` is tracked, the client refuses to send the token over plain `http`
to anything but a loopback host unless `AGENTILE_STORE_ALLOW_HTTP=1` (or the
older `AGENTILE_PROJECTS_ALLOW_HTTP=1`) is set.

**Process stores** need no token, and never get one: the client removes
`AGENTILE_STORE_TOKEN` and `AGENTILE_PROJECTS_TOKEN` from the command's
environment, so a change to the tracked `url` cannot hand the token to a
command. The client starts the command for each operation and talks to it over
stdin and stdout (section 9). A process store holds its own credentials, for
example in its own environment variables. An `exec:` url runs a command named in
a tracked file, the same trust a repo already gives the commands in
`.agentile/gates.json`: review a change to it the way you would review a change
to a gate.

**The local store** keeps one JSON file per project. `local:<path>` names the
directory, resolved against the main checkout (not the current directory, so
every worktree reaches the same files); plain `local` means
`${XDG_DATA_HOME:-~/.local/share}/agentile/stores`.
It sits outside the repo on purpose: every worktree of a checkout sees the same
backlog, and the backlog never turns up in a diff. It is for one person on one
machine. A team that shares a backlog across machines needs an HTTP store. It
has no registry of projects: a project exists once anything has been written to
it, so it answers a mistyped project slug with an empty backlog instead of
`404`. `/ag-init` confirms the slug for that reason.

## 3. Principles

These decisions shape everything below.

1. **The spec's canonical markdown is the exchange format.** Specs and outcomes
   travel as frontmatter plus body (section 7). A store MAY decompose them into
   fields, as Agentile Projects does, but what goes in comes back out.
2. **Every state change is one transaction.** Claim, rank, ship, abandon with
   cascade, shape (create the spec and mark the stub) and opening a checkpoint
   (create it and pause the run) each MUST succeed or fail as a whole. Two
   concurrent claims MUST never both win the same spec.
3. **Illegal transitions are refused, not tolerated.** A request that would
   move a resource along an edge its state machine (section 5) does not have
   gets `409 conflict`. A repeat of a transition that already happened is
   allowed only where section 5 marks it idempotent.
4. **Derived views are computed, never stored.** Map, flow, blocked and
   dependents are calculated on every request so they cannot go stale.
5. **Times are UTC, second precision**, written `YYYY-MM-DDTHH:MM:SSZ`. A store
   refuses (`422`) a client-supplied time in any other form, such as `shaped_at`
   with an offset.
6. **Slugs are the identity of specs and outcomes**, unique within a project and
   matching `^[a-z0-9]+(-[a-z0-9]+)*$`. Inbox items, runs and checkpoints have
   integer ids, unique within the store.
7. **Who did it is recorded by the store, not claimed by the client.** The store
   attributes captures, shapes, claims and answers to the authenticated user
   (HTTP) or the user the client reports (process). Clients never send a user id
   for themselves.
8. **Unknown input is ignored, unknown output is ignored.** A store MUST accept
   and drop frontmatter keys and JSON fields it does not know. A client MUST
   ignore response fields it does not know. That is what lets either side grow
   without a protocol bump.

## 4. The data model

Types: `string`, `int`, `float`, `bool`, `time` (section 3.5), `slug`, `[T]` (a
JSON array), `T?` (may be `null`). Every field listed is present in responses,
`null` when unset, unless marked *optional*.

### 4.1 Project and user

| Field | Type | Meaning |
|---|---|---|
| `slug` | slug | the project's address |
| `name` | string | display name |
| `wip_limit` | int | how many specs may be `in_progress` at once; `0` means unlimited; default `1` |
| `brief` | string | the brief's markdown, without the generated outcomes section (6.8) |

A user has `user_id` (int), `name`, `email`, and one **role** per project:
`owner`, `member` or `viewer`. Owners and members are **writers**. Viewers may
call every read and nothing else. A store with no notion of users (the local
store) treats the single local user as `owner` of every project it holds.

### 4.2 Inbox item (a stub)

| Field | Type | Meaning |
|---|---|---|
| `id` | int | |
| `title` | string | one line, at most 80 characters, required |
| `text` | string | the rest; may be empty |
| `type` | enum | `feature` (default), `bug`, `chore`, `spike` |
| `status` | enum | `open`, `shaped`, `dropped` (5.2) |
| `serves` | slug? | outcome this stub serves |
| `captured_at` | time | |
| `captured_by` | string | display name of who captured it |
| `suggested_kind` | string? | the assist's guess at `type`, kept for the record |
| `duplicate_of` | int or slug? | what the capturer was warned it duplicates: an inbox id, or a ready spec's slug |
| `duplicate_of_type` | enum? | `inbox` or `spec`, saying which |
| `duplicate_probability` | float? | |
| `attachments` | [Attachment] | *optional*; `[]` when the store has no attachments |

### 4.3 Spec

The spec is the unit of work. Fields fall into four groups.

**Identity and triage**

| Field | Type | Meaning |
|---|---|---|
| `slug` | slug | required, immutable |
| `title` | string | required |
| `status` | enum | `ready`, `in_progress`, `shipped`, `abandoned` (5.1) |
| `type` | enum | `feature` (default), `bug`, `chore`, `spike` |
| `route` | enum? | `foreground`, `background`, `spike` |
| `business_value` | enum? | `high`, `medium`, `low` |
| `technical_certainty` | enum? | `high`, `medium`, `low` |
| `model` | string? | the model the spec should be built with, free text |
| `rank` | int? | position in the ready queue, lower first; `null` means unprioritised |
| `depends_on` | [slug] | specs that must ship first, sorted |
| `serves` | slug? | the outcome it serves |
| `tags` | [string] | free-form |
| `outcome` | string? | the one-line observable check that proves the spec worked |

**Shaping context** (new in protocol 1)

| Field | Type | Meaning |
|---|---|---|
| `shaped_against` | string? | the git commit (7 to 40 hex characters) trunk was at when the spec was shaped |
| `shaped_at` | time? | when that was |
| `source_inbox` | int? | the stub it was shaped from |
| `captured_by` | string? | email of who captured the stub, or created the spec |
| `shaped_by` | [string] | emails of everyone who shaped it |

`shaped_against` is what makes drift visible: when the spec is claimed, the
client compares it with trunk (6.9). The store only keeps the value.

**Claim and lifecycle** (written only by transitions, never by `PATCH`)

| Field | Type | Meaning |
|---|---|---|
| `claimed_by` | string? | the claim identity: a session id, `factory/<project>/<slug>`, `ag-run@host/pid` |
| `claimed_by_member` | string? | email of the user who made the claim |
| `claimed_at` | time? | |
| `label` | string? | a human label the claimer gave |
| `created_at` | time | |
| `shipped_at` | time? | |
| `abandoned_at` | time? | |
| `abandoned_reason` | string? | required when abandoned |
| `needs_review` | bool | *optional*; a store's own check thinks the spec needs a human look before building |
| `needs_review_reason` | string? | *optional* |

**Body**: `problem_why_now`, `acceptance_criteria`, `scope_in`, `scope_out`,
`edge_cases`, `affected_areas`, `open_questions`, `verification`, all strings,
`""` when empty. They are the sections of the canonical markdown (7.1).

**Two JSON shapes.** A *SpecSummary* is every field above except the body and
`abandoned_reason`, `needs_review_reason`, `captured_by` and `shaped_by`, plus:

- `path`: `"docs/agentile/specs/<slug>"`, where the spec's artefacts live in the repo;
- `prefix`: the same value as `rank`. It is the field's older name; skills
  written before protocol 1 read it. Stores MUST send both until protocol 2.
- `kind`: the same value as `type`, likewise kept for older clients.

A *SpecDetail* is the SpecSummary plus everything else, including the body.

### 4.4 Outcome

| Field | Type | Meaning |
|---|---|---|
| `slug` | slug | required |
| `title` | string | required |
| `status` | enum | `open`, `achieved`, `abandoned` (5.3) |
| `rank` | int? | |
| `created` | time | (named `created`, not `created_at`, for historical reasons) |
| `achieved_at`, `abandoned_at` | time? | |
| `claim`, `measure`, `stop_rule`, `notes` | string | the four sections (7.2); detail only |
| `abandoned_reason` | string? | detail only |
| `created_by` | string? | email; detail only |

An outcome is a bet, not a container: it has no progress field and nothing
derived is stored on it. Specs point at it through `serves`.

### 4.5 Run and run event

A run is one attempt by one runner to take one spec through the build. It
exists so that a process that dies, or a pause that outlives a session, leaves a
record another process can pick up.

| Field | Type | Meaning |
|---|---|---|
| `id` | int | |
| `spec` | slug | |
| `runner_id` | string | the claim identity of the runner |
| `session_id` | string? | a Claude session id, for `claude --resume` |
| `model` | string? | the model the run uses; set when the run opens, never changed |
| `status` | enum | `active`, `paused`, `shipped`, `failed`, `closed` (5.4) |
| `started_at`, `last_event_at` | time | |
| `ended_at` | time? | |
| `detail` | string | the latest event's detail, `""` when none |
| `events` | [RunEvent] | in order |

A RunEvent is `{event, at, detail}`, where `event` is one of `started`,
`claimed`, `paused`, `idle`, `shipped`, `failed`, `deployed`, `closed`.

A run is **live** while its status is `active` or `paused`. A spec has at most
one live run.

### 4.6 Checkpoint

A checkpoint is a question a paused build leaves for a person.

| Field | Type | Meaning |
|---|---|---|
| `id` | int | |
| `spec` | slug | |
| `run_id` | int | |
| `seq` | int | 1, 2, 3… per spec, across all its runs |
| `ref` | string | `"<slug> #<seq, three digits> <reason>"`, e.g. `"rate-limit #002 question"` |
| `reason` | enum | `plan_review`, `build_blocked`, `build_checkpoint`, `gate_failure`, `verify_checkpoint`, `ship_approval`, `question` |
| `asked_by` | enum | `plan`, `build`, `builder`, `reviewer`, `verify`, `ship` |
| `ask` | string | the question, in the checkpoint ask format of `/ag-build` |
| `asked_at` | time | |
| `session_id` | string | the asking session, `""` when unknown |
| `status` | enum | `open`, `answered` |
| `answer` | string | `""` until answered |
| `answered_by` | string | display name, `""` until answered |
| `answered_at` | time? | |
| `priority` | enum? | *optional*: `needs_human`, `routine`, `unclear` |
| `layout` | object? | *optional*: a store's parse of the ask for display; clients MUST NOT depend on it |

### 4.7 Attachment (optional capability)

`{id, filename, content_type, byte_size, checksum, url}`, where `url` is a GET
the same credentials can fetch. Stores without the `attachments` capability
(section 11) always send `[]`.

## 5. State machines

Every edge not listed is refused with `409 conflict`, except where marked
*idempotent*: then a repeat returns `200` and changes nothing.

### 5.1 Spec

```
              claim                    ship
   ready ─────────────▶ in_progress ─────────▶ shipped
     ▲  ◀───────────────     │
     │      release          │ abandon
     │                       ▼
     └──── abandon ───▶  abandoned
```

| Transition | From | To | Effects |
|---|---|---|---|
| create, shape | (none) | `ready` | `created_at` set. A `status` other than `ready` in the markdown is `422`. |
| claim | `ready`, unclaimed | `in_progress` | `claimed_by`, `claimed_by_member`, `claimed_at`, `label` set; a run opens (6.1) |
| release | `in_progress` | `ready` | claim fields and `label` cleared; rank kept; live run closed with event `closed`, detail `"released"`. From `ready`: *idempotent*. |
| ship | `in_progress` | `shipped` | `shipped_at` set; claim fields kept as the record; live run closed with event `shipped` |
| abandon | `ready`, `in_progress` | `abandoned` | `abandoned_at`, `abandoned_reason` set; claim fields cleared; live run closed with event `closed`, detail `"abandoned"` |

`shipped` and `abandoned` are terminal. Work that turns out wrong after it
shipped comes back as a new stub; the old spec MAY gain `superseded_by` in a
later protocol version.

A closed spec's `rank` is meaningless. A store MAY keep the old value or clear
it, and clients MUST ignore it.

### 5.2 Inbox item

| Transition | From | To | Effects |
|---|---|---|---|
| add | (none) | `open` | |
| shape | `open` | `shaped` | a spec is created in the same transaction (8.4) |
| drop | `open` | `dropped` | From `dropped`: *idempotent*. From `shaped`: `409`. |

### 5.3 Outcome

| Transition | From | To |
|---|---|---|
| create | (none) | `open` (a different `status` in the markdown is `422`) |
| achieve | `open` | `achieved`, `achieved_at` set |
| abandon | `open` | `abandoned`, `abandoned_at` and `abandoned_reason` set |

Abandoning an outcome leaves the specs that serve it alone.

### 5.4 Run

| Event | From | To | `ended_at` |
|---|---|---|---|
| `started`, `claimed`, `idle` | live | `active` | |
| `paused` | live | `paused` | |
| `shipped` | live | `shipped` | set |
| `failed` | live | `failed` | set |
| `deployed`, `closed` | live | `closed` | set |

Every event sets `last_event_at` and, when it has one, `detail`. An event for a
run that is not live is `409`. A new attempt at the same spec opens a new run.

### 5.5 Checkpoint

| Transition | From | To | Effects |
|---|---|---|---|
| open | (none) | `open` | the run must be live (else `409`); the run gets event `paused`, detail = the reason |
| answer | `open` | `answered` | answer, `answered_by`, `answered_at` set. If the run is `paused` and none of its other checkpoints is open, the run gets event `idle`, detail `"checkpoint answered"`. A second answer is `409`. |

Open checkpoints never block a claim, ship, release or abandon. Closing a run
with checkpoints still open leaves them open, as a record of what was asked.

## 6. Algorithms

### 6.1 Claim

Input: `identity` (required), `label`, `wip`, `slug`, `model`.
Output: `{"result": R, "run_id": int?}` with status `200`, where `R` is a spec
slug on success and otherwise one of the result codes below. The result codes
are answers, not errors.

The whole procedure is one transaction that holds a write lock from its first
read:

1. **Re-claim.** If `slug` is given and that spec is `in_progress` with
   `claimed_by == identity`, return the slug and the id of its live run (open a
   new run if it has none). This makes a claim whose response was lost safe to
   repeat.
2. **WIP.** Let `limit` be `wip` if the client sent it, else the project's
   `wip_limit`. If `limit > 0` and the project has `limit` or more specs
   `in_progress`, return `WIP_FULL`. The count is project-wide, not per identity.
3. **Choose.**
   - With `slug`: if no such spec, or it is `shipped` or `abandoned`, return
     `NOT_FOUND`. If it is `in_progress` (under another identity), return
     `TAKEN`. If any of its `depends_on` is not `shipped`, return `BLOCKED`.
     Rank is ignored: an unranked spec may be claimed by name.
   - Without `slug`: take the `ready` specs. None: `NONE`. None of them ranked:
     `UNPRIORITISED`. None of the ranked ones has every dependency `shipped`:
     `BLOCKED`. Otherwise pick the lowest `rank`, ties broken by `slug`.
     Unranked specs are never picked from the queue.
4. **Take it.** Set `status = in_progress`, `claimed_by = identity`,
   `claimed_by_member` = the user, `claimed_at` = now, `label` (`""` stored as
   `null`). If the spec had no rank, give it `max(rank of ready and
   in_progress specs) + 1`, or `1`, so it shows up in the queue order.
5. **Open the run.** `runner_id = identity`, `session_id = identity`, `model`
   as sent, `status = active`, with events `started` then `claimed`.

A store that cannot hold a lock across the transaction MUST use a conditional
write (update only where `status = ready` and `claimed_by` is empty) and report
`TAKEN` when it loses.

An abandoned dependency is not shipped, so it blocks its dependents for good.
`/ag-abandon` deals with that by cascading or by removing the link.

### 6.2 Rank

`PUT /specs/rank` with `{"slugs": [s1, s2, …]}`:

1. Drop repeated slugs, keeping the first. Each slug MUST exist (`404`) and be
   `ready` or `in_progress` (`409`, naming each closed slug).
2. The listed specs get ranks `1…k` in that order.
3. Every other `ready` or `in_progress` spec that already had a rank follows,
   `k+1…`, in its previous order. Unranked specs that were not listed stay
   unranked.

The response is `{"ranked": [slug…]}`: every active ranked spec, in order.
Ranks after this call are dense. Outcomes rank the same way over `open`
outcomes, and listing a closed outcome is allowed.

### 6.3 Dependencies

`depends_on` is a set of slugs in the same project. Each MUST exist when it is
written (`404` otherwise). A store MUST refuse (`422`) a dependency on the spec
itself and any write that would create a cycle.

- `deps <slug>`: the direct dependencies, any status, sorted.
- `dependents <slug>`: every spec that depends on `<slug>` directly or through
  others, found breadth-first over `ready` and `in_progress` specs only (a
  closed spec ends the walk), sorted, without `<slug>` itself.

### 6.4 Abandon with cascade

`abandon` takes `reason` (required, `422` if blank) and optional `cascade`, a
list of slugs. In one transaction the target is abandoned, then each cascade
slug that names a `ready` or `in_progress` spec is abandoned with the **same**
reason. Cascade slugs that name nothing, or a closed spec, are skipped without
error. The cascade does not recurse: the client computes the list, normally from
`dependents`, and decides per dependent.

### 6.5 Blocked

A spec is **blocked** when it is `ready` and at least one of its `depends_on` is
not `shipped`.

### 6.6 Map

`GET /map` returns, in this key order:

```json
{
  "outcomes": [
    { "slug": "faster-onboarding", "title": "…", "status": "open", "rank": 1,
      "created": "…Z", "achieved_at": null, "abandoned_at": null,
      "specs": { "ready": [], "in_progress": [], "shipped": [], "abandoned": [] },
      "blocked": [] }
  ],
  "unlinked": { "ready": [], "in_progress": [], "shipped": [], "abandoned": [], "blocked": [] },
  "orphaned": {},
  "tags": { "billing": ["a", "b"] }
}
```

`outcomes` lists every outcome in rank order (unranked last, then by slug).
Each spec appears under the outcome it serves, bucketed by status, slugs sorted;
specs that serve none go under `unlinked`. `blocked` (6.5) lists slugs a second
time, on purpose. `orphaned` maps an outcome slug that no longer exists to the
specs still pointing at it; a store that enforces the reference sends `{}`.
`tags` maps each tag to its specs, keys and values sorted.

### 6.7 Flow

`GET /flow` returns one object per spec (every status, sorted by slug);
`GET /flow/<slug>` returns one.

```json
{ "slug": "a", "status": "shipped", "in_progress": false,
  "created_at": "…Z", "claimed_at": "…Z", "shipped_at": "…Z",
  "queue_wait_seconds": 12, "cycle_seconds": 30, "human_wait_seconds": 5,
  "agent_seconds": 25, "lead_seconds": 42,
  "checkpoint_count": 1, "open_checkpoint_count": 0,
  "checkpoints": [ { "reason": "ship_approval", "asked_by": "ship", "status": "answered",
                     "asked_at": "…Z", "answered_at": "…Z", "wait_seconds": 5 } ] }
```

- `in_progress` is true when `claimed_at` is set and `shipped_at` is not.
- `queue_wait_seconds` = `claimed_at − created_at`.
- `cycle_seconds` = `(shipped_at, or now while in progress) − claimed_at`.
- A checkpoint waits from `asked_at` until `answered_at`, or the end of the
  cycle, or now. `human_wait_seconds` is the sum of those waits.
- `agent_seconds` = `max(cycle − human_wait, 0)`.
- `lead_seconds` = `shipped_at − created_at`.

Every duration is an integer number of seconds, or `null` when an end is
missing. `human_wait_seconds` and `agent_seconds` are `null` when
`cycle_seconds` is. Checkpoints are in `seq` order.

### 6.8 Brief

`GET /brief` returns `text/markdown`: the project's `brief` (or `# <name>` when
it is blank) with a generated section

```
## Prioritised outcomes

1. **<title>** — <claim, trimmed>
```

listing open outcomes in rank order, or the line `_No open outcomes yet._` when
there are none. If the brief already has a line that is exactly
`## Prioritised outcomes`, everything from that line up to the next `## `
heading (or the end) is replaced; otherwise the section is appended after a
blank line. The brief is edited in the store; the repo copy is read-only.

### 6.9 Drift (client side)

The store keeps `shaped_against`; the client measures drift. When `/ag-build`
claims a spec that has one, it counts the commits on trunk since that commit
and the files they touched, and compares the paths with the spec's
`affected_areas`. That check lives in the skill because only the client has the
repo. A spec with no `shaped_against` was shaped before protocol 1 and is built
without the check.

## 7. Canonical markdown

### 7.1 Spec

```markdown
---
title: Rate-limit the login endpoint
slug: rate-limit-login
status: ready
depends_on: [session-store]
type: feature
route: background
business_value: high
technical_certainty: high
rank: 3
created_at: 2026-10-12T01:00:00Z
serves: fewer-account-takeovers
tags: [security, auth]
outcome: Brute-force attempts in the auth log drop to zero within a week
shaped_against: 3f9c2a1
shaped_at: 2026-10-12T01:00:00Z
---

# Rate-limit the login endpoint

## Problem / why now

…

## Acceptance criteria

…

## Scope boundary

**In scope:** …

**Out of scope:** …

## Edge cases and failure paths

…

## Affected areas

…

## Open questions

…

## Verification

…
```

**Frontmatter grammar.** The block starts at the first byte (after an optional
UTF-8 byte-order mark) with a line `---` and ends at the next line `---`. Each
line inside is `key: value`, where `key` matches `[A-Za-z_]+`. The value is the
rest of the line, trimmed, taken literally (quotes are characters, not syntax).
A value written `[a, b, c]` is a list, split on commas and trimmed, empty items
dropped. This is a strict subset of YAML; multi-line values and nested
structures are not part of it. Lines that do not match are ignored.

**On input** (create and shape) a store reads `slug`, `title`, `status` (only
`ready` or absent, 5.1), `type`, `route`, `model`, `business_value`,
`technical_certainty`, `outcome`, `label`, `depends_on`, `serves`, `tags`,
`shaped_against` and `shaped_at`. A key that is present but blank sets the field
to `null`. `title` falls back to the first `# ` heading of the body. Every other
key is ignored on input: rank, claim and lifecycle fields are set only by their
transitions, and attribution fields only by the store.

**Sections.** The body is split at lines beginning `## `. The seven headings
are exactly `Problem / why now`, `Acceptance criteria`, `Scope boundary`,
`Edge cases and failure paths`, `Affected areas`, `Open questions` and
`Verification`. Inside `Scope boundary`, the text after `**In scope:**` up to
`**Out of scope:**` is `scope_in`, the rest is `scope_out`. A missing section is
`""`. Unknown sections are dropped.

**On output** (`GET /specs/<slug>.md`) a store writes the frontmatter keys in
this order, leaving out any that is `null`, `""` or `[]`: `title`, `slug`,
`status`, `depends_on`, `type`, `route`, `model`, `business_value`,
`technical_certainty`, `rank`, `created_at`, `serves`, `tags`, `outcome`,
`shaped_against`, `shaped_at`, `claimed_by`, `label`, `claimed_at`,
`claimed_by_member`, `abandoned_reason`, `abandoned_at`, `shipped_at`,
`captured_by`, `shaped_by`, `source_inbox`. Lists are written `[a, b]`. Then a
blank line, `# <title>`, and all seven sections in the order above, each present
even when empty, separated by blank lines, ending with a newline.

**One line per value.** A frontmatter value never holds a line break. A store
MUST refuse (`422`) a line break in a value the client chose for the
frontmatter: `title`, `model`, `outcome`, `label`, `shaped_against`, `shaped_at`
on a spec, `title` on an outcome. Free text that reaches the frontmatter from a
transition (`abandoned_reason`, and a claim's `label`) MAY hold line breaks in
the store and in JSON, but is written to the markdown with every whitespace run
that contains a line break replaced by one space. Without that rule a reason
containing `---` would end the block and forge keys.

### 7.2 Outcome

Frontmatter `title`, `slug`, `status` (only `open` or absent on input), then
`# <title>` and the four sections `## Claim`, `## Measure`, `## Stop rule`,
`## Notes`. On output the frontmatter order is `title`, `slug`, `status`,
`rank`, `created`, `achieved_at`, `abandoned_at`, `abandoned_reason`,
`created_by`, with empty values left out, and all four sections are present.

## 8. The HTTP binding

All paths are under `<url>/api/v1`. Project paths start
`/projects/<project>`; every interpolated path segment is percent-encoded on its
own. Requests carry `Authorization: Bearer <token>` and
`Accept: application/json, text/markdown`. JSON bodies use
`Content-Type: application/json`; markdown bodies are sent raw with
`Content-Type: text/markdown`, and a store MUST read a markdown body whatever
the content type says. Query parameters with empty values are left out.

Responses are JSON, except the three markdown reads (`.md` and `/brief`), which
are `text/markdown`. Errors follow section 10.

In the tables, **R** marks a read (any role), **W** a write (owner or member).

### 8.1 Account and project

| | Method and path | Request | Response |
|---|---|---|---|
| R | `GET /me` | | `{user_id, name, email, projects: [{slug, role, archived}]}`; projects sorted by slug, archived ones included with `archived: true`. A store MAY add fields per project (Agentile Projects adds `factory_enabled`, `factory_workers`). Needs no project. |
| R | `GET /projects/:p/doctor` | | `{project, role, reachable: true, protocol: 1, store: "<name>", capabilities: [...]}` (section 11) |
| R | `GET /projects/:p/brief` | | markdown (6.8) |
| W | `PUT /projects/:p/brief` | markdown | `{ok: true}`; replaces the project's `brief` (the generated outcomes section is regenerated on read, so a client may send it or not) |
| R | `GET /projects/:p/map` | | 6.6 |
| R | `GET /projects/:p/flow` | | 6.7, array |
| R | `GET /projects/:p/flow/:slug` | | 6.7, one object; `404` if no such spec |

A project the user cannot see, an archived project and an unknown slug all
answer `404`, never `403`, so a store does not reveal which projects exist.

### 8.2 Specs

| | Method and path | Request | Response |
|---|---|---|---|
| R | `GET /projects/:p/specs?pool=&status=` | `pool`: `active` (default; `ready` + `in_progress`), `done` (`shipped`), `abandoned`. `status` filters within the pool. Unknown pool: `422`. | [SpecSummary], in queue order: ranked by `rank`, unranked last, ties by slug |
| R | `GET /projects/:p/specs/:slug` | | SpecDetail |
| R | `GET /projects/:p/specs/:slug.md` | | markdown (7.1), whatever `Accept` says |
| W | `POST /projects/:p/specs` | markdown | `201`, SpecSummary. Duplicate or malformed slug, blank title, bad enum, non-ready status: `422`. Unknown `depends_on` or `serves`: `404`. Nothing is created on error. |
| W | `PATCH /projects/:p/specs/:slug` | JSON object, below | SpecSummary |
| W | `PUT /projects/:p/specs/rank` | `{slugs}` | `{ranked}` (6.2) |
| W | `POST /projects/:p/specs/claim` | `{identity, label?, wip?, slug?, model?}` | `200`, `{result, run_id}` (6.1). Blank identity: `422`. |
| W | `POST /projects/:p/specs/:slug/release` | | SpecSummary (5.1) |
| W | `POST /projects/:p/specs/:slug/ship` | `{run_id?}` | SpecSummary (5.1); a `run_id` of another spec's run is `422` |
| W | `POST /projects/:p/specs/:slug/abandon` | `{reason, cascade?}` | SpecSummary of the target (6.4) |
| R | `GET /projects/:p/specs/:slug/deps` | | [slug] (6.3) |
| R | `GET /projects/:p/specs/:slug/dependents` | | [slug] (6.3) |
| R | `GET /projects/:p/specs/:slug/checkpoints` | | [Checkpoint] for the spec, all runs, in `seq` order |

**PATCH.** Writable keys: `title`, `type` (or `kind`), `route`, `model`,
`business_value`, `technical_certainty`, `label`, `outcome`, `serves`,
`shaped_against`, `shaped_at`, `needs_review`, `abandoned_reason`, the eight
body fields, and the lists `tags`, `depends_on` and `shaped_by`. A list may be
sent as a JSON array or as the string `"[a, b]"` and replaces the old list.
`serves: ""` clears it. A blank `title` is `422`. `status` or `rank` in the body
is `422` (they change only through their transitions). Unknown keys are ignored. The whole patch is
one transaction.

### 8.3 Outcomes

| | Method and path | Request | Response |
|---|---|---|---|
| R | `GET /projects/:p/outcomes?status=` | | [Outcome] (no sections), rank order; every status unless filtered |
| R | `GET /projects/:p/outcomes/:slug` | | Outcome with sections and detail fields |
| R | `GET /projects/:p/outcomes/:slug.md` | | markdown (7.2) |
| W | `POST /projects/:p/outcomes` | markdown | `201`, Outcome |
| W | `PATCH /projects/:p/outcomes/:slug` | `title`, `claim`, `measure`, `stop_rule`, `notes`, `abandoned_reason` | Outcome; `status` or `rank`: `422` |
| W | `PUT /projects/:p/outcomes/rank` | `{slugs}` | `{ranked}`: every ranked outcome, any status |
| W | `POST /projects/:p/outcomes/:slug/achieve` | | Outcome |
| W | `POST /projects/:p/outcomes/:slug/abandon` | `{reason}` | Outcome |

### 8.4 Inbox

| | Method and path | Request | Response |
|---|---|---|---|
| R | `GET /projects/:p/inbox?status=` | `status` defaults to `open`; an unknown value returns `[]` | [InboxItem], newest first |
| W | `POST /projects/:p/inbox` | `{text, title?, type?, serves?, suggested_kind?, duplicate_of?, duplicate_of_type?, duplicate_probability?}` (`kind` accepted for `type`) | `201`, `{ok: true, id}`. Without `title`, the first sentence of `text`'s first line, trailing `.!?` removed, cut to 80 characters. Without `duplicate_of_type`, an all-digit `duplicate_of` is an inbox id and anything else a spec slug; either must exist (`404`). |
| W | `POST /projects/:p/inbox/assist` | `{text}` | `{title, text, kind, serves_outcome_slug, duplicate_of, duplicate_of_type, duplicate_probability, judgment_id}`; saves nothing (8.4.1) |
| W | `POST /projects/:p/inbox/:id/shape` | spec markdown | `201`, SpecSummary. Creates the spec as `POST /specs` would, with `source_inbox` and `captured_by` from the stub and the user added to `shaped_by`, and marks the stub `shaped`, all in one transaction. A stub that is not `open`: `409`. |
| W | `POST /projects/:p/inbox/:id/drop` | | `{ok: true}` (5.2) |

**8.4.1 Assist** is the capture helper: tidy the line into a title and a
paragraph, guess its kind and outcome, and look for a likely duplicate among
open stubs and ready specs. It is advisory. Every field except `title` and
`text` MAY be `null`, and a store with no model behind it returns a plain tidy
and nulls. `duplicate_of` is an inbox id (int) when `duplicate_of_type` is
`inbox` and a spec slug when it is `spec`. `duplicate_probability` MAY be sent
even when no duplicate is reported.

### 8.5 Runs and checkpoints

| | Method and path | Request | Response |
|---|---|---|---|
| R | `GET /projects/:p/runs?spec=&status=` | `status=active` means live (`active` or `paused`); `status=closed` means not live; any other value matches exactly | [Run] with events, newest `started_at` first |
| W | `POST /projects/:p/runs` | `{spec, runner_id, session_id?, model?, detail?}` | `201`, Run, with a `started` event. The spec must be `in_progress` and have no live run, else `409`. |
| W | `POST /projects/:p/runs/:id/events` | `{event, detail?}` | `200`, Run (5.4) |
| W | `POST /projects/:p/runs/:id/close` | `{detail?}` | `200`, Run; the same as event `closed` |
| W | `POST /projects/:p/runs/:id/checkpoints` | `{reason, asked_by, session_id?, ask}` | `201`, Checkpoint (5.5) |
| W | `POST /projects/:p/checkpoints/:id/answer` | `{answer, by?}` | Checkpoint (5.5). `by` is an email; if it is not a member of the project the store records the authenticated user instead. Blank answer: `422`. |

## 9. The process binding

A process store is a program. For each operation the client starts it with the
command line from `exec:<command line>` (split like a shell would, without
running a shell), writes one JSON request to its stdin, closes stdin, and reads
one JSON response from stdout. The program MUST finish within 60 seconds; the
client kills it (and its process group) after that and fails the operation
with exit 2. `AGENTILE_STORE_TOKEN` and `AGENTILE_PROJECTS_TOKEN` are removed
from its environment (section 2). `AGENTILE_STORE_TIMEOUT` sets a different
deadline in seconds.

Request:

```json
{
  "protocol": 1,
  "method": "POST",
  "path": "/projects/my-app/specs/claim",
  "query": { "status": "ready" },
  "content_type": "application/json",
  "body": { "identity": "sess-1", "label": "" },
  "user": { "email": "keith@example.com", "name": "Keith" },
  "config": { "project": "my-app", "wip_limit": "2" }
}
```

- `method`, `path` (without `/api/v1`), `query` and the body are exactly what
  the HTTP binding would send. A markdown body is a JSON string with
  `content_type: "text/markdown"`.
- `user` is the person at the keyboard, from `git config user.email` and
  `user.name`. A process store attributes writes to it. It is not
  authentication; a process store that needs authentication does its own.
- `config` is the frontmatter of `.agentile/store.md` minus `url`, so a store
  can take options there (the local store reads `wip_limit`).

Response:

```json
{ "status": 200, "content_type": "application/json", "body": { "result": "rate-limit-login", "run_id": 7 } }
```

`status` and the body follow the HTTP binding exactly, errors included. A
markdown body is a JSON string with `content_type: "text/markdown"`. If the
program exits non-zero, or prints something that is not one JSON object, the
client reports a store failure (exit 2) with the first lines of its stderr.

The process binding is the shortest route from any backend to a working store:
a script over a SQLite file, a team tracker's API, or a spreadsheet. The local
store (`bin/ag-store-local`) is the reference implementation: about 850 lines
of Ruby with no gems.

**Concurrency.** Process stores run as several processes at once (several
sessions, a factory). A process store MUST make each request a transaction
against its data, for example with an exclusive file lock held from first read
to last write, as the local store does.

## 10. Errors

Every error has a JSON body `{"error": "<code>", "detail": "<sentence>"}`.

| Status | `error` | When |
|---|---|---|
| 401 | `unauthorized` | missing, malformed, unknown or revoked token |
| 403 | `forbidden` | a viewer attempted a write |
| 404 | `not_found` | unknown project (or one the user cannot see), spec, outcome, stub, run, checkpoint, or a referenced slug |
| 409 | `conflict` | an edge the state machine does not have; a rank of a closed spec; a checkpoint on a run that is not live; a second answer |
| 422 | `invalid` | a missing or malformed field, a bad enum, a duplicate slug, a cycle, a line break in a frontmatter value, `status` or `rank` in a `PATCH` |
| 500 | `internal` | the store failed; it MUST NOT have changed anything |

A store MAY use a more specific `error` string (`invalid_encoding`,
`unprocessable`) as long as the status is right; clients branch on the status.
The client (`ag-store`) exits `1` on any error status other than `401`, and
`2` on `401`, a transport failure, a process store that crashes or prints
something other than a response, or a configuration problem, printing `detail`
to stderr.

## 11. Conformance and capabilities

A store **conforms** to protocol 1 when `dev/test-store-conformance.rb` passes
against it:

```
ruby dev/test-store-conformance.rb                       # the bundled local store, in a temp dir
ruby dev/test-store-conformance.rb --url exec:./my-store # your process store
AGENTILE_STORE_TOKEN=… ruby dev/test-store-conformance.rb --url https://store.example --project scratch
```

The suite drives `bin/ag-store`, the same client every skill uses, so it tests
what skills see. Against an HTTP store it needs a scratch project it may fill
with test data; it never deletes anything.

`doctor` reports `protocol` (`1`), `store` (a name, e.g. `agentile-projects`,
`local`) and `capabilities`, a list from:

| Capability | Meaning |
|---|---|
| `users` | real users and roles; without it, everything is attributed to the process user |
| `assist-model` | `inbox/assist` uses a language model; without it, assist is a plain tidy |
| `attachments` | stubs and specs carry images |
| `push` | the store pushes live events to clients (Agentile Projects: ActionCable, used by the factory) |
| `review-check` | the store sets `needs_review` after a claim |
| `checkpoint-priority` | the store triages checkpoints into `priority` |

Skills MUST work against a store with no capabilities at all. Capabilities only
switch on extras.

## 12. Known gaps in current stores

Agentile Projects at commit `521a305` differs from protocol 1 in these ways.
Each was confirmed by running the conformance suite against a copy of it on
2026-10-12, except G5 (no `ag-store` operation sends an event to a run by id),
which comes from reading its source, and G9 and G10, which the client covers. The conformance suite reports each one;
until they are fixed it runs against Agentile Projects with `--allow-gaps` to
treat them as warnings.

| # | Protocol 1 says | Agentile Projects does |
|---|---|---|
| G1 | release, ship and abandon follow 5.1 and refuse other edges with `409` | accepts any edge: a shipped spec can be released or re-shipped |
| G2 | create accepts only `status: ready` | accepts any valid status |
| G3 | a targeted claim by the identity that holds the spec returns the slug (6.1 step 1) | returns `TAKEN` |
| G4 | outcome achieve and abandon only from `open` | no precondition |
| G5 | an event on a run that is not live is `409` | accepted, and can revive the run |
| G6 | `POST /runs` needs an `in_progress` spec with no live run | no check |
| G7 | outcome slugs match the slug pattern | not validated |
| G8 | dependencies refuse self-reference and cycles | not checked |
| G9 | SpecSummary has `rank` and `type` as well as `prefix` and `kind` | `prefix` and `kind` only (the client adds `rank` and `type`) |
| G10 | `doctor` reports `protocol`, `store`, `capabilities` | not yet (the client assumes protocol 1, store `agentile-projects`) |
| G11 | spec markdown carries `shaped_against` and `shaped_at` | dropped on input |
| G12 | shaping or dropping a stub that is not `open` is `409` (dropping a dropped one is idempotent) | re-shapes a shaped stub, and drops a shaped one |
| G13 | `PUT /projects/:p/brief` replaces the brief | no such endpoint; the brief is edited in the web UI only |
| G14 | outcome create accepts only `status: open` | takes `status` (and `rank`) from the frontmatter |
| G15 | a stub's `duplicate_of` may be a spec slug, with `duplicate_of_type` | takes only an inbox id: a spec slug is `404`, so the client saves the stub without the duplicate note |
| G16 | a line break in a frontmatter value is refused or flattened (7.1) | writes an abandon reason with line breaks into the frontmatter as is, so `spec_read` returns a broken block |

G9 and G10 are smoothed over in the client, so skills see protocol 1 today. G11
matters most: until it is fixed, a spec shaped into Agentile Projects loses its
`shaped_against`, and the drift check (6.9) has nothing to compare.

## 13. Versioning

`protocol` is an integer. Additions (new optional fields, new capabilities, new
endpoints) do not change it; section 3.8 is what makes that safe. A change that
breaks an existing client (a renamed field, a stricter rule that turns a valid
request into an error, a removed endpoint) is protocol 2, and the client will
refuse a store whose `doctor` reports a protocol it does not know.

## Appendix A. `ag-store` operations

| Operation | Endpoint | `ag-store` prints |
|---|---|---|
| `whoami` | `GET /me` | the object |
| `doctor` | `GET /doctor` | the object plus `host` (HTTP) or `command` (process) |
| `brief_sync --dir d` | `GET /brief` | writes `d/brief.md`, prints the path |
| `brief_write` (markdown on stdin) | `PUT /brief` | `{ok: true}` |
| `map` | `GET /map` | the object |
| `flow [slug]` | `GET /flow[/slug]` | the array or object |
| `inbox_list [--status s]` | `GET /inbox` | the array |
| `inbox_add <text> [--title t] [--type k] [--serves o] …` | `POST /inbox` | the new id |
| `inbox_assist <text>` | `POST /inbox/assist` | the object |
| `inbox_shape <id>` (markdown on stdin) | `POST /inbox/:id/shape` | the slug |
| `inbox_drop <id>` | `POST /inbox/:id/drop` | `true` |
| `spec_list [--status s] [--pool p]` | `GET /specs` | the array |
| `spec_read <slug>` | `GET /specs/:slug.md` | the markdown, as a JSON string |
| `spec_create` (markdown on stdin) | `POST /specs` | the slug |
| `spec_write <slug> --set k=v …` | `PATCH /specs/:slug` | the SpecSummary |
| `rank <slug>…` | `PUT /specs/rank` | `{ranked}` |
| `claim <identity> [label] [wip] [--spec s] [--model m]` | `POST /specs/claim` | the result string |
| `release <slug>`, `ship <slug>` | `POST …/release`, `…/ship` | the SpecSummary |
| `abandon <slug> --reason r [--cascade "[a, b]"]` | `POST …/abandon` | the SpecSummary |
| `deps <slug>`, `dependents <slug>` | `GET …/deps`, `…/dependents` | the array |
| `outcome_list`, `outcome_read`, `outcome_create`, `outcome_write`, `outcome_rank`, `outcome_achieve`, `outcome_abandon` | 8.3 | as `spec_*`; create prints the slug |
| `checkpoint_open <slug> <reason> --by b` (ask on stdin) | finds or opens the live run, then `POST /runs/:id/checkpoints` | the id |
| `checkpoint_list <slug>`, `checkpoint_open_count <slug>` | `GET /specs/:slug/checkpoints` | the array; the count of entries not `answered` |
| `checkpoint_answer <id> --by b` (answer on stdin) | `POST /checkpoints/:id/answer` | the Checkpoint |
| `run_event <event> --spec s` | finds or opens the live run, then `POST /runs/:id/events` | `last_event_at` |
| `run_list [--spec s] [--status st]` | `GET /runs` | the array |
| `run_close --spec s` | finds the live run, then `POST /runs/:id/close` | the Run |
| `promote <slug> --dir d` | none: creates `d/specs/<slug>/` | the path |

"Finds the live run" means: the live run of the spec whose `runner_id` is the
identity (`--runner`, else `AGENTILE_RUNNER_ID`, else `CLAUDE_SESSION_ID`), else
the newest live run of the spec.
