Review still fails after 2 retries: the broadcast leaks order status to other customers.

The reviewer rejected the diff on each pass for the same must-fix item.

Options:
1. retry — the builder will scope the stream per customer (recommended)
2. release
3. Abandon it yourself with: /ag-abandon portal-live-updates

---

- must-fix: app/channels/order_status_channel.rb:9 streams from a single shared name, so every subscriber sees every order.
- must-fix: no test proves a customer cannot subscribe to another customer's order.
- nice-to-have: log subscription rejections.
