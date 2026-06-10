---
# wip_limit is read from prioritise.md; next.md is the pull policy.
---

# Next — this project's pull policy

`/ag-next` atomically claims the highest-priority unclaimed ready spec and reports
it. WIP is capped by `wip_limit` in prioritise.md. To run claims continuously (claim
→ build → verify → ship → repeat), use `/ag-loop`.
