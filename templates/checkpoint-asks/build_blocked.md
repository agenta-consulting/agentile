Blocked: the spec asks for a status_changed_at column but the orders table is owned by another service.

Tried adding the column in a migration; the schema check in CI forbids changes to orders from this repo.

Options:
1. resume — I have amended the spec to use a separate order_status_events table
2. Fix it yourself with: asking the orders team to add status_changed_at, then answer 'resume'
3. Send it back: answer with a different instruction saying how to proceed

---

- Spec acceptance criterion 2 reads "orders.status_changed_at is set on every transition".
- db/schema_checks.rb:14 rejects any ALTER on orders.
- Nothing was committed beyond the failing migration, which is not on the branch.
