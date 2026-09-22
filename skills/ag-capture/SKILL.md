---
name: ag-capture
description: Add a stub to the Agentile inbox — tidied and classified by the store's assist, confirmed in one glance (or saved instantly with --yes). Safe to run mid-build. Trigger phrases include "/ag-capture", "capture this idea", "drop a stub", "add to the inbox", "note this down for later".
allowed-tools: AskUserQuestion, Bash, Read
---

# ag-capture

Drop an idea into the Inbox as a **stub** in one move. A stub is a placeholder that is *not yet ready to build*. The whole point is that capture costs less than holding the idea in your head, so this skill never interrupts you.

## Apply this project's playbook

Before doing anything else, check for `.agentile/capture.md` (resolve `.agentile/`
from the project root). If it exists, honour it:

- If its frontmatter sets `delegate_to: <skill>`, run this stage by invoking that
  skill with the current spec/context **instead of** the baseline below.
- Invoke any skills listed in `also_run` alongside the baseline.
- If `human_checkpoint: true`, stop after producing your output and require an
  explicit human "approved" before handing off to the next stage.
- Treat the prose body as project policy, layered on the baseline below.

If the file is absent, use the baseline below unchanged.

## Rules

- **Do not interview.** The only questions allowed are the one-line ask when `$ARGUMENTS` is empty and the single confirmation in step 4.
- **Do not start work, plan, or shape.** That is what `/ag-shape` is for.
- **Do not estimate, triage, or add acceptance criteria.** A stub is one line; the store's assist may classify it, you do not.

## Refresh the brief

Before anything else, resolve the **Agentile directory** from `.agentile/config.md` under "## Paths" (default `docs/agentile/`) and run `ag-store brief_sync --dir "<dir>"` (bare command; fallback `"${CLAUDE_PLUGIN_ROOT}/bin/ag-store"`). It rewrites `<dir>/brief.md` from the store so this session reads the current brief, and prints the path. If it exits 2 because the project is not linked (no `.agentile/store.md`, or no token), tell the user to run `/ag-init` (or export `AGENTILE_PROJECTS_TOKEN`) and stop. Every `ag-store` call below is the bare command with the same fallback; none takes `--store`.

## Steps

1. The stub text is `$ARGUMENTS`, minus a trailing `--yes` if present. If it is empty, ask the user for the one line (this is the only question allowed here) and stop until they answer.
2. Ask the store for suggestions (quote the text so the shell cannot eat an apostrophe or a backtick — the text must reach the store **verbatim**):

   ```
   ag-store inbox_assist "<stub text>"
   ```

   It returns `{title, text, kind, serves_outcome_slug, duplicate_of, duplicate_of_type, duplicate_probability, judgment_id}` — a tidied title and text, a `kind` (`feature`/`bug`/`chore`/`spike`, or null when the store was not confident), the open Outcome it seems to serve (or null), and a possible duplicate (an existing inbox stub or a ready spec — `duplicate_of_type` is `"inbox"` or `"spec"`) when `duplicate_probability` is 0.5 or more. Nothing is saved yet.
3. If the assist call failed for any reason other than "not linked" (the store's assist is a convenience, never a gate): skip straight to saving with the **raw** text and a `--title` derived as a very short label (3–6 words, no trailing full stop; the user's own `--title "..."` wins) and `--type` from what the text plainly says (default `feature`; a described defect or repro ⇒ `bug`; housekeeping with no user-visible change ⇒ `chore`; an open question to explore ⇒ `spike`). Pass `--serves` only when the user named an Outcome explicitly. Go to step 5.
4. Otherwise, if the user passed `--yes`: save immediately using the assist's suggestions (`--title`, `--type` from `kind`, `--serves` from `serves_outcome_slug` when set — when `kind` or `serves_outcome_slug` is null, simply omit the corresponding flag rather than guessing; `inbox_add` drops absent keys and the app defaults `kind` to `feature`), **and** pass the raw suggestion metadata through unchanged whenever assist returned it: `--suggested-kind <kind>`, `--duplicate-of <duplicate_of>`, `--duplicate-probability <duplicate_probability>` (omit whichever assist returned null for). Then — when `duplicate_of` is set — print the duplicate warning below the confirmation, without asking. Go to step 5.

   Otherwise show the suggestion in one `AskUserQuestion`: the tidied title and text, the kind, the Outcome, and — when `duplicate_of` is set — the duplicate warning, framed by `duplicate_of_type`: "looks like inbox item #`<duplicate_of>`: `<title>`" for `"inbox"`, or "looks like the ready spec `` `<duplicate_of>` ``" for `"spec"`. Options: **Save as suggested**, **Save my original text** (keeps the user's wording, still uses the suggested title/kind), **Don't save** (a duplicate, or second thoughts) — and when `duplicate_of_type` is `"inbox"`, add **Shape the existing one instead** (hand off to `/ag-shape <duplicate_of>` and stop here rather than saving). Either save option passes the same `--suggested-kind`/`--duplicate-of`/`--duplicate-probability` metadata as the `--yes` path above. One question, then act.
5. Save:

   ```
   ag-store inbox_add "<text>" --title "<title>" --type "<kind>" [--serves "<outcome-slug>"] [--suggested-kind "<kind>"] [--duplicate-of "<id>"] [--duplicate-probability "<p>"]
   ```

   The store records who captured it from the token — there is no `--by`. It prints the new stub's id. A non-zero exit 2 means the project is not linked — tell the user to run `/ag-init` rather than working around it.
6. Reply with one short line confirming the stub was captured as inbox item #`<id>`, its title and kind, and (if any) the Outcome it serves. Nothing more.
