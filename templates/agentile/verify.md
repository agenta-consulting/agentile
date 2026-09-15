---
# human_checkpoint: true   # uncomment to require a human sign-off after a passing verify
retry_limit: 1             # bounce a failed verify back to build this many times before pausing
stop_on_gate_failure: true # pause on a failing gate past the retry limit (false: fail the item and move on)
---

# Verify — this project's Definition of Done

List what "done" observably means here (the checklist the reviewer applies on top
of the baseline tests/scan/diff-read). Run `/ag-customise verify` to build it out.
