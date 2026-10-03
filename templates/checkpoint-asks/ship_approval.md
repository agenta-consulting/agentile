Ship portal-live-updates — Portal order pages update live?

Built the order status broadcast and portal subscription with a polling fallback. Verify passed with no must-fix findings.

Before approving:
- Open http://localhost:3000/orders/1 in two tabs, change the status in one, and confirm the other updates without a reload.
- Stop the websocket server and confirm the page falls back to polling within 30 seconds.
- Open docs/agentile/specs/portal-live-updates/evidence/live-update.png and confirm the badge colours.
- Skim the diff of app/channels/order_status_channel.rb for stream scoping.

Options:
1. approved
2. Send it back: answer with a different instruction saying what to change

---

Evidence: docs/agentile/specs/portal-live-updates/evidence/live-update.png
Builder: 6 files changed, 142 insertions. Reviewer: VERDICT: pass, no must-fix findings.
