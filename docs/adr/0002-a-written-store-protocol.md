---
number: 0002
title: The store is a written protocol with two transports, a reference local store and a conformance suite
status: proposed
date: 2026-10-12
---

# ADR-0002: The store is a written protocol with two transports, a reference local store and a conformance suite

## Status

proposed

## Context

Since 0.20.0 the backlog has lived in one place, Agentile Projects, and
`bin/ag-store` was a thin client over that app's JSON API. The contract between
the skills and the store existed only as that app's behaviour. Three problems
followed:

- Nobody could run Agentile without an account on the hosted app. The `local`
  and `airtable` adapters removed in 0.20.0 had no successor.
- The app's behaviour was the spec, including behaviour nobody chose: a shipped
  spec could be released or shipped again, a spec could be created already
  shipped, a run could be revived by an event after it ended, a dependency
  could point at its own spec.
- A spec carried no record of the code it was shaped against, so a spec shaped
  weeks before it was built could be built against assumptions trunk no longer
  met, with nothing to warn anyone.

## Decision

1. **The Agentile Store Protocol, version 1** (`docs/store-protocol.md`) is the
   contract. It defines the data model, state machines, algorithms (claim,
   rank, dependencies, cascade, map, flow, brief), canonical markdown, errors
   and capabilities. Where an implementation disagrees, the implementation has
   the bug.
2. **The HTTP binding is the Agentile Projects API v1**, kept as it is wherever
   it was already right, so the hosted store needs no breaking change. Older
   field names (`prefix`, `kind`) stay as aliases; the client adds the
   protocol names when a store sends only the old ones.
3. **A second transport, the process binding**, carries the same requests and
   responses as JSON over a child process's stdin and stdout. A store can be a
   script over any backend without running a server. `url: exec:<command>`
   selects one.
4. **The plugin ships a reference local store**, `bin/ag-store-local`, over the
   process binding (`url: local`): one JSON file per project outside the repo,
   one exclusive file lock per request, no gems.
5. **Illegal transitions are refused with 409** rather than tolerated, and the
   gaps between Agentile Projects and the protocol are listed (protocol §12)
   and fixed in the app, not written into the protocol.
6. **Specs record `shaped_against` and `shaped_at`.** `/ag-shape` and `/ag-spec`
   set them; `/ag-plan` measures drift from that commit and writes a "Fit since
   shaping" section; `/ag-build` pauses for plan review when the plan
   recommends re-shaping.
7. **`dev/test-store-conformance.rb` decides conformance.** It drives
   `bin/ag-store`, so it tests what skills see, and runs against the local store
   in the plugin's own gates.

## Consequences

- Agentile runs with no account: `/ag-init` offers the local store.
- Anyone can write a store; the suite tells them when it is done.
- Agentile Projects has sixteen gaps to close (protocol §12, G1 to G16). Until
  G11 is fixed, specs shaped into it lose `shaped_against`, so the drift check
  has nothing to compare for those specs.
- The local store is for one person on one machine. It has no users, no
  dashboards and no push channel, so the factory and the iOS and Hooman Input
  clients still need Agentile Projects.
- Two transports means two code paths in the client. Both are covered: the HTTP
  path by `dev/test-ag-store-http.rb` against a fake API, the process path by
  the conformance suite and `dev/test-ag-store-local.rb`.

## Alternatives considered

- **Op-level contract only** (`ag-store` op names and outputs, no wire format).
  Every store would need its own adapter inside the client again, which is
  what 0.20.0 removed.
- **HTTP only**, with the local store as a small server. A server to start,
  a port to claim, and a process to keep alive, for a single-user store.
- **A SQLite local store.** Proper transactions, but the `sqlite3` gem is not
  something every machine with Ruby has; a JSON file under `flock` is enough at
  this scale and needs nothing.
