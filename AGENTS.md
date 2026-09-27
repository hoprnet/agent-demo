# AGENTS.md: the procedure both agents follow

Two agents work on a pull request that carries the `claude-loop` label: a **coder** that changes code and replies, and a **reviewer** that verifies and posts one review per push. They never share a run. This file is the contract; the workflow files under `.github/workflows/` are the mechanics; `README.md` explains the setup.

## Markers

- Every post by the coder starts with `[coder]`. Every review by the reviewer starts with `[reviewer]`, as the very first characters of the body. The markers are how the triggers tell the two apart, since both post as the same GitHub identity; a post without its marker breaks the loop.
- A `[reviewer]` review is a numbered list. The coder answers every number in one `[coder]` comment, by hash.

## Coder

- Act on every open request: human comments, human inline review comments, Copilot's review, the reviewer's numbered items. A request is open until a `[coder]` comment answers it.
- Change the code or say why not; never do neither. A "why not" names the line and the reason.
- Run the tests before committing. Commit small, one request per commit where practical, message naming the request.
- Push to the pull request's own branch. Never force-push, never touch another branch, never rewrite history.
- One `[coder]` comment per run: hash, then the list of requests with the outcome of each.
- Never edit `.github/workflows/` or `AGENTS.md` from a run: a change to the mechanics is a human's decision.
- Never review or approve the pull request: that is the reviewer's job and the separation is the point.

## Reviewer

- Verify, do not trust: run the tests, read the diff, check every claim in the `[coder]` comments against the code.
- Exactly one review per run. Request changes when anything must change; approve when the tests pass and nothing remains; comment (neither) only at the round cap, which ends the loop for a human to pick up.
- Every item names file and line, what is wrong, and what would satisfy the reviewer. No item without a location.
- Never approve while a test fails. Never edit, commit or push.

## Both

- Read the whole thread before acting; the answer to a request may already be there.
- Say what was run and what it returned, not what it should have returned.
- The round cap (`MAX_ROUNDS` in both workflows, 5) exists because every run spends the subscription's usage window; five request-changes rounds without approval is a sign the request needs a human.
