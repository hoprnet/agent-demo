# agent-demo: a coder agent and a review agent on one pull request

A proof of concept for reviewing pull requests with two Claude Code agents that never share a run: a **coder** that acts on
comments and pushes fixes, and a **reviewer** that verifies every push and posts one review. Both run as GitHub Actions
through the Claude Code GitHub Action, bill your Claude **subscription** (not the API), and are switched on per pull request
with one label. The procedure they follow is `AGENTS.md`; this file is the setup.

## How the loop runs

```
human, Copilot or reviewer posts on a labelled PR
        │  issue_comment / pull_request_review(_comment)
        ▼
  claude-coder.yml ── fixes on the PR branch, pushes, replies "[coder] <hash> …"
        │  pull_request: synchronize (the push)
        ▼
  claude-reviewer.yml ── runs the tests, checks the claims, posts ONE review "[reviewer] …"
        │  request changes ──► back to the coder          approve ──► loop ends
        ▼
  after MAX_ROUNDS (5) request-changes rounds both stop and leave it to a human
```

Both agents post as `claude[bot]`, so the workflows tell them apart by the `[coder]` and `[reviewer]` markers at the start of
every post. The coder never reacts to `[coder]` posts or to approvals; the reviewer only reacts to pushes. Copilot's review is
treated like a human review (its inline comments are ignored individually, since its review event already fires once).

## Finish the setup (once per repository)

1. **Install the Claude GitHub App** on this repository: https://github.com/apps/claude (repository admin required). The
   action uses its Contents, Issues and Pull requests permissions to push, comment and review. Alternatively run
   `/install-github-app` inside Claude Code in this checkout; choose "Skip for now" when it offers to write a workflow,
   since the workflows here are already in place.
2. **Create the subscription token and store it as a secret.** On your laptop:
   ```bash
   claude setup-token        # prints a long-lived OAuth token bound to your Claude subscription
   gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo hoprnet/agent-demo   # paste the token when asked
   ```
   The workflows pass it as `claude_code_oauth_token`; runs then use your Pro/Max/Team usage windows, not API credits.
   Do not also set `ANTHROPIC_API_KEY`; the workflows never reference it. The token is personal: it bills the subscription
   of whoever ran `claude setup-token`, so for a team pick the account whose allowance should pay.
3. **Create the label** the loop is switched on with:
   ```bash
   gh label create claude-loop --repo hoprnet/agent-demo --color 5319E7 --description "Claude coder + reviewer agents act on this PR"
   ```
4. **Check Actions are enabled** for the repository (Settings, Actions, General: allow all actions, or at least
   `anthropics/*` and `actions/*`). The jobs declare their own permissions, so the default `GITHUB_TOKEN` setting can stay
   read-only.
5. **Push this repository** (`git push origin main`). Workflows only trigger once they exist on the default branch.

Optional: add a `CLAUDE.md` with project conventions; the action reads it, as it reads `AGENTS.md`.

## Run the proof of concept

1. Branch, break something, open a pull request:
   ```bash
   git checkout -b poc/mean-bug
   sed -i 's|return sum(values) / len(values)|return sum(values) / (len(values) + 1)|' demo/calc.py
   git commit -am "poc: introduce an off-by-one in mean()" && git push -u origin poc/mean-bug
   gh pr create --fill --repo hoprnet/agent-demo
   ```
2. **Follow the PR:** add the label.
   ```bash
   gh pr edit <number> --add-label claude-loop
   ```
   Adding the label fires both workflows once: the reviewer runs the tests, finds `test_mean` failing and requests changes
   with a numbered item naming `demo/calc.py`; that review fires the coder, which fixes the line, pushes, and replies
   `[coder] <hash> …`; the push fires the reviewer again, which approves. Expect three or four runs and a few minutes each.
3. Try the other entry point: comment on the PR, for example "add a `subtract(a, b)` with a test". The coder acts on it,
   the reviewer checks the push. Anyone with write access can do this; no `@claude` mention is needed on a labelled PR.
4. Watch under the repository's **Actions** tab (`claude-coder`, `claude-reviewer`) and in the PR's timeline.
5. **Stop following:** `gh pr edit <number> --remove-label claude-loop`. Nothing runs on the PR after that.

## Follow a new pull request

Add the `claude-loop` label. That is the whole procedure: the workflows live in the repository once and apply to every PR
that carries the label, and the `labeled` event starts the first round immediately, including for comments that were
already there. Remove the label to stop; re-add it to continue after the round cap. The label is visible in the PR list, so
you can see which PRs are under the loop.

For a one-off without subscribing, the interactive form still works: comment `@claude …` on any PR (the coder workflow's
`issue_comment` trigger runs only for labelled PRs, so add a plain `@claude` workflow from
https://github.com/anthropics/claude-code-action/blob/main/examples/claude.yml if you want that too).

## How the coder trigger works

`.github/workflows/claude-coder.yml` listens to four events: `issue_comment` (a comment in the PR conversation),
`pull_request_review_comment` (an inline comment), `pull_request_review` (a submitted review, which is also how Copilot posts)
and `pull_request: labeled`. The job's `if:` gate decides before the action starts:

- the PR must carry `claude-loop` (for `issue_comment` the labels are on `github.event.issue`);
- posts whose body contains `[coder]` never trigger it (its own replies);
- a bot actor triggers it only when the body carries `[reviewer]` or the actor is Copilot; humans always do;
- inline review comments count only from humans, so one Copilot review fires one run, not one per inline comment;
- an approving review never triggers it.

Inside the action, `allowed_bots: "claude[bot],copilot-pull-request-reviewer[bot]"` lets those two bots through the
action's own human-actor check (which otherwise rejects every bot to prevent loops). A step before the action counts
`[reviewer]` request-changes reviews and stops at `MAX_ROUNDS`, posting a `[coder]` note instead of running. `concurrency`
queues runs per PR so two comments in a row do not race on the same branch. The prompt tells the coder what to read, how to
commit and push (`git push origin HEAD` to the PR branch it checked out with `gh pr checkout`), and how to reply; the
`--allowedTools` list is the hard limit on what it can run.

## How the reviewer trigger works

`.github/workflows/claude-reviewer.yml` listens to `pull_request: synchronize` (every push to the PR branch, including the
coder's) and `labeled`, plus `workflow_dispatch` for a manual run by PR number. Pushes by the coder arrive as
`claude[bot]`, hence `allowed_bots: "claude[bot]"`. The reviewer checks out the PR head, has read-only tools plus
`python -m pytest` and `gh pr review`, and must post exactly one review: request changes with a numbered list, approve, or,
at the round cap, a plain comment that ends the loop. `cancel-in-progress: true` drops a review of a commit that has already
been superseded by a newer push.

## Migrate to another repository

1. Copy `.github/workflows/claude-coder.yml`, `.github/workflows/claude-reviewer.yml` and `AGENTS.md`.
2. In both workflows replace `python -m pytest` in the prompts and in `--allowedTools` with the repository's test command,
   and add any build or lint commands the agents may run to `--allowedTools` (nothing else is allowed).
3. Adjust `AGENTS.md`: keep the markers, the one-review rule and the cap; add the repository's own rules.
4. Install the Claude GitHub App on that repository, add the `CLAUDE_CODE_OAUTH_TOKEN` secret (a repository secret, or one
   organisation secret shared with selected repositories, remembering it bills one person's subscription), create the
   `claude-loop` label, push.
5. To keep the procedure in one place for many repositories, move the two workflows into a `claude-loop` repository as a
   reusable workflow (`on: workflow_call`) and give each repository a ten-line caller with the same `on:` block and
   `uses: <org>/claude-loop/.github/workflows/pr-loop.yml@main` plus `secrets: inherit`. Changing the procedure then changes
   it everywhere at once.

## Cost and limits

- Every run spends your subscription's five-hour and weekly usage windows, shared with your interactive sessions. The
  design keeps runs to one per event and caps the rounds; if a PR eats the allowance, lower `MAX_ROUNDS` or remove the label.
- The runners are GitHub-hosted. Anything that needs your own machine (a test host, a long measurement) is out of reach
  here; put those steps on a self-hosted runner (`runs-on: self-hosted` on a machine where `claude` is logged in also bills
  the subscription) or leave them to an interactive session, and have the coder say "needs a host run" instead.
- Branch protection that forbids pushes from apps blocks the coder's push; the run then fails visibly. The App cannot
  approve a PR it opened itself, so keep PRs human-opened for the reviewer's approval to count.
- Comment-triggered runs need the commenter to have write access (the action's own check); allow others with
  `allowed_non_write_users` if you want outside contributors to drive the coder.

## Files

- `.github/workflows/claude-coder.yml`, `.github/workflows/claude-reviewer.yml`: the two agents.
- `AGENTS.md`: the procedure both follow.
- `demo/calc.py`, `tests/test_calc.py`: a tiny module and its tests for the proof of concept.
