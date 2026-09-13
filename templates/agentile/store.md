---
store: local
---

# Store

Where the Inbox and specs live.

**local** (the default) is files + git under the Agentile directory — today's
behaviour, unchanged. Prioritising and claiming are safe within one checkout;
across machines they rely on a social contract (pull before you touch the
queue, push right after) rather than a hard guarantee — fine for one person,
worth outgrowing once more than one person is prioritising or claiming at
the same time.

**team** mode moves the Inbox and every spec into a shared datastore instead,
so the queue and every claim are visible live to everyone, not just after
the next push. The default team datastore is **airtable** — see
`templates/stores/airtable/README.md` for setup (a personal access token, a
base, and `ag-store provision`) and its honest concurrency notes.

Switch modes with `/ag-customise store`, or by hand:

```yaml
store: airtable
airtable_base: appXXXXXXXXXXXXXX
airtable_inbox_table: Inbox      # defaults shown; omit unless renamed
airtable_specs_table: Specs
airtable_members_table: Members
```

Credentials are never written here — `AGENTILE_AIRTABLE_TOKEN` is an
environment variable only, set wherever you keep local secrets for tools you
run (never in a tracked file).

`plan.md`, supporting files, and ADRs always stay in this repo in **both**
modes — only the Inbox and spec content move to a shared store.
