Built the order status broadcast and the portal subscription; all unit tests pass.

The build playbook asks for a human look before verify.

Before approving:
- Skim the diff of app/channels/order_status_channel.rb

Options:
1. approved
2. Send it back: answer with a different instruction saying what to change

---

Builder summary:
- app/channels/order_status_channel.rb: new broadcast channel
- app/javascript/portal/order.js: subscribes and re-renders the status badge
- test/channels/order_status_channel_test.rb: covers broadcast and unauthorised subscribe
