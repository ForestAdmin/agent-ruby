Triage and fix open Dependabot vulnerability alerts in this repository, open a PR, then monitor CI and fix anything that breaks until CI is green or you hit the retry cap. Work through the phases below in order. This is a **Ruby / Bundler monorepo of published gems**: the root `Gemfile`/`agent_ruby.gemspec` carry only dev tooling (rubocop, rspec), and each published package lives under `packages/<name>/` with its **own `Gemfile`** (declaring `gemspec` + `path:` deps) and its own gemspec. No `Gemfile.lock` is ever committed (gitignored). Only gemspecs ship to consumers.

**0. Preflight.** Confirm you have what you need:

**Context & token rule:** this routine runs inside GitHub Actions on a checkout of the repository's default branch. `$GH_PAT` is provided by the workflow from the `SECURITY_GH_PAT` secret (a user fine-grained PAT) — use it for **every** `curl`/REST call to `api.github.com`. Git is already authenticated with the same PAT via the checkout step, so plain `git push` works and its pushes trigger CI. Never use the Actions-provided `$GITHUB_TOKEN` for REST calls or the label POST: events it creates do not trigger other workflows, so the Slack notification would never fire.

- `$GH_PAT` is set and non-empty (`[ -n "$GH_PAT" ]`) with `security_events:read` (Dependabot alerts), `contents:write`, `workflows:write` (needed to push `uses:` bumps for `github-actions`-ecosystem alerts), `pull_requests:write`, `issues:write`, `actions:read` + `actions:write` (re-running flaky jobs), and `statuses:read` on this repo. Note: fine-grained PATs cannot carry the `Checks` permission (it is GitHub App-only), so CI monitoring below uses the Actions and Commit statuses APIs — never call the Checks API (`/check-runs`), it would 403. Probe with `curl -sS -o /tmp/preflight-body.json -w "%{http_code}" -H "Authorization: Bearer $GH_PAT" "https://api.github.com/repos/$(git remote get-url origin | sed -E 's|.*github\.com[:/]([^.]+)(\.git)?$|\1|')/dependabot/alerts?per_page=1"` — expect `200`. On any non-200, `cat /tmp/preflight-body.json` — the GitHub error body says why (missing fine-grained permission vs org restriction/pending approval vs expired token).
- Bundler is usable: `bundle --version` works. The workflow already ran `bundle install` at the **root**, which installs the dev tooling (needed for `bundle exec rubocop`). ⚠ The root bundle covers only dev tooling — the published packages' dependency trees resolve through their **own** Gemfiles under `packages/<name>/`; work there for anything dependency-related (see phase 4). NEVER commit any `Gemfile.lock`.

If `$GH_PAT` is missing, stop and print exactly: `Preflight failed: GH_PAT must be set (from the SECURITY_GH_PAT repository/organization secret). Probe not attempted. Aborting — not falling back to bundle audit (it ignores dismissals and the 7-day gate).` If the probe fails, stop and print exactly: `Preflight failed: GH_PAT (SECURITY_GH_PAT secret) lacks the required scopes on <repo>. Probe returned <http_code>, GitHub said: <first 300 chars of /tmp/preflight-body.json>. Aborting — not falling back to bundle audit (it ignores dismissals and the 7-day gate).` Do not proceed.

**1. Fetch alerts.** Derive `$REPO` as `owner/name` from `git remote get-url origin`. Then:
```
curl -sS -D /tmp/alerts-headers.txt \
  -H "Authorization: Bearer $GH_PAT" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO/dependabot/alerts?state=open&per_page=100"
```
Paginate by following the `rel="next"` URL from the `Link` response header captured in `/tmp/alerts-headers.txt` — the JSON body does not contain pagination links. For each alert capture: `number`, `security_advisory.severity`, `dependency.package.ecosystem`, `dependency.package.name`, `dependency.manifest_path`, `security_vulnerability.vulnerable_version_range`, `security_vulnerability.first_patched_version.identifier`, `created_at`, `security_advisory.summary`. Alerts may cover several ecosystems (`rubygems`, but also `npm` via the tooling `package.json`/`yarn.lock`, or `github-actions`) — handle each with its own toolchain; the phases below describe the Bundler path, with the other ecosystems addressed at the end of phase 4.

**2. Triage each alert as FIX or IGNORE.** Mark as IGNORE only when one of the following is concretely true — record which one applies:
- The gem is dev/test/tooling only (in this repo's root Gemfile that group is spelled `group :development, :tests` — note the plural) and the exploit requires untrusted input at runtime.
- The vulnerable code path is unreachable from our code. A negative repo grep alone is NOT sufficient evidence — a dependency can invoke the affected API internally without our code ever naming it. Require at least one of: the advisory targets an optional component/feature we demonstrably don't install or enable; the dependency chain shows the vulnerable call is only reachable through an entry point we never invoke (trace it); or the exploit requires a configuration we don't use. State the evidence in the PR; when in doubt, treat as FIX.
- The advisory is disputed or withdrawn upstream.
- No upstream patch exists yet (`first_patched_version` is null).
- It duplicates another open alert on the same root cause (reference which).

Everything else is FIX.

**3. Skip alerts opened less than 7 days ago.** These are deferred to the next run — list them in the PR description but don't touch them.

**4. For each remaining FIX, prefer the narrowest bump.**

**Work in the package the alert belongs to.** The alert's `dependency.manifest_path` names the owning `Gemfile`/gemspec — usually `packages/<name>/…`. All resolution and verification for that alert happens **inside that package**: `cd packages/<name>`, delete its local `Gemfile.lock` if present, run `bundle lock`, and read the resolved version in the freshly generated lockfile (never commit it). The root bundle knows nothing about the published packages' dependencies — do not use it to verify anything but the dev-tooling group.

A gem is a **direct** dependency if the owning package's gemspec (or its Gemfile, or the root Gemfile/gemspec for root alerts) declares it; otherwise it is transitive. Since only gemspecs ship to consumers, a fix whose vulnerable gem is a **direct dependency of a published package MUST land in that package's gemspec**:
- **Direct:** relax/bump the version constraint in the owning gemspec (or Gemfile) to require the patched version with an explicit upper bound on the current major — e.g. `">= <first_patched_version>", "< <current_major + 1>"` — a bare `>=` would let Bundler resolve a later breaking major. If the patch only exists in a later major, treat it as the blocked-bump case below. Then re-resolve in that package (delete its local lockfile, `bundle lock`) and read the resolved version.
- **Transitive:** bump the constraint of the nearest direct ancestor **in its owning gemspec** so resolution pulls the patched version. If no ancestor bump works, add an explicit pinned entry to the owning package's `Gemfile` (a pessimistic constraint like `"~> <first_patched_version>"` — never an unbounded `">= …"`) with a trailing comment `# security pin — see Dependabot alert <number>`. ⚠ Gemfile pins protect only this repo's CI, NOT consumers of the published gems (gemspecs cannot pin transitives) — whenever a Gemfile pin is the only option, say so explicitly in the PR. Verify by re-resolving in that package.
- **Blocked bump:** if the only viable path is a breaking major touching APIs we use, use the explicit Gemfile pin as above. Record it in the PR under "Security pins added" with the parent chain tried and why the bump wasn't viable.

Use bundler-generated resolution only for verification — no `Gemfile.lock` is ever committed in this repo.

For **npm-ecosystem** alerts (the tooling `package.json`/`yarn.lock` at the root): fix with yarn (`yarn why <pkg>`, bump or root-`resolutions` pin bounded to the parent-compatible major, `yarn install` to update the committed `yarn.lock`). For **github-actions-ecosystem** alerts: bump the `uses:` reference in the affected `.github/workflows/*.yml`; `SECURITY_GH_PAT` carries the `workflows:write` permission this push requires. If the push is nevertheless rejected citing workflow permissions, the files are already **inside the commit** — unstaging alone changes nothing. Rewrite the commit without them (`git reset --soft HEAD~1`, `git restore --staged --worktree .github/workflows/`, re-commit with the same message), then push again, move those alerts to "Could not auto-fix (token lacks Workflows permission)", adjust the Summary counts, and ship the rest.

**5. Audit existing security pins.** Sweep **every** `Gemfile` (root and `packages/*/Gemfile`) for entries carrying a `# security pin` comment (or clearly pin-only entries not required by the code):
- **Stale** — the gem no longer appears in that package's dependency tree at all. Remove the entry, re-resolve in that package (delete its local lockfile, `bundle lock`), confirm.
- **Redundant** — removing the entry still resolves the gem at a version satisfying the original pin (parents caught up upstream). Verify by removing it and re-resolving **from scratch in that package** (delete its local `Gemfile.lock`, then `bundle lock` — a plain `bundle install` conservatively keeps the previously locked version and would always look satisfied). Read the resolved version in the regenerated lockfile: if it still satisfies the original pin, keep the removal; if not, restore the entry.

Process one entry at a time, re-resolving between each. Keep removals in the working tree — everything is committed once, in phase 7. Record every removal in a "Security pins removed" section of the PR with the reason (stale or redundant).

**6. Pre-push checks (cheap, local only).** From the repo root, re-run `bundle install` (to sync the dev tooling with any root Gemfile edits), then `bundle exec rubocop` (the repo has a `.rubocop.yml`) and fix any offenses the changes introduced. Leave pre-existing offenses in untouched files alone. **Do not run the test suite locally** — CI is the source of truth for tests.

**7. Open the PR.**

**Gate first:** if there is nothing to ship — every alert ended up IGNORED or DEFERRED, no fixes or pins were added, and no stale/redundant pins were removed — print the triage summary as the run output and **stop here**: no branch, no commit, no PR. If stale pins were removed but nothing else changed, ship the PR anyway — pin hygiene is worth shipping on its own.

Create the branch with this exact shell command — do **not** use any built-in branch-creation tool that auto-generates names:
```
BRANCH="security/$(date -u +%Y-%m-%d)"
git checkout -b "$BRANCH"
```
**Same-day rerun note:** if the remote branch already exists (`git ls-remote --exit-code --heads origin "$BRANCH"`), this run supersedes it — its content is recomputed from scratch off the default branch. Just note it for now: the push step below changes accordingly, and it only ever happens **after** this run's commit exists.
Before pushing, verify the branch name matches `^security/\d{4}-\d{2}-\d{2}$`:
```
git rev-parse --abbrev-ref HEAD | grep -Eq '^security/[0-9]{4}-[0-9]{2}-[0-9]{2}$' || { echo "Branch name does not match required pattern; aborting"; exit 1; }
```
If the check fails, stop. Do not rename after the fact by auto-generating a name elsewhere — investigate why the branch got a different name and fix it at the source.

Then, strictly in this order:
1. **Commit** as `chore(security): patch <N> Dependabot alerts` (a single commit containing all of this run's changes, including the phase-5 removals; double-check no `Gemfile.lock` is staged).
2. **Push — only after the commit exists** (never push the bare default-branch state over an existing security branch). If the remote branch does not exist: `git push -u origin "$BRANCH"`. If it does (same-day rerun): first `git fetch origin "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"` so the lease has an expected value — the checkout only fetched the default branch — then `git push --force-with-lease -u origin "$BRANCH"` (the single sanctioned force-push; see Constraints).
3. **Open or reuse the PR:** look for an already-**open** PR whose head is `$BRANCH` (`GET /repos/$REPO/pulls?head=<owner>:$BRANCH&state=open`). If one exists, reuse its `number` as `$PR_NUMBER` and update its description; otherwise create one against the default branch via `POST /repos/$REPO/pulls` and capture `$PR_NUMBER` from the response (closed PRs on that branch are irrelevant — the force-push already discarded their stale history).
4. Set the monitoring commit explicitly on **every** path — create or reuse: `SHA=$(git rev-parse HEAD)`. After any later push, refresh it the same way.

**Label the PR `:lock: security`.** This triggers the Slack notification workflow that pings `@first_level_support` — do not skip. The add-labels endpoint silently auto-creates missing labels with a random color and no description, so ensure the label exists **first**:
```
curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO/labels/%3Alock%3A%20security"
```
If that returns `404`, create it:
```
curl -sS -X POST \
  -H "Authorization: Bearer $GH_PAT" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO/labels" \
  -d '{"name":":lock: security","color":"B60205","description":"Security fix — notifies first-level support"}'
```
Then attach it to the PR:
```
curl -sS -o /tmp/label-resp.json -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $GH_PAT" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/$REPO/issues/$PR_NUMBER/labels" \
  -d '{"labels":[":lock: security"]}'
```
If labeling fails, stop and print the response body — do not silently continue, because a missing label means the Slack notification won't fire and the PR won't be picked up for review.

The PR description must include the sections listed below. Mark the **Validation** line as `⏳ Awaiting CI` — phase 8 updates it.

**Alert references in the body must be full Markdown links, never bare `#<number>`.** GitHub auto-links `#<number>` to issues/PRs in the same repo, which sends readers to the wrong page. Format every alert reference as `[#<number>](https://github.com/$REPO/security/dependabot/<number>)` — in every table AND in any inline mentions.

**Actionable checkboxes go in a task list, never in table cells.** GitHub renders `- [ ]` as an interactive checkbox only when it starts a list item; inside a table cell it stays literal text, and a raw `<input type="checkbox">` is stripped by GitHub's sanitizer. So the tables carry **no** checkbox column, and the body ends with a **Review checklist** section built from real task lists:

```
## Review checklist

**Fixes to verify** — tick once you have confirmed the bump landed:
- [ ] [#<number>](https://github.com/$REPO/security/dependabot/<number>) — `<package>`

**Alerts to dismiss** — tick once dismissed in the repo's Security tab (reason in the Ignored section):
- [ ] [#<number>](https://github.com/$REPO/security/dependabot/<number>) — `<package>`
```
Omit either list if it would be empty. Deferred / Security pins added / Security pins removed / Could not auto-fix need no checkboxes — they are informational.

The very first line of the PR description must be the following blockquote so first-level support knows how to review it:

```
> 👋 First-level support: see [Handling automated security PRs](https://forest.slite.com/app/docs/rmjdwFgmV2RzUp) for how to triage and merge this PR.
```

- **Summary**: N fixed, M ignored, K deferred, R security pins added, S security pins removed, F could-not-auto-fix. Append `| label: :lock: security applied` once the label POST returns 200. Keep these counts (and the `patch <N>` commit message, when practical) consistent whenever an alert later moves between sections.
- **Fixed** table: alert number, gem, ecosystem, from → to, severity, what was bumped (direct dep in which gemspec, or "bumped `<parent>` X → Y").
- **Ignored**: each alert with its specific reason (one of the five allowed reasons).
- **Deferred**: alert numbers skipped by the age gate.
- **Security pins added / removed** (if any): gem, pinned range, which Gemfile, reason — and for added pins, the explicit "CI-only, does not protect consumers" caveat where applicable.
- **Could not auto-fix** (if any): alert number, what was attempted, the observed failure.
- **Risks**: per bump, from the upstream CHANGELOG — breaking changes touching APIs we use, tests likely to need updating. If no behavior change beyond the patched vuln, say so.
- **Manual testing**: only if automated CI doesn't cover the affected paths — give concrete reproduction steps. Otherwise write "Covered by CI."
- **Validation**: `⏳ Awaiting CI` for now.
- **Review checklist**: the task lists described above (this is where the checkboxes live).

**8. Monitor CI and fix failures.** Poll **inside a single Bash loop per tool call** (about 10 minutes of `sleep 60` iterations per call — do NOT spend one tool call per poll, that would exhaust the turn budget). Each iteration fetches the workflow runs and the combined commit status for the PR head SHA (Actions + Commit statuses APIs only — the Checks API is not accessible to fine-grained PATs; check runs posted by GitHub Apps such as coverage bots are therefore a blind spot of this monitoring):
```
curl -sS -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO/actions/runs?head_sha=$SHA"
curl -sS -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO/commits/$SHA/status"
```
Wait until every workflow run has a non-null `conclusion` and — **only if the combined status reports at least one status context (`total_count > 0`)** — its `state` is no longer `pending`. An empty `statuses` array (`total_count: 0`) always reports `state: pending` on GitHub's side and must be treated as *no status gate*, not as pending CI. **Startup guard:** do not evaluate completion until at least one workflow run other than this security-fixes workflow exists for `$SHA` — with zero runs the condition would be vacuously true. If no such run has appeared after 10 minutes, comment on the PR ("No CI run started for this commit after 10 minutes — please check branch filters.") and stop. Cap one polling cycle at 45 minutes.

Outcomes (every concluded run falls in exactly one bucket — there is no third state):
- **All green** — every workflow run concluded `success`, `skipped`, or `neutral`, and, when `total_count > 0`, the combined status `state` is `success` → edit the PR description: replace `⏳ Awaiting CI` with `✅ CI green (Actions + commit statuses; app-based checks not monitored)`. Stop.
- **Any failure** — a workflow run concludes with **anything else** (`failure`, `timed_out`, `cancelled`, `action_required`, `stale`, `startup_failure`, …), or a status context reports `failure`/`error` → diagnose. Fetching Actions logs is a two-step dance — the endpoint answers `302` with an empty body and a signed storage URL that must then be requested **without** the Authorization header:
```
LOGS_URL=$(curl -sS -o /dev/null -w '%{redirect_url}' -H "Authorization: Bearer $GH_PAT" \
  "https://api.github.com/repos/$REPO/actions/runs/<id>/logs")
curl -sS -o /tmp/logs.zip "$LOGS_URL" && unzip -o /tmp/logs.zip -d /tmp/logs/
```
  Also fetch the per-job breakdown (`GET /repos/$REPO/actions/runs/<id>/jobs`); a failing **status context** has no Actions logs — record its `context` name and `target_url` in the PR instead. Identify the root cause. Apply a fix, commit as `fix(security): address CI failure — <short reason>`, push to the same branch, refresh the head SHA (`SHA=$(git rev-parse HEAD)`) so the polling calls inspect the new commit, and resume polling.
- **Still pending after 45 minutes** → comment on the PR: "CI still pending after 45 minutes; stopping automated monitoring. Please review." Stop.

**Retry cap: push at most 3 fix commits.** If CI fails again after the third fix commit, stop. (The single flaky-job rerun described below pushes nothing and does not count.) When stopping at the cap, comment on the PR with: the failure signatures seen each cycle, what fixes were attempted, and which alerts in the diff are most likely responsible. Update Validation to `❌ CI failing — needs human review`. Do not close the PR.

**Failures the routine must not try to fix — flag and stop instead:**
- Infrastructure failures (runner startup errors, missing CI secrets, GitHub Actions outage). Detect via runner-level error messages or zero-step runs.
- Flaky tests unrelated to the bumped gems (the failing test file doesn't touch anything that changed, and the failure is timing/network-shaped). Re-run the failed check **once** via `POST /repos/$REPO/actions/runs/<id>/rerun-failed-jobs`; if it flakes again, comment and stop.
- Any fix that would require editing source code beyond minor test adjustments tied to a specific bump. In that case, revert just the offending bump (and any pin added for it), re-resolve locally in the affected package to verify the revert, re-push the Gemfile/gemspec change, and move the alert to "Could not auto-fix" in the PR description with the observed failure (updating the Summary counts).

**Constraints:**
- Only modify `Gemfile` files and `*.gemspec` files (never commit any `Gemfile.lock` — they are gitignored) — plus, for other ecosystems: the root `package.json`/`yarn.lock` (npm alerts) or `uses:` references in `.github/workflows/*.yml` (github-actions alerts) — and test files that genuinely need to change. Don't touch source code to make a bump work — revert the bump instead.
- Never silence failures with `rubocop:disable`, skipped specs, or by marking a workflow required-status as optional.
- Don't close, dismiss, or comment on Dependabot alerts from the API — merging the PR closes them.
- Don't force-push during CI fix cycles — only add commits to the security branch. Single exception: the same-day-rerun supersede in phase 7 uses `--force-with-lease` once, before the PR is (re)used or created.
- Branch name must match `^security/\d{4}-\d{2}-\d{2}$` — no exceptions, no default-named branches. Create the branch via `git checkout -b` in a shell.
- The PR must carry the `:lock: security` label before phase 7 exits — treat a labeling failure as hard-stop, not a warning.
- The PR creation and label calls must go through `$GH_PAT` (a user PAT), never the in-Actions `$GITHUB_TOKEN` — GitHub suppresses workflow-triggered events (like `labeled`) from that token, so the Slack notification workflow would never fire.
