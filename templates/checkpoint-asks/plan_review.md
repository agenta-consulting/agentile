Plan ready for portal-live-updates: push order status changes to the portal over the existing websocket.

Review or amend plan.md in place, then answer this checkpoint.

Options:
1. approved
2. Send it back: answer with a different instruction saying what to change

---

Plan summary: add an OrderStatusChannel broadcast on status change, subscribe from the portal order page, and fall back to polling when the socket drops. No migrations are needed. Plan: docs/agentile/specs/portal-live-updates/plan.md
