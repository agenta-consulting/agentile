---
max_iterations: 5          # items per /ag-loop invocation — a runaway guard
pause_before_ship: true    # stop for human sign-off before each ship/merge
pause_at_plan: route       # pause for plan review: always | route (foreground & spike specs) | never
stop_on_gate_failure: true # halt/pause on a failing gate rather than continuing
verify_retry_limit: 1      # bounce a failed verify back to build this many times before pausing
on_empty: watch            # under /loop, an empty backlog: watch (keep waiting) | stop (end the loop)
watch: self-paced          # how to wait when idle: self-paced | a fixed interval like 10m
---

# Loop policy

How this project wants `/ag-loop` to behave. There are two pause knobs —
`pause_at_plan` (steering, before code) and `pause_before_ship` (the final
gate) — and the runner also honours every per-stage `human_checkpoint: true`
regardless of these settings.

- `/ag-loop` alone drains the ready backlog then stops.
- `/loop /ag-loop` drains and then watches — waiting for new ready work and
  starting on it as it appears. `on_empty` and `watch` only apply under `/loop`.
- `pause_at_plan: route` pauses after `plan.md` is written when the spec's
  `route` is `foreground` or `spike` — the cheapest place to steer. Review or
  amend `plan.md` in place, then reply "approved". `background` specs run
  through without a plan pause.
