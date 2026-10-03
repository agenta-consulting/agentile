Should the portal fall back to polling when the websocket drops, or show a stale banner?

The spec says "stays current" without saying what happens offline. Both are small changes.

Options:
1. Poll every 30 seconds until the socket reconnects (recommended) — keeps data fresh, adds one timer
2. Show a stale-data banner and stop updating — simpler, but the user must reload

---

Polling reuses the existing /orders/:id.json endpoint, so no new route. The banner needs new copy that nobody has approved.
