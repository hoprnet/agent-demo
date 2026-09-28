# claude-loop: a coder agent and a review agent on your pull requests

Two Claude Code agents work on a pull request that carries the `claude-loop` label. The **coder** acts on what people write on the PR and pushes fixes. The **reviewer** checks every push, runs the tests and posts one review. They never share a run, so the reviewer judges the coder's work independently. Both run as GitHub Actions through the Claude Code GitHub Action and bill your Claude subscription, not the API. Every state and every failure shows on the PR itself.

This repository is the reference setup and its test bed. `AGENTS.md` is the procedure both agents follow, `.github/workflows/` and `.github/claude-loop/loop.sh` are the mechanics, and this file explains setup, daily use and what to do when something goes wrong.

## Quick start

1. Install the Claude GitHub App on the repository and store a `claude setup-token` result as the repository secret `CLAUDE_CODE_OAUTH_TOKEN` (details under "Set up a repository").
2. Create the label `claude-loop`.
3. Open a pull request and add the label. The reviewer runs; if it requests changes, the coder fixes and pushes, and the reviewer checks again until it approves.
4. Talk to the loop by commenting on the PR, in the conversation or on a line of code. Remove the label to stop.

## What you see on the pull request

| Where | What it means |
|---|---|
| 👀 on your comment | The coder picked it up. No 👀 within a few minutes means nothing is running; see "When things go wrong". |
| `[reviewer] …` review | The reviewer's verdict: "request changes" with a numbered list, or "approve". A `For a human:` note lists what only a person can do (PR title or description, a design choice); it never blocks. |
| `[coder] …` comment | The coder's answer: the commit hash, then each request with what was done or why not. Inline comments also get a `[coder]` reply in their own thread. |
| `claude-loop` status check | The loop's state on the head commit: pending while an agent works or changes are open, green when the reviewer approved, red on a failure or at the round cap. It links to the run. |
| `[loop] ❌ …` comment | An agent run failed. It names the cause, what to do and how to retry, with the agent's own error text. |
| `[loop] ⚠️ …` comment | The watchdog or the round cap: a comment nobody picked up, a loop that stalled, or the cap reached. |
| `claude-loop:error` label | Something needs a human now. It clears by itself when an agent run succeeds again. |

`[coder]`, `[reviewer]` and `[loop]` at the very start of a post are how the workflows tell the agents apart: both agents post as `claude[bot]`, and `[loop]` messages come from the workflows themselves.

## Set up a repository

You need admin rights on the repository.

1. **Install the Claude GitHub App** on the repository: https://github.com/apps/claude. The action uses its Contents, Issues and Pull requests permissions to push, comment and review. Alternatively run `/install-github-app` inside Claude Code in a checkout; choose "Skip for now" when it offers to write a workflow, since the workflows here are already in place.
2. **Create the subscription token and store it as a secret.** On your laptop, `claude setup-token` prints a long-lived OAuth token bound to your Claude subscription. Store it as the repository secret `CLAUDE_CODE_OAUTH_TOKEN`; the workflows pass it as `claude_code_oauth_token`, so runs use your Pro, Max or Team usage windows, not API credits. Three ways to store it, none of which puts the token in the repository:
   - **GitHub web UI, no CLI needed.** Repository → Settings → Secrets and variables → Actions → New repository secret; name `CLAUDE_CODE_OAUTH_TOKEN`, paste the token, Add secret.
   - **`gh` with a scoped personal token, no `gh auth login`.** Create a fine-grained personal access token at https://github.com/settings/personal-access-tokens/new for this repository only, with the single repository permission **Secrets: read and write** and a short expiry. Then:
     ```bash
     read -rs GH_TOKEN && export GH_TOKEN          # paste the personal token; nothing echoes, nothing in history
     read -rs T && printf '%s' "$T" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo OWNER/REPO   # paste the Claude token
     unset GH_TOKEN T
     ```
     `gh secret set` encrypts the value with the repository's public key before it leaves your machine. Delete the personal token afterwards.
   - **`gh auth login`** (browser device flow), then `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo OWNER/REPO` and paste when asked.

   This is safe on a public repository: Actions secrets are encrypted at rest, cannot be read back once saved, are masked in logs, and are withheld from workflows that pull requests from forks trigger. Keep the token out of every file, workflow `env:` literal and commit message, and do not also set `ANTHROPIC_API_KEY`; the workflows never use it. The token bills the subscription of whoever ran `claude setup-token`, so for a team pick the account whose allowance should pay. It can only make model requests: it is not a claude.ai login and cannot read conversations or account settings. If it leaks, revoke it in that account's claude.ai settings (or through Anthropic support), run `claude setup-token` again and replace the secret.
3. **Create the label `claude-loop`**, in any of these ways:
   - Web UI: Issues → Labels → New label. Or type the name in a PR's Labels picker and choose "Create new label".
   - With the scoped token from step 2 plus the permission **Issues: read and write**: `gh label create claude-loop --repo OWNER/REPO --color 5319E7 --description "Claude coder + reviewer agents act on this PR"`.
   - With `curl` and the same token:
     ```bash
     curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
       https://api.github.com/repos/OWNER/REPO/labels \
       -d '{"name":"claude-loop","color":"5319E7","description":"Claude coder + reviewer agents act on this PR"}'
     ```
   The error label `claude-loop:error` creates itself the first time it is needed.
4. **Check that Actions are enabled** (Settings → Actions → General: allow all actions, or at least `anthropics/*` and `actions/*`). The jobs declare their own permissions, so the default `GITHUB_TOKEN` setting can stay read-only.
5. **Push the files to the default branch.** Workflows only run once they exist there.

Both agents run on Claude Opus 5.5 (`--model claude-opus-5-5` in each workflow's `claude_args`); change that line to use another model. A `CLAUDE.md` with project conventions is read by the action, as `AGENTS.md` is.

## Daily use

- **Follow a PR:** add the `claude-loop` label (sidebar, or `gh pr edit N --add-label claude-loop`). The reviewer starts at once. Comments that were already on the PR are handled too: if the reviewer approves while a request is still unanswered, it starts the coder itself.
- **Ask for something:** comment on the PR, in the conversation or on a line. One comment can hold several requests. A burst of comments is handled by one coder run. Only repository owners, organisation members and collaborators can drive the loop; other people's comments are ignored.
- **Change your mind:** say so in a new comment. The newest instruction from a team member settles a design question; an agent that argued the opposite before says so once and then follows you.
- **Push yourself:** fine at any time. The reviewer checks your push. If the coder is pushing at the same moment, it rebases onto your commit.
- **Stop:** remove the label. Nothing runs on the PR after that.
- **Round cap:** the reviewer requests changes at most 5 times per label (`MAX_ROUNDS` in both workflows). Then it posts its remaining findings as a comment, the status turns red and a `[loop]` message says a human decides. Remove and re-add the label to allow another 5 rounds. Your own comments still reach the coder after the cap.
- **Copilot reviews:** if Copilot review is enabled, the coder handles its findings like a human review. GitHub starts no workflow for a Copilot review, so the watchdog hands it to the coder on its next run (15 to 30 minutes, or sooner with any comment).
- **Run an agent by hand:** Actions tab → `claude-coder` or `claude-reviewer` → Run workflow → PR number.

## When things go wrong

Every failure is meant to be visible on the PR within minutes, with the cause and the fix. What you see and what to do:

| What you see | Cause | What to do |
|---|---|---|
| `[loop] ❌ … Claude authentication failed` | The token secret is invalid, expired or revoked. | Run `claude setup-token` and replace the `CLAUDE_CODE_OAUTH_TOKEN` secret. |
| `[loop] ❌ … Claude usage limit or rate limit reached` | Your subscription's five-hour or weekly window is used up. | Wait for the reset, then post any comment; the coder picks up everything unanswered. |
| `[loop] ❌ … the Claude API was overloaded` | A temporary problem on Anthropic's side. | Retry in a few minutes with a comment. |
| `[loop] ❌ … the agent hit its turn limit` | The request needed more than 80 agent turns. | Split it into smaller comments, or raise `--max-turns`. |
| `[loop] ❌ … the agent step hit its time limit` | The agent ran past 30 minutes (coder) or 18 (reviewer). | Split the request, or raise `timeout-minutes`. |
| `[loop] ❌ … the workflow files on this PR branch differ from main` | The Claude action refuses to run workflow files that differ from the default branch (see "GitHub details the workflows work around"). | Merge the default branch into the PR branch and push; put workflow changes in their own PR. |
| `[loop] ❌ … no Claude token available to this run` | The secret is missing, or the PR comes from a fork (forks never get secrets). | Add the secret; for forks, pull the change into a branch of this repository. |
| `[loop] ❌ … the agent finished without posting its reply` | The agent could not post; the run summary lists refused tool calls. | Open the run; extend `--allowedTools` if a needed command was refused. |
| `[loop] ⚠️ no agent picked up a comment within 10 minutes` | GitHub Actions is down or delayed, or the `claude-coder` workflow is disabled. | Check githubstatus.com and the Actions tab; once it runs again, post any comment. |
| `[loop] ⚠️ the loop has been waiting since …` | A run died without reporting (lost runner, job-level timeout), or a hand-off event was lost while a workflow was disabled. | Post a comment or re-add the label. |
| `[loop] ⚠️ the head commit … has had no review` | The `claude-reviewer` workflow is disabled, or Actions was down during a push. | Re-add the label. |

Each `[loop] ❌` message ends with the retry action for that agent: a comment re-runs the coder, and re-adding the label (or running `claude-reviewer` by hand) re-runs the reviewer.

The last three rows come from the **watchdog** workflow. It uses no Claude, only the repository token, and runs every 15 minutes and on demand. It covers what a failing run cannot report about itself, and it hands Copilot reviews to the coder. Two limits are worth knowing:

- GitHub runs schedules late or skips them under load (in testing, two of three 15-minute slots were skipped), so detection can take 30 minutes or more. Public repositories also have their schedules disabled after 60 days without activity.
- During a complete GitHub Actions outage the watchdog cannot run either. The only signal then is the missing 👀 on your comment. Once Actions recovers, the watchdog reports the stalled PRs.

## Skills

The agents load four public Claude Code skills as plugins, through the action's `plugin_marketplaces` and `plugins` inputs. Each run installs them fresh, so an update to a skill reaches the next run.

| Skill | Marketplace | Used by | For |
|---|---|---|---|
| `unslop` | `kauki-skills` (https://github.com/Teebor-Choka/skills) | coder, reviewer, VPN test | Checking every comment, review and prose edit for machine-written tells. |
| `write-clear-explainers` | `seb-ai-skills` (https://github.com/SCBuergel/seb-ai-skills) | coder, reviewer, VPN test | Writing posts and docs that a reader who did not watch the run can follow. |
| `hopr-debug` | `kauki-skills` | coder, reviewer, VPN test | Loaded when a change or a failure concerns HOPR sessions, SURBs, channels or relays. |
| `test-gnosis-vpn` | `seb-ai-skills` | VPN test | The procedure for testing Gnosis VPN on a remote machine without losing SSH. |

The prompts say when to load each one, and `Skill` is in every agent's `--allowedTools`. The run summary lists the skills a run used, for example `loop: skills used: unslop:unslop, write-clear-explainers:write-clear-explainers`. To add a skill, add its marketplace and `name@marketplace` to the two inputs in each workflow and say in the prompt when to use it.

## Test Gnosis VPN on a machine

The `claude-vpn-test` workflow has an agent install, connect and check Gnosis VPN on a cloud machine you own, following the `test-gnosis-vpn` skill, and posts a `[vpn-test] PASS` or `[vpn-test] FAIL` report on the PR. It is separate from the coder and reviewer loop and never edits the repository.

### Set up the machine and the secrets

1. **Pick a machine you can lose for a few minutes.** Connecting the VPN turns on a kill switch that cuts SSH unless the guards below hold. If a run dies badly, the machine's dead-man switch tears the VPN down after 6 minutes and reboots the machine after 12. Use a disposable VM, not a shared server.
2. **Make a key pair for GitHub only,** with no passphrase:
   ```bash
   ssh-keygen -t ed25519 -N "" -C "agent-demo claude-vpn-test" -f ~/.ssh/gh_vpn_test_ed25519
   ```
3. **Authorise the public key on the machine** for root, or for a user with passwordless `sudo`:
   ```bash
   ssh-copy-id -i ~/.ssh/gh_vpn_test_ed25519.pub root@HOST
   ```
4. **Store four secrets** (Settings → Secrets and variables → Actions → New repository secret, or `gh secret set NAME --repo OWNER/REPO < file` with a token that has **Secrets: read and write**):

   | Secret | Value | Required |
   |---|---|---|
   | `VPN_TEST_HOST` | The machine's IP address or host name. | yes |
   | `VPN_TEST_SSH_KEY` | The whole private key file, `~/.ssh/gh_vpn_test_ed25519`, including the BEGIN and END lines. | yes |
   | `VPN_TEST_KNOWN_HOSTS` | The output of `ssh-keyscan -t ed25519 HOST`, checked against the machine's console. | recommended |
   | `VPN_TEST_USER` | The SSH user, when it is not `root`. | no |

   Without `VPN_TEST_KNOWN_HOSTS` the run accepts the host key it first sees and says so in a warning. The host address stays in secrets: it is masked in logs and replaced by `<test machine>` in the report.

### Run a test

- **From the Actions tab:** `claude-vpn-test` → Run workflow. Inputs: the PR to report on, whether to install the client first, the release channel, and an exit to connect to (empty means the first ready one).
- **From a PR:** add the `vpn-test` label. The test runs with the default inputs; remove and re-add the label to run it again.
- **Without a machine:** run it with `self_test` ticked. The runner then plays the machine: an SSH server on the runner, the lock, the guards, the agent's survey and the teardown all run, but the agent never connects the VPN, since the kill switch would cut the runner off.

The report starts with the verdict. It then gives the package and client versions, the network and the funding status, and each step of the test with its result and numbers: connect, whether the exit IP changed (never the addresses), a 10 MB download, a ping, disconnect, and the kill switch gone afterwards. A FAIL adds the agent's diagnosis, using the `hopr-debug` skill, and what a human should look at.

### One test at a time

Two locks make sure only one test ever runs on the machine:

1. **The workflow's concurrency group** `gnosis-vpn-test-host` queues runs of this repository: a second run waits until the first has finished and is never cancelled.
2. **A lock on the machine itself,** `.github/claude-loop/vpn-lock.sh`, covers everything else: another repository, a fork of this workflow, or a person testing by hand. It is a directory under `/run/lock`, taken atomically inside an `flock` critical section; in testing, of 30 testers started in the same second exactly one got the lock. A run waits up to 30 minutes for it (`LOCK_WAIT_MIN`) and then fails and says the machine stayed busy.

While a run holds the lock, its heartbeat refreshes it every minute. A lock without a heartbeat for 15 minutes (`LOCK_STALE_MIN`) belongs to a crashed run and the next run takes it over. A reboot clears it. To test by hand without colliding with a run, take the lock yourself first and release it afterwards:

```bash
ssh root@HOST 'bash -s' -- acquire "me, by hand" < .github/claude-loop/vpn-lock.sh   # BUSY and exit code 3 if a run holds it
ssh root@HOST 'bash -s' -- release "me, by hand" < .github/claude-loop/vpn-lock.sh
ssh root@HOST 'bash -s' -- status < .github/claude-loop/vpn-lock.sh
```

A hand-held lock has no heartbeat, so a run takes it over after 15 minutes; refresh it with `refresh "me, by hand"` during a longer session.

### Safety on the machine

Before the agent starts, the workflow installs the skill's two guards as systemd units:

- `gvpn-ssh-keeper` keeps a route from the machine to the runner outside the tunnel, so SSH survives the kill switch.
- `gvpn-deadman` watches `/run/gvpn-deadman.alive`. The workflow's heartbeat touches it every minute; if it goes silent, the guard disconnects the VPN after 6 minutes and reboots the machine after 12.

The teardown runs even when the agent fails: disconnect, stop the client, check that the kill switch table is gone, stop the guards, stop the heartbeat, release the lock. The agent may only run `ssh vpnhost …`, `curl`, `sleep` and `date`, and gets 45 minutes.

### When a VPN test fails

| What you see | Cause | What to do |
|---|---|---|
| `[loop] ❌ vpn-test failed: the VPN test machine is not configured (missing secret(s): …)` | A required secret is missing. | Add it as described above. |
| `[loop] ❌ vpn-test failed: cannot reach the VPN test machine over SSH` | Wrong host, key, user or host key. | Try `ssh -i ~/.ssh/gh_vpn_test_ed25519 USER@HOST` yourself; renew `VPN_TEST_KNOWN_HOSTS` after rebuilding the machine. |
| `[loop] ❌ vpn-test failed: the VPN test machine stayed busy with another test for 30 minutes` | Another test held the host lock for 30 minutes. | Check `vpn-lock.sh status` on the machine; run again once it is free. |
| `[vpn-test] FAIL …`, then `[loop] ❌ vpn-test failed: the VPN test failed` | The test ran and Gnosis VPN failed a check. | Read the report; it names the failed check and the earliest client error. |
| `[loop] ❌ vpn-test failed: could not install the safety guards on the VPN test machine` | The guard scripts could not be fetched or started; nothing was connected. | Open the run log for the failing command. |
| A warning in the run that the machine was unreachable at teardown | SSH dropped during the test. | Wait 12 minutes: the dead-man switch disconnects the VPN and reboots the machine. |

The Claude failures from the table above (token, usage limit, turn limit, time limit) are reported the same way, with `vpn-test` in the message.

## How it works

```
label added, or a human pushes            a team member comments or reviews
            │                                        │
            ▼                                        ▼
   claude-reviewer ◄──── second job ──── claude-coder ── fixes, pushes, replies [coder]
   runs tests, posts ONE review          when it pushed      ▲
            │                                                 │
            ├── request changes ──────────────────────────────┘
            ├── approve, but a request is unanswered ── dispatch ──┘
            └── approve ──► done (status green)
```

**The coder** (`.github/workflows/claude-coder.yml`) listens to PR comments, inline review comments, submitted reviews and `workflow_dispatch`. A gate decides before any runner starts: the PR must be open and labelled; human events count only from owners, organisation members and collaborators; bot events count only for the reviewer's `[reviewer]` reviews (not approvals) and Copilot's reviews; `[coder]` posts never trigger it. Then, per run:

1. A precheck without Claude lists the requests newer than the coder's last `seen-until` watermark (the line it ends every summary with). Nothing new means the run ends there, so duplicate and coalesced triggers cost no subscription.
2. 👀 on every comment the run will handle, and a pending `claude-loop` status.
3. The round cap guard, then the agent with an exact tool allow-list, a 30-minute step limit and 80 turns.
4. A run summary on the Actions page (turns, time, API-equivalent cost, every refused tool call) and a postcondition: no `[coder]` reply means the run failed.
5. If the branch moved, a second job in the same run calls the reviewer. A push made from inside a workflow cannot start another workflow by event: GitHub holds that run for approval. Those held duplicate runs are deleted automatically.
6. On any failure, the job diagnoses itself (which step failed, the agent's error text, how long it ran), and a `report` job posts the `[loop] ❌` message, turns the status red and adds the error label.

**The reviewer** (`.github/workflows/claude-reviewer.yml`) runs on the label, on human pushes, by hand, and as the coder's second job. It skips a head it already reviewed since the label, reviews with read-only tools plus the tests, and must post exactly one `[reviewer]` review. Unanswered human requests are the coder's work in progress: the reviewer names them in one line and does not block on them. It records its outcome as the `claude-loop` status of the exact commit it reviewed, and on an approval with requests still open it dispatches the coder.

**Concurrency:** one coder run per PR at a time; a burst of events coalesces into one waiting run, and the replaced runs end without calling Claude. A newer push cancels a review in progress. Different PRs run fully in parallel.

**Timeouts:** every job has `timeout-minutes`, each agent step has its own limit, and every GitHub API call in `loop.sh` has a 60-second timeout with three attempts (client errors other than 429 fail at once).

**The shared logic** lives in `.github/claude-loop/loop.sh`: prechecks, round counting, statuses, reactions, postconditions, diagnosis, reports and the watchdog. Every job loads it from the default branch, so a pull request cannot change the loop's own behaviour.

## GitHub details the workflows work around

- **A workflow's own push cannot wake another workflow.** GitHub attributes a push made from inside a workflow run to `github-actions[bot]` and parks the `pull_request` run it would trigger as "action required". That is why the reviewer runs as the coder's second job, and why the parked duplicates are deleted. Both workflows also set `bot_id: "209825114"` and `bot_name: "claude[bot]"`, so the coder's commits are attributed to the Claude App's own bot user.
- **Runs started by a workflow have a bot as actor.** A coder run the reviewer dispatches, and the review chained into it, are started by `github-actions[bot]`. The Claude action refuses bot actors unless they are listed, so both workflows list it in `allowed_bots`, next to `claude[bot]` (and Copilot for the coder).
- **Copilot reviews start no workflow.** A Copilot review is produced by an Actions run of its own, and like a workflow's own push it triggers nothing. The watchdog therefore looks for Copilot reviews the coder has not answered and dispatches the coder.
- **Workflow identity.** On `pull_request` events the Claude action refuses to start unless the workflow file on the PR branch is identical to the default branch's. The loop reports this as a failure with the fix. After changing the workflows on the default branch, merge it into open PR branches: `git checkout BRANCH && git pull && git merge main && git push`. Keep workflow changes out of PRs the agents work on; `AGENTS.md` forbids the coder to touch them.

## Use it in another repository

1. Copy `.github/workflows/claude-coder.yml`, `.github/workflows/claude-reviewer.yml`, `.github/workflows/claude-loop-watchdog.yml`, `.github/claude-loop/loop.sh` and `AGENTS.md`.
2. In the coder and reviewer workflows, replace `python -m pytest` in the prompts and in `--allowedTools` with the repository's test command, and add its build or lint commands to `--allowedTools` (nothing else is allowed). Drop the "Install the test tooling" step or replace it with the project's setup.
3. Adjust `AGENTS.md`: keep the markers, the one-review rule, the cap and the human-only rule; add the repository's own rules.
4. Follow "Set up a repository": the Claude App, the `CLAUDE_CODE_OAUTH_TOKEN` secret, the `claude-loop` label, push. The first PR you label is the smoke test: expect a review, a green or pending status, and 👀 on your comments.
5. For many repositories, keep one copy of the procedure: move the three workflows into a shared repository as reusable workflows (`on: workflow_call`) and give each repository short caller workflows with the same triggers and `secrets: inherit`.

## Cost and limits

- Every agent run spends your subscription's five-hour and weekly windows, shared with your interactive Claude Code sessions. In testing, a typical round (one review, one coder run, one chained review) took two to four minutes of agent time. The prechecks keep coalesced and duplicate triggers free; the round cap bounds a stubborn PR; the run summary shows turns and an API-equivalent cost per run.
- The runners are GitHub-hosted. A test that needs one machine over SSH works like `claude-vpn-test`. Anything that needs more (long measurements, a whole test stack) belongs on a self-hosted runner (`runs-on: self-hosted` on a machine where `claude` is logged in also bills the subscription), or in an interactive session.
- Branch protection that forbids pushes from apps blocks the coder's push; the failure report says so. The Claude App cannot approve a PR it opened, so keep PRs human-opened for the reviewer's approval to count.
- Organisation-wide bots (CodeRabbit, Augment and the like) comment on every PR. The gate ignores them, and each ignored event costs only a skipped job.

## How this was tested

The toolchain was built and tested on this repository's pull requests #1 to #13. What each test showed:

| Test | Result |
|---|---|
| Subtle bugs on a green test suite (docstring vs. code, untested edge cases, a test that pins a bug) | The reviewer found every one by reading the code; the coder fixed code and tests; approved in one or two rounds. |
| One comment with three different requests; a follow-up that changes an earlier request | All handled in one run each; the newest instruction won; a question got an answer, not a code change. |
| A review with three inline comments, two of them garbled | One coder run; sensible reading of the garbled ones from their lines; threaded replies; the reviewer flagged the ambiguity as a human question. |
| A burst of three comments in three seconds | One coder run handled all three; the replaced runs cost nothing and reported nothing. |
| A human push while the coder was working | The coder's push was rejected; it rebased, re-ran the tests and pushed; the reviewer confirmed the history. |
| Two PRs at once | Two independent loops, both approved within three minutes. |
| Label removed, comment posted, label re-added | No run while unlabelled; after re-labelling the comment was answered (by the reviewer's dispatch, or by hand from the Actions tab). |
| Round cap (temporarily 0) | Findings posted as a comment, `[loop]` cap message, red status, error label. |
| Invalid token | `[loop] ❌ Claude authentication failed` with the agent's own 401 text and the fix. |
| Turn limit (temporarily 2) and step timeout (temporarily 1 minute) | Classified precisely, with the remedy; no partial pushes. |
| `claude-coder` workflow disabled (stand-in for an Actions outage) | Watchdog incident after 10 minutes; after re-enabling, one comment brought the loop back and it caught up on everything unanswered, including a request whose earlier run had timed out. |
| A PR that edits a workflow file | `[loop] ❌ … the workflow files on this PR branch differ from main`, with the fix; after the fix the reviewer ran normally and the error label cleared. |
| A hand-off lost while a workflow was disabled | Watchdog stall report after 30 minutes; one comment resumed the loop. |
| Copilot review requested through the API | No workflow started by GitHub; the watchdog dispatched the coder, which answered it. |
| Skills (PR #13, a docs page full of machine-written tells) | Both agents loaded `unslop` and `write-clear-explainers`; the review listed the stock phrases, the chatbot sign-off and functions that do not exist; the coder rewrote the page; approved. |
| VPN test without secrets | `[loop] ❌ vpn-test failed: the VPN test machine is not configured (missing secret(s): …)` on the PR within a minute. |
| Two VPN tests dispatched at once | The second waited in the concurrency group and started after the first had finished. |
| 30 testers taking the host lock in the same second, free and stale | Exactly one winner each time; wrong-owner release refused; a silent lock taken over after its stale time. |
| VPN test self-test (the runner plays the machine) | SSH, host lock, guards, agent with `test-gnosis-vpn`, teardown and lock release all ran; `[vpn-test] PASS (self-test)` posted. The first attempt found a guard install that failed for a non-root SSH user, now fixed. |
| Final run on the final `main` (PR #12) | Bug found on a green suite, fixed, approved; an inline comment answered in its thread with a commit; approved again. |

Faults the tests found, each fixed in its own commit:

- A comment on a closed but still labelled PR started a run.
- GitHub reports an approval's `commit_id` as the current head, so "already reviewed" is now read from per-commit statuses.
- A failure report cannot read the failing job's log from inside the same run, so jobs now diagnose themselves.
- The round cap was off by one.
- Held duplicate runs cannot be cancelled, only deleted.
- A PR's merge ref could carry an outdated `loop.sh`.
- Dispatched runs failed the action's bot-actor check until `github-actions[bot]` was allowed.
- Copilot reviews start no workflow, so the watchdog relays them.

## Files

- `.github/workflows/claude-coder.yml`: the coding agent, its chained review and its failure report.
- `.github/workflows/claude-reviewer.yml`: the review agent and its failure report.
- `.github/workflows/claude-loop-watchdog.yml`: the watchdog.
- `.github/claude-loop/loop.sh`: the shared logic without Claude.
- `.github/workflows/claude-vpn-test.yml`: the Gnosis VPN test on a machine.
- `.github/claude-loop/vpn-lock.sh`: the lock on the test machine.
- `AGENTS.md`: the procedure both agents follow.
- `demo/calc.py`, `tests/test_calc.py`: a tiny module and its tests, the material for test pull requests.
