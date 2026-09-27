# agent-demo: a coder agent and a review agent on one pull request

A proof of concept for reviewing pull requests with two Claude Code agents that never share a run: a **coder** that acts on comments and pushes fixes, and a **reviewer** that verifies every push and posts one review. Both run as GitHub Actions through the Claude Code GitHub Action, bill your Claude subscription rather than the API, and are switched on per pull request with one label. The procedure they follow is `AGENTS.md`; this file is the setup.

## Quick start

1. Install the Claude GitHub App on the repository and store a `claude setup-token` result as the secret `CLAUDE_CODE_OAUTH_TOKEN` (details below).
2. Create the label `claude-loop`.
3. Open a pull request and add the label. The reviewer runs; if it requests changes, the coder fixes and pushes; the reviewer approves when the tests pass and nothing remains.
4. Watch the Actions tab and the PR timeline. Remove the label to stop.

## How the loop runs

```
label `claude-loop` added, or any push to the PR branch
        │  pull_request: labeled / synchronize
        ▼
  claude-reviewer.yml ── runs the tests, checks the claims, posts ONE review "[reviewer] …"
        │  request changes ──► coder            approve ──► loop ends
        ▼
  claude-coder.yml ── fixes on the PR branch, pushes, replies "[coder] <hash> …"
        │  same run, second job: the reviewer workflow is called ──► reviewer again
        ▼
  after MAX_ROUNDS (5) request-changes rounds both stop and leave it to a human

  a team member's comment or review on the PR also goes straight to the coder
```

Both agents post as `claude[bot]`, so the workflows tell them apart by the `[coder]` and `[reviewer]` markers at the start of every post. The coder never reacts to `[coder]` posts or to approvals; the reviewer only reacts to pushes. Copilot's review is treated like a human review (its inline comments are ignored individually, since its review event already fires once).

## Finish the setup (once per repository)

1. **Install the Claude GitHub App** on this repository: https://github.com/apps/claude (repository admin required). The action uses its Contents, Issues and Pull requests permissions to push, comment and review. Alternatively run `/install-github-app` inside Claude Code in this checkout; choose "Skip for now" when it offers to write a workflow, since the workflows here are already in place.
2. **Create the subscription token and store it as a secret.** On your laptop, `claude setup-token` prints a long-lived OAuth token bound to your Claude subscription. Store it as the repository secret `CLAUDE_CODE_OAUTH_TOKEN`; the workflows pass it as `claude_code_oauth_token`, so runs use your Pro/Max/Team usage windows, not API credits. Three ways to store it, none of which puts the token in the repository:

   - **GitHub web UI, no CLI needed.** Repository → Settings → Secrets and variables → Actions → New repository secret; name `CLAUDE_CODE_OAUTH_TOKEN`, paste the token, Add secret. This is the simplest route when `gh` is not logged in.
   - **`gh` with a scoped personal token, no `gh auth login`.** Create a fine-grained personal access token at https://github.com/settings/personal-access-tokens/new with access to this repository only and one repository permission, **Secrets: read and write** (nothing else), and a short expiry. Then:
     ```bash
     read -rs GH_TOKEN && export GH_TOKEN          # paste the personal token; nothing echoes, nothing in history
     read -rs T && printf '%s' "$T" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo hoprnet/agent-demo   # paste the Claude token
     unset GH_TOKEN T
     ```
     `gh secret set` encrypts the value with the repository's public key before it leaves your machine; the personal token can be deleted afterwards.
   - **`gh auth login`** (browser device flow, about a minute), then `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo hoprnet/agent-demo` and paste when asked. `/install-github-app` inside Claude Code also stores the secret for you, but it requires this login as well.

   Why this is safe on a public repository: Actions secrets are encrypted at rest and cannot be read back through the API or the UI once saved. They are masked in workflow logs and withheld from workflows that pull requests from forks trigger. Keep the token out of every file under the repository, out of workflow `env:` literals and out of commit messages. Do not set `ANTHROPIC_API_KEY` as well; the workflows never reference it. The token is personal: it bills the subscription of whoever ran `claude setup-token`, so for a team pick the account whose allowance should pay. It can only make model requests: it is not a claude.ai login and cannot read conversations or account settings. If it ever leaks, revoke it in that account's claude.ai settings (or through Anthropic support), run `claude setup-token` again and replace the secret.

3. **Create the label** the loop is switched on with, `claude-loop`. Any of:
   - **Web UI:** repository → Issues → Labels → New label; name `claude-loop`, colour `5319E7`, description "Claude coder + reviewer agents act on this PR". Or create it inline the first time you apply it: on a pull request, the Labels gear in the sidebar offers "Create new label" when you type a name that does not exist yet.
   - **`gh` with the scoped personal token from step 2** (add the repository permission **Issues: read and write**, which is what labels need), no login:
     ```bash
     export GH_TOKEN=...   # or read -rs GH_TOKEN as above
     gh label create claude-loop --repo hoprnet/agent-demo --color 5319E7 --description "Claude coder + reviewer agents act on this PR"
     ```
   - **Plain `curl`** with the same token:
     ```bash
     curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
       https://api.github.com/repos/hoprnet/agent-demo/labels \
       -d '{"name":"claude-loop","color":"5319E7","description":"Claude coder + reviewer agents act on this PR"}'
     ```
   - **`gh auth login`**, then the `gh label create` line above.

4. **Check Actions are enabled** for the repository (Settings, Actions, General: allow all actions, or at least `anthropics/*` and `actions/*`). The jobs declare their own permissions, so the default `GITHUB_TOKEN` setting can stay read-only.
5. **Push this repository** (`git push origin main`). Workflows only trigger once they exist on the default branch.

Optional: add a `CLAUDE.md` with project conventions; the action reads it, as it reads `AGENTS.md`.

## Run the proof of concept

Nothing here needs `gh`: `git` over your SSH key and the GitHub web pages are enough. Where a `gh` one-liner exists it is given as an aside for people who are logged in.

1. **Branch, break something, push.**
   ```bash
   git checkout -b poc/mean-bug
   sed -i 's|return sum(values) / len(values)|return sum(values) / (len(values) + 1)|' demo/calc.py
   git commit -am "poc: introduce an off-by-one in mean()"
   git push -u origin poc/mean-bug
   ```
2. **Open the pull request** on the web: go to https://github.com/hoprnet/agent-demo/compare/poc/mean-bug?expand=1 (the repository page also shows a "Compare & pull request" banner for the branch you just pushed), keep `main` as the base, and create it. (`gh pr create --fill --repo hoprnet/agent-demo` does the same.)
3. **Follow the PR:** on the pull request page, click the gear next to **Labels** in the right-hand sidebar and pick `claude-loop` (or type the name and choose "Create new label" if it does not exist yet). (`gh pr edit <number> --add-label claude-loop`.) Adding the label fires the reviewer: it runs the tests, finds `test_mean` failing and requests changes with a numbered item naming `demo/calc.py`; that review fires the coder, which fixes the line, pushes, and replies `[coder] <hash> …`; the push fires the reviewer again, which approves. Expect three runs of a few minutes each.
4. **Try the other entry point:** in the pull request's conversation, write a comment such as "add a `subtract(a, b)` with a test" and post it. The coder acts on it, the reviewer checks the push. Any organisation member or collaborator with write access can do this; no `@claude` mention is needed on a labelled PR.
5. **Watch** under the repository's **Actions** tab (workflows `claude-coder` and `claude-reviewer`; each run's log shows what Claude read and ran) and in the pull request's timeline, where the `[coder]` comments and `[reviewer]` reviews land. If a run finishes in seconds with nothing posted, the PR branch's workflow files differ from `main`'s; see "Two GitHub details the workflows work around" below.
6. **Stop following:** remove the label from the same sidebar gear (`gh pr edit <number> --remove-label claude-loop`). Nothing runs on the PR after that. Re-adding it starts a new round, which is also how you continue after the round cap.

## Follow a new pull request

Add the `claude-loop` label, from the pull request's sidebar or with `gh pr edit <number> --add-label claude-loop`. That is the whole procedure: the workflows live in the repository once and apply to every PR that carries the label. The label starts the reviewer at once; its first review brings in the coder, which then also answers any comments that were already on the PR. Remove the label to stop; re-add it to continue after the round cap. The label is visible in the PR list, so you can see which PRs are under the loop.

For a one-off without subscribing, the interactive form still works: comment `@claude …` on any PR (the coder workflow's `issue_comment` trigger runs only for labelled PRs, so add a plain `@claude` workflow from https://github.com/anthropics/claude-code-action/blob/main/examples/claude.yml if you want that too).

## How the coder trigger works

`.github/workflows/claude-coder.yml` listens to three events: `issue_comment` (a comment in the PR conversation), `pull_request_review_comment` (an inline comment) and `pull_request_review` (a submitted review, which is also how Copilot posts). It does not run on the label event; the reviewer does, and its first review brings the coder in, so the two never race on a freshly labelled PR. The job's `if:` gate decides before the action starts:

- the PR must carry `claude-loop` (for `issue_comment` the labels are on `github.event.issue`);
- posts whose body starts with `[coder]` never trigger it (its own replies); the check is on the first characters, so a review that merely quotes "[coder]" still counts;
- a bot actor triggers it only when the body starts with `[reviewer]` or the actor is Copilot;
- inline review comments count only from humans, so one Copilot review fires one run, not one per inline comment;
- an approving review never triggers it;
- a human-authored event counts only when its author is a repository owner, a member of the organisation or a collaborator (`author_association`), so comments from strangers on a public repository never start a job. Labels need triage permission anyway, and fork PRs get no secrets, so outsiders cannot spend the subscription; team members can trigger as often as they like.

Inside the action, `allowed_bots: "claude[bot],copilot-pull-request-reviewer[bot]"` lets those two bots through the action's own human-actor check (which otherwise rejects every bot to prevent loops). A step before the action counts `[reviewer]` request-changes reviews and stops at `MAX_ROUNDS`, posting a `[coder]` note instead of running. A job-level `concurrency` group queues runs per PR so two comments in a row do not race on the same branch. The group sits on the job, not the workflow, for a reason: GitHub keeps only one queued run per group, and a workflow-level group would let a run the `if:` gate is about to skip (another bot's comment, the coder's own reply) cancel the queued run that matters. The prompt tells the coder what to read, how to commit and push (`git push origin HEAD` to the PR branch it checked out with `gh pr checkout`), and how to reply; the `--allowedTools` list is the hard limit on what it can run.

## How the reviewer trigger works

`.github/workflows/claude-reviewer.yml` listens to `pull_request: synchronize` (a push to the PR branch) and `labeled`, plus `workflow_dispatch` for a manual run by PR number, and it is callable (`workflow_call`) so the coder's run can chain it after a push. Pushes by the coder arrive as `claude[bot]`, hence `allowed_bots: "claude[bot]"`. Both workflows install `pytest` first (the GitHub runner image has python but not pytest). The reviewer checks out the PR head, has read-only tools plus `python -m pytest` and `gh pr review`, and must post exactly one review: request changes with a numbered list of things the coder can do, approve, or, at the round cap, a plain comment that ends the loop. Anything only a human can do (the PR description, closing the PR, a design decision) goes under a `For a human:` note and never by itself blocks approval, so the loop does not spend rounds on items it cannot resolve. `cancel-in-progress: true` drops a review of a commit that has already been superseded by a newer push.

## Migrate to another repository

1. Copy `.github/workflows/claude-coder.yml`, `.github/workflows/claude-reviewer.yml` and `AGENTS.md`.
2. In both workflows replace `python -m pytest` in the prompts and in `--allowedTools` with the repository's test command, and add any build or lint commands the agents may run to `--allowedTools` (nothing else is allowed).
3. Adjust `AGENTS.md`: keep the markers, the one-review rule and the cap; add the repository's own rules.
4. Install the Claude GitHub App on that repository, add the `CLAUDE_CODE_OAUTH_TOKEN` secret (a repository secret, or one organisation secret shared with selected repositories, remembering it bills one person's subscription), create the `claude-loop` label, push.
5. To keep the procedure in one place for many repositories, move the two workflows into a `claude-loop` repository as a reusable workflow (`on: workflow_call`) and give each repository a ten-line caller with the same `on:` block and `uses: <org>/claude-loop/.github/workflows/pr-loop.yml@main` plus `secrets: inherit`. Changing the procedure then changes it everywhere at once.

## Two GitHub details the workflows work around

- **A workflow's own push cannot wake another workflow.** GitHub attributes a push made from inside a workflow run to `github-actions[bot]`, whatever token the action used and however the commit is authored, and holds the `pull_request` run that push would trigger for manual approval (`action_required` in the Actions tab, until someone clicks "Approve and run"). So the coder's pushes never reach the reviewer through an event. Instead the coder workflow runs the reviewer as a second job of the same run (`workflow_call` into `claude-reviewer.yml`), only when the coder actually pushed. The standalone reviewer workflow still covers the label event and human pushes. A held duplicate run may still appear after a coder push; it can be ignored or approved, it reviews the same commit. Both workflows also set `bot_id: "209825114"` and `bot_name: "claude[bot]"`, the Claude GitHub App's own bot user, so the coder's commits are at least attributed to `claude[bot]` rather than to `github-actions[bot]`.
- **Workflow identity on `pull_request` events.** On these events (the reviewer's triggers) GitHub runs the workflow file as it is on the **PR branch**, and the Claude Code GitHub Action then refuses to start unless that file is byte-identical to the copy on the default branch. The run still shows green, with "Skipping action due to workflow validation" in the step log, and nothing happens. Two consequences:
  - A PR branch created before a change to `.github/workflows/` must be brought up to date before the loop works on it: `git checkout <branch> && git pull && git merge main && git push`. The push itself fires the reviewer.
  - A PR that itself edits the workflow files never runs the agents on `pull_request` events; the coder's comment triggers use the default branch's copy and keep working. Change the workflows on `main` (or a PR whose only purpose is that change), not inside a PR the agents are meant to work on. AGENTS.md already forbids the coder to touch them.

## Cost and limits

- Every run spends your subscription's five-hour and weekly usage windows, shared with your interactive sessions. The design keeps runs to one per event and caps the rounds; if a PR eats the allowance, lower `MAX_ROUNDS` or remove the label.
- The runners are GitHub-hosted. Anything that needs your own machine (a test host, a long measurement) is out of reach here; put those steps on a self-hosted runner (`runs-on: self-hosted` on a machine where `claude` is logged in also bills the subscription) or leave them to an interactive session, and have the coder say "needs a host run" instead.
- Branch protection that forbids pushes from apps blocks the coder's push; the run then fails visibly. The App cannot approve a PR it opened itself, so keep PRs human-opened for the reviewer's approval to count.
- Comment-triggered runs need the commenter to have write access (the action's own check) and to be an owner, member or collaborator (the workflow's gate). To let outside contributors drive the coder, widen the gate's `author_association` list and set the action's `allowed_non_write_users`.

## Files

- `.github/workflows/claude-coder.yml`, `.github/workflows/claude-reviewer.yml`: the two agents.
- `AGENTS.md`: the procedure both follow.
- `demo/calc.py`, `tests/test_calc.py`: a tiny module and its tests for the proof of concept.
