# Automate the OneDrive → reports → release pipeline

## Context

Today every competition requires the same manual ritual: sign in to a shared personal
OneDrive, find the competition folder, download two workbooks, rename them with the
competition date, drop them in `input_excel/`, run `make YEAR=xxxx`, then commit and push so
`release-reports.yml` mints a release. Nothing about that is judgement work — the source tree
is perfectly regular (`<shared root>/2026/20260926_CompetitionName/Form_analiza.xlsx` +
`Form_acro_analiza.xlsx`), and the rename is a pure function of the folder name.

The goal: a weekly GitHub Actions run (plus a manual button) that fetches any new competition
folders, runs the existing pipeline, commits the result to `main` the way a human does today,
and lets the existing release workflow fire. Zero clicks in the normal case.

Decisions already taken: source is a **personal OneDrive requiring sign-in** (so delegated
OAuth with a rotating refresh token — app-only/client-credentials does not work for consumer
accounts), the automation **runs in GitHub Actions**, triggered by **weekly cron + manual
dispatch**, and it **commits straight to `main`**, matching the current date-named-commit
convention.

## Current pipeline (verified)

- `excel_converter.rb` — `input_excel/*.xlsx` → `src/YYYY/YYYY-MM-DD_{dance,acro}.csv`.
  Requires exactly `YYYY-MM-DD_Form_analiza.xlsx` (dance) / `YYYY-MM-DD_Form_acro_analiza.xlsx`
  (acro) and a sheet named `data`; silently skips anything else (this is how the
  `_Foot_analiza` typo slipped through in `8dc972c`).
- `csv_concatenator.rb YEAR` → `src/YYYY/YYYY-overall_{acro,dance}.csv`.
- `main.rb YEAR` → `output/csv/YYYY/*_{report,summary}.csv` + `docs/YYYY/*_summary.html`.
  Needs an acro+dance **pair** per date; unpaired dates are warned about and skipped.
- `Makefile` — `convert → concatenate → analyze`; `YEAR` defaults to the latest year found in
  `input_excel/` filenames.
- `.github/workflows/release-reports.yml` — on `workflow_dispatch` **and push to `main`**;
  detects latest year from `src/`, computes `YEAR.N`, runs only `main.rb YEAR`, attaches
  `output/csv/YEAR/*_{report,summary}.csv` to a release.
- Both inputs and all derived files are committed (only `Gemfile.lock` is ignored). Deps:
  `roo`, `descriptive_statistics`, `rspec`, `factory_bot` — the new code needs **no new gem**
  (`net/http`, `json`, `base64`, `digest` are stdlib).

## Approach

A Ruby fetcher that mirrors the shared OneDrive tree into `input_excel/`, wired into the
Makefile and driven by a new scheduled workflow. Ruby keeps the repo single-language and
dependency-free; the alternative (`rclone`, which ships its own OAuth client id and would
avoid the Azure app registration) is noted at the end as a fallback if the app registration
turns out to be blocked.

### 1. `module/input_files.rb` (new) — single source of truth for naming

Extract the naming rules that are currently duplicated in `excel_converter.rb` (two inline
regexes) and in the `Makefile`'s `INPUT_YEARS` one-liner:

- `KINDS = { "Form_analiza.xlsx" => "dance", "Form_acro_analiza.xlsx" => "acro" }`
- `INPUT_PATTERN` = `/\A(\d{4}-\d{2}-\d{2})_Form_(?:(acro)_)?analiza\.xlsx\z/`
- `COMP_FOLDER_PATTERN` = `/\A(\d{4})(\d{2})(\d{2})_(.+)\z/` → `[date, competition_name]`
- `input_filename(date, kind)` → `"#{date}_Form_#{'acro_' if kind == 'acro'}analiza.xlsx"`
- `csv_path(date, kind)` → `"src/#{date[0,4]}/#{date}_#{kind}.csv"`

Then have `excel_converter.rb` use `INPUT_PATTERN`/`KINDS` instead of its inline regexes
(small, behaviour-preserving change — it keeps the same "skip unrecognized" warning).

### 2. `module/onedrive/client.rb` (new) — minimal Graph client, stdlib only

- `refresh_access_token(client_id:, refresh_token:, tenant:)` → POSTs to
  `https://login.microsoftonline.com/#{tenant}/oauth2/v2.0/token` with
  `grant_type=refresh_token`, `scope="Files.Read.All offline_access"`. Tenant defaults to
  `consumers` (personal accounts), overridable. **Returns the new refresh token too** — MSA
  refresh tokens rotate on every redemption and must be persisted, or the automation dies.
- `resolve_share(url)` → `GET /shares/u!#{Base64.urlsafe_encode64(url).delete('=')}/driveItem`
  → `{drive_id, item_id}`.
- `children(drive_id, item_id)` → `GET /drives/{drive}/items/{item}/children`, following
  `@odata.nextLink`.
- `download(drive_id, item_id, dest)` → `GET .../content`, following the 302 to the
  pre-authenticated URL **with the `Authorization` header stripped** on the redirect.
- Raises a typed `AuthError` on 400/401 from the token endpoint so the caller can print
  "re-run `make onedrive-login`".

### 3. `bin/onedrive_login.rb` (new) — one-time interactive auth

Device-code flow against `/oauth2/v2.0/devicecode`: prints the code and URL, polls the token
endpoint, then writes `.onedrive_token` (gitignored) and prints the refresh token plus the
exact `gh secret set` commands to run. This is the only interactive step, needed once now and
again only if the token is left unredeemed for 90 days.

### 4. `onedrive_fetch.rb` (new, repo root beside the other entry scripts)

Config from env (`ONEDRIVE_CLIENT_ID`, `ONEDRIVE_REFRESH_TOKEN` or `.onedrive_token`,
`ONEDRIVE_SHARE_URL`), flags `--dry-run`, `--year=YYYY` (repeatable), `--force`.

1. Resolve the share URL to a drive item; list its children.
2. For each child folder whose name is a 4-digit year **>= the current year** (default; wider
   via `--year`) — this stops the script from resurrecting pruned old inputs like
   `2025-04-27`, which exist as CSV in `src/2025/` but were deliberately removed from
   `input_excel/`.
3. Inside each year folder, match competition folders against `COMP_FOLDER_PATTERN` →
   `date = "2026-09-26"`, `name = "CompetitionName"`.
4. **Skip** a competition when both `src/YYYY/YYYY-MM-DD_{dance,acro}.csv` already exist,
   unless `--force`. (Keying on the derived CSVs, not on `input_excel/`, is what makes the
   rolling `input_excel/` working set safe.)
5. Require **both** workbooks in the folder; if only one is present, warn loudly and skip the
   date entirely — `main.rb` needs the pair, and a half-pair would produce a broken commit.
6. Download to a temp dir, then move into `input_excel/` under the canonical name from
   `input_files.rb`.
7. Print a machine-readable summary on stdout and, when `GITHUB_OUTPUT` is set, emit
   `fetched=2026-09-26:CompetitionName,...` and `years=2026` for the workflow.
8. Persist the rotated refresh token: rewrite `.onedrive_token`, and when
   `ONEDRIVE_TOKEN_OUT` is set, write it there for the workflow to push into the secret.

### 5. `Makefile` — new targets

```make
onedrive-login:                 # one-time device-code auth
	bundle exec ruby bin/onedrive_login.rb

fetch:                          # mirror new competitions into input_excel/
	bundle exec ruby onedrive_fetch.rb $(FETCH_ARGS)

sync: fetch pipeline            # fetch, then convert → concatenate → analyze
```

`YEAR` keeps working exactly as today: after `fetch` adds a new pair, the existing
`INPUT_YEARS` glob picks up the right year on its own, so `make sync` needs no arguments.

### 6. `.github/workflows/sync-onedrive.yml` (new)

```yaml
on:
  schedule:
    - cron: '0 6 * * 1'        # Monday 06:00 UTC, after weekend competitions
  workflow_dispatch:
    inputs: { force: {type: boolean, default: false}, dry_run: {type: boolean, default: false} }
concurrency: { group: onedrive-sync, cancel-in-progress: false }
```

Steps: checkout (with `token: ${{ secrets.SYNC_PAT }}`) → `ruby/setup-ruby@v1` 3.2 with
`bundler-cache: true` → `bundle exec ruby onedrive_fetch.rb` → **rotate the secret**
(`gh secret set ONEDRIVE_REFRESH_TOKEN` from the token file, with `::add-mask::`, using
`SYNC_PAT`) → if nothing was fetched, exit successfully → `make YEAR=<year>` → **idempotency
guard**: if `git status --porcelain src/ output/ docs/` is empty, `git checkout -- input_excel/`
and stop (a re-exported workbook has different zip bytes but identical data — without this,
every week would mint an empty release) → commit and push.

Commit subject stays the bare date to match history (`05c380f 2026-09-26`); when several dates
land at once, subject `2026-09-26, 2026-10-03` with the competition names in the body.

The push is made with `SYNC_PAT`, not `GITHUB_TOKEN`, **specifically so it triggers
`release-reports.yml`** — pushes authenticated with `GITHUB_TOKEN` deliberately do not fire
workflows. This keeps the release logic untouched and keeps the fully manual path working
exactly as it does today.

On failure, a final `if: failure()` step opens (or reuses, matched by title) an issue
"OneDrive sync failed" so an expired token in the off-season is visible rather than silent.

### 7. `.github/workflows/release-reports.yml` — one small change

Replace `bundle exec ruby main.rb $YEAR` with `make YEAR=$YEAR` so CI regenerates from the
workbooks instead of trusting the committed CSVs, and drop the stale `mkdir -p ./bk-docs/$YEAR`
(`main.rb` writes to `docs/`, since `ec6917b`). Year detection and versioning stay as they are.

### 8. Supporting changes

- `.gitignore`: add `.onedrive_token`, `.env`.
- `README.md`: document the new targets, the Azure app registration, the four secrets, and the
  cron; fix the now-wrong "Trigger the workflow manually" line.
- `spec/module/onedrive_spec.rb`: specs for the pure logic only — folder name → date +
  competition name, canonical filename building, the year filter, the "both CSVs exist" skip,
  and the half-pair rejection. No network in the suite.

### One-time manual setup (yours, not scriptable)

1. portal.azure.com → App registrations → New registration → **Personal Microsoft accounts
   only**; Authentication → Allow public client flows = **Yes**. No client secret (public
   client + device code).
2. API permissions → Microsoft Graph → Delegated → `Files.Read.All`, `offline_access`.
3. `make onedrive-login`, sign in, copy the printed values.
4. Create a fine-grained PAT on this repo with **Contents: RW** and **Secrets: RW**.
5. Repo secrets: `ONEDRIVE_CLIENT_ID`, `ONEDRIVE_REFRESH_TOKEN`, `ONEDRIVE_SHARE_URL`
   (the share link to the folder holding the year folders), `SYNC_PAT`.

## Verification

1. `bundle exec rspec` — existing suite plus the new pure-logic specs.
2. Local dry run against the real share:
   `make fetch FETCH_ARGS=--dry-run` — must list the known 2026 competitions as "skip (CSV
   exists)" and nothing else, proving both the traversal and the skip rule.
3. Local real run on a pruned copy: `git stash` nothing, instead
   `make fetch FETCH_ARGS="--force --year=2026"` in a scratch clone → confirm
   `input_excel/2026-09-26_Form_analiza.xlsx` reappears byte-comparable in content
   (`bundle exec ruby excel_converter.rb` then `git diff --stat src/2026/` must be empty).
4. `make sync` end to end in the scratch clone → `src/`, `output/csv/2026/`, `docs/2026/`
   regenerate with no diff against what is committed.
5. CI dry run: `gh workflow run sync-onedrive.yml -f dry_run=true`, read the logs, confirm the
   token refresh worked and the secret rotation step ran.
6. Real CI run after the next competition: `gh run watch`, then `gh release list` shows one new
   `2026.N` with the expected CSVs, and `git log -1` shows the date-named commit.
7. Negative check: re-run `sync-onedrive.yml` immediately — it must finish green with no
   commit and no new release.

## Known gotchas, called out rather than solved

- **Scheduled workflows are disabled after 60 days without repo activity.** In the off-season
  the cron will switch itself off; GitHub emails a warning first, and a manual dispatch or any
  commit re-arms it. Say the word and I'll add a monthly keepalive commit, but it's noise.
- MSA refresh tokens die if unredeemed for 90 days. The weekly cron keeps it alive; the
  rotation step is what makes that true, so it must not be skipped.
- `bk-docs/index.html` (the hand-maintained summary index) and the missing `docs/assets/`
  after `ec6917b` are both stale today. Out of scope here — worth a separate pass.
- Fallback if the Azure app registration is refused: `rclone` ships its own OneDrive OAuth
  client, so `rclone config` + an `rclone.conf` secret replaces steps 1–3 and the token
  handling, at the cost of a binary dependency in CI.
