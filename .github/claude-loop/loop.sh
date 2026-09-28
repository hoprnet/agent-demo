#!/usr/bin/env bash
# claude-loop helper: everything the two agent workflows and the watchdog do WITHOUT Claude.
# Prechecks (is there anything to do?), round counting, the `claude-loop` commit status, acknowledgement
# reactions, postconditions (did the agent actually post?), failure reports and the watchdog.
#
# Needs: bash, gh, jq (all on ubuntu-latest). Environment: GH_TOKEN, GITHUB_REPOSITORY; optional GITHUB_SERVER_URL,
# GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT (for links to the run), LOOP_LABEL (default claude-loop).
# Every GitHub call goes through ghx: a 60 s timeout and three attempts, so a slow or flaky API never hangs a job.
set -euo pipefail

R="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}"
LABEL="${LOOP_LABEL:-claude-loop}"
ERROR_LABEL="${LABEL}:error"
CONTEXT="claude-loop"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
RUN_URL="${SERVER}/${R}/actions/runs/${GITHUB_RUN_ID:-0}"
HUMANS='["OWNER","MEMBER","COLLABORATOR"]'
BOT="claude[bot]"

log() { echo "loop: $*" >&2; }

ghx() {
  local i out rc
  for i in 1 2 3; do
    if out=$(timeout 60 gh "$@" 2>&1); then printf '%s' "$out"; return 0; else rc=$?; fi
    log "gh $1 ${2:-} failed (attempt $i, rc $rc): ${out:0:200}"
    # a client error other than 429 will not change on retry (not found, conflict, forbidden, invalid)
    if grep -qE 'HTTP 4[0-9][0-9]' <<<"$out" && ! grep -q 'HTTP 429' <<<"$out"; then return "$rc"; fi
    sleep $((i * 5))
  done
  return "$rc"
}

# JSON array of every item of a paginated list endpoint
list() { ghx api --paginate "$1" --jq '.[]' | jq -s '.'; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ISO time of the last time the loop label was added, or 1970 if never
label_time() {
  list "repos/$R/issues/$1/events" | jq -r --arg l "$LABEL" \
    '[.[] | select(.event == "labeled" and .label.name == $l) | .created_at] | max // "1970-01-01T00:00:00Z"'
}

# request-changes reviews by the reviewer agent since the label was (re-)added
rounds() {
  local since; since=$(label_time "$1")
  list "repos/$R/pulls/$1/reviews" | jq --arg s "$since" --arg b "$BOT" \
    '[.[] | select(.user.login == $b and .state == "CHANGES_REQUESTED" and (.body | startswith("[reviewer]")) and .submitted_at > $s)] | length'
}

head_sha() { ghx api "repos/$R/pulls/$1" --jq '.head.sha'; }

# set the one commit status the loop shows on the PR: status PR STATE DESCRIPTION [SHA]
status() {
  local pr=$1 state=$2 desc=$3 sha=${4:-}
  [ -n "$sha" ] || sha=$(head_sha "$pr")
  ghx api -X POST "repos/$R/statuses/$sha" -f state="$state" -f context="$CONTEXT" \
    -f description="${desc:0:139}" -f target_url="$RUN_URL" > /dev/null || log "could not set status"
}

ensure_label() {
  ghx api -X POST "repos/$R/labels" -f name="$ERROR_LABEL" -f color=B60205 \
    -f description="the claude-loop agents hit an error; see the [loop] comment" > /dev/null 2>&1 || true
}
mark_error() { ensure_label; ghx api -X POST "repos/$R/issues/$1/labels" -f "labels[]=$ERROR_LABEL" > /dev/null || true; }
clear_error() { timeout 60 gh api -X DELETE "repos/$R/issues/$1/labels/$(jq -rn --arg l "$ERROR_LABEL" '$l|@uri')" > /dev/null 2>&1 || true; }

# 👀 on the comment that triggered the coder, so a human sees it was picked up: ack EVENT_NAME COMMENT_ID
ack() {
  case "$1" in
    issue_comment) ghx api -X POST "repos/$R/issues/comments/$2/reactions" -f content=eyes > /dev/null || true ;;
    pull_request_review_comment) ghx api -X POST "repos/$R/pulls/comments/$2/reactions" -f content=eyes > /dev/null || true ;;
  esac
}

# Requests the coder has not seen yet, as a JSON array; the watermark is the latest `seen-until` the coder wrote.
coder_requests() {
  local pr=$1 comments reviews inline mark
  comments=$(list "repos/$R/issues/$pr/comments")
  reviews=$(list "repos/$R/pulls/$pr/reviews")
  inline=$(list "repos/$R/pulls/$pr/comments")
  mark=$(jq -r --arg b "$BOT" '[.[] | select(.user.login == $b and (.body | startswith("[coder]")))
          | ((.body | capture("seen-until: (?<t>[0-9TZ:.-]+)").t) // .created_at)] | max // "1970-01-01T00:00:00Z"' <<<"$comments")
  jq -n --arg m "$mark" --arg b "$BOT" --argjson h "$HUMANS" \
    --argjson c "$comments" --argjson r "$reviews" --argjson i "$inline" '
    def marker: startswith("[coder]") or startswith("[reviewer]") or startswith("[loop]");
    ( [ $c[] | select(.user.type != "Bot" and (.author_association as $a | $h | index($a)) and ((.body // "") | marker | not))
              | {kind: "comment", id, at: .created_at, by: .user.login} ]
    + [ $i[] | select(.user.type != "Bot" and (.author_association as $a | $h | index($a)) and ((.body // "") | marker | not))
              | {kind: "inline", id, at: .created_at, by: .user.login, path, line} ]
    + [ $r[] | select(
            (.user.type != "Bot" and (.author_association as $a | $h | index($a)) and .state != "APPROVED" and .state != "DISMISSED"
               and ((.body // "") | marker | not))
         or (.user.login == $b and .state == "CHANGES_REQUESTED" and ((.body // "") | startswith("[reviewer]")))
         or (.user.login == "copilot-pull-request-reviewer[bot]"))
              | {kind: "review", id, at: .submitted_at, by: .user.login, state} ] )
    | map(select(.at > $m)) | sort_by(.at)'
}

# exit 0 and print the open requests when there is work, exit 10 when there is none
coder_precheck() {
  local reqs n state; state=$(ghx api "repos/$R/pulls/$1" --jq '.state')
  if [ "$state" != "open" ]; then log "PR #$1 is $state; the loop only works on open pull requests"; return 10; fi
  reqs=$(coder_requests "$1"); n=$(jq length <<<"$reqs")
  if [ "$n" -eq 0 ]; then log "nothing new for the coder on PR #$1"; return 10; fi
  jq -c '.[]' <<<"$reqs"
}

# The reviewer's outcome for one commit, from the claude-loop status history of that exact commit (review
# objects cannot answer this: GitHub reports an approval's commit_id as the current head once commits are added).
# Prints the latest outcome description recorded since the label was added, or nothing.
OUTCOME_RE='^(approved by the reviewer|changes requested|round cap reached)'
reviewed_outcome() {
  local pr=$1 sha=$2 since; since=$(label_time "$pr")
  ghx api "repos/$R/commits/$sha/statuses?per_page=100" | jq -r --arg c "$CONTEXT" --arg s "$since" --arg re "$OUTCOME_RE" \
    '[.[] | select(.context == $c and .created_at > $s and (.description | test($re)))] | sort_by(.created_at) | last | .description // ""'
}

# exit 10 when the reviewer already reviewed this exact head since the label was added, or the PR is not open
reviewer_precheck() {
  local pr=$1 sha=$2 state outcome
  state=$(ghx api "repos/$R/pulls/$pr" --jq '.state')
  if [ "$state" != "open" ]; then log "PR #$pr is $state; the loop only works on open pull requests"; return 10; fi
  outcome=$(reviewed_outcome "$pr" "$sha")
  if [ -n "$outcome" ]; then log "head ${sha:0:7} of PR #$pr already reviewed since the label: $outcome"; return 10; fi
}

# postconditions: the agent must have posted in this run
coder_posted() {
  list "repos/$R/issues/$1/comments" | jq -e --arg b "$BOT" --arg s "$2" \
    '[.[] | select(.user.login == $b and (.body | startswith("[coder]")) and .created_at >= $s)] | length > 0' > /dev/null
}
reviewer_state() {
  list "repos/$R/pulls/$1/reviews" | jq -r --arg b "$BOT" --arg s "$2" \
    '[.[] | select(.user.login == $b and (.body | startswith("[reviewer]")) and .submitted_at >= $s)] | last | .state // ""'
}

# Settle the status after a coder run that did not push: the head's recorded review outcome, or waiting.
settle() {
  local pr=$1 sha outcome
  sha=$(head_sha "$pr"); outcome=$(reviewed_outcome "$pr" "$sha")
  case "$outcome" in
    approved*) status "$pr" success "approved by the reviewer" "$sha"; clear_error "$pr" ;;
    "changes requested"*) status "$pr" pending "changes requested; waiting for the coder or a human" "$sha" ;;
    "round cap"*) status "$pr" failure "round cap reached; a human decides" "$sha" ;;
    *) status "$pr" pending "waiting for the reviewer (head ${sha:0:7} not reviewed yet)" "$sha" ;;
  esac
}

# Start the coder by hand for a PR (workflow_dispatch is the one event a workflow token may trigger)
kick_coder() {
  local ref; ref=$(ghx api "repos/$R" --jq '.default_branch')
  ghx api -X POST "repos/$R/actions/workflows/claude-coder.yml/dispatches" -f ref="$ref" -f "inputs[pr]=$1" > /dev/null \
    && log "dispatched the coder for PR #$1" || log "could not dispatch the coder for PR #$1"
}

# After a review, record its outcome on the reviewed commit. after_review PR STATE ROUNDS MAX SHA
# An approval while human requests are still unanswered (comments made before the label, or while it was off)
# starts the coder, since no change request will.
after_review() {
  local pr=$1 st=$2 n=$3 max=$4 sha=$5
  case "$st" in
    APPROVED) status "$pr" success "approved by the reviewer" "$sha"; clear_error "$pr"
              if coder_precheck "$pr" > /dev/null 2>&1; then log "approved, but the coder has open requests"; kick_coder "$pr"; fi ;;
    CHANGES_REQUESTED) status "$pr" pending "changes requested (round $((n + 1)) of $max); coder is next" "$sha"; clear_error "$pr" ;;
    COMMENTED) cap "$pr" "$n" "$max"; status "$pr" failure "round cap reached ($max); a human decides" "$sha" ;;
  esac
}

# Delete the reviewer runs GitHub holds for approval: a push made from inside a workflow is attributed to
# github-actions[bot], and GitHub parks the pull_request run it triggers as "completed / action_required". Such a
# run cannot be cancelled (it is already completed), it shows on the PR as a check waiting for approval, and the
# chained review already covered its commit, so it is deleted.
cancel_held() {
  local ids; ids=$(ghx api "repos/$R/actions/runs?status=action_required&per_page=50" \
    --jq '.workflow_runs[] | select(.name == "claude-reviewer" and .actor.login == "github-actions[bot]") | .id' || true)
  for id in $ids; do ghx api -X DELETE "repos/$R/actions/runs/$id" > /dev/null && log "deleted held run $id" || log "could not delete held run $id"; done
}

# Classify a failure from log text on stdin: prints "headline|hint"
classify() {
  local t; t=$(cat)
  if grep -qiE 'workflow validation|identical content to the version' <<<"$t"; then
    echo "workflow file on the PR branch differs from main|merge main into the PR branch and push; see README, 'workflow identity'"
  elif grep -qiE 'CLAUDE_CODE_OAUTH_TOKEN is required|ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN|no credentials|secret.*not set' <<<"$t"; then
    echo "no Claude token available to this run|set the CLAUDE_CODE_OAUTH_TOKEN secret; fork pull requests never receive secrets"
  elif grep -qiE 'overloaded_error|(status|error|http|code)[: ]*529|api is overloaded' <<<"$t"; then
    echo "the Claude API was overloaded (a temporary Anthropic-side problem, not your quota)|retry in a few minutes: post a comment on the PR"
  elif grep -qiE 'usage limit|rate.?limit|quota|(status|error|http|code)[: ]*429|429 too many|too many requests|limit reached|hit your( usage)? limit|(weekly|session|5-hour|five-hour) limit|limit (will )?resets?|out of (usage|credits|extra usage)' <<<"$t"; then
    echo "Claude usage limit or rate limit reached|wait for the subscription window to reset, then comment on the PR or re-add the label"
  elif grep -qiE '(status|error|http|code)[: ]*401|401 unauthorized|authentication_error|authentication failed|invalid api key|please run /login|invalid.*(token|api key|x-api-key)|unauthori[sz]ed|OAuth token (has )?expired|invalid bearer' <<<"$t"; then
    echo "Claude authentication failed|the CLAUDE_CODE_OAUTH_TOKEN secret is invalid, expired or revoked; run claude setup-token and replace it"
  elif grep -qiE 'exceeding the configured maximum|max.?turns|error_max_turns' <<<"$t"; then
    echo "the agent hit its turn limit|raise --max-turns in the workflow, or split the request into smaller comments"
  elif grep -qiE 'has timed out|timed out after|exceeded the maximum execution time|timeout-minutes' <<<"$t"; then
    echo "the run timed out|the request may be too large for one run; split it, or raise timeout-minutes"
  elif grep -qiE 'did not post|produced no review|postcondition' <<<"$t"; then
    echo "the agent finished without posting its reply|see the run log for what it did"
  elif grep -qiE 'non-fast-forward|rejected.*fetch first|failed to push' <<<"$t"; then
    echo "the coder could not push (the branch moved or is protected)|push access and branch protection for the Claude app"
  else
    echo "the agent run failed|see the run log"
  fi
}

# diagnose FAILED_STEP EXEC_FILE AGENT_START LIMIT_MIN: run inside the failing job (`if: failure()`), where the
# agent's execution file is still on disk; writes headline, hint and lines to $GITHUB_OUTPUT for the report job.
# (The report job cannot read this job's log: logs are not downloadable while the workflow run is in progress.)
diagnose() {
  local step=$1 file=$2 start=$3 limit=$4 text="" hl hint elapsed=0
  if [ -f "$file" ]; then
    text=$(jq -r '([.[] | select(.type == "result")] | last) as $r | select($r != null and $r.is_error == true)
                  | "\($r.subtype // "?"): \(($r.result // "") | tostring | gsub("\n"; " ") | .[0:400])"' "$file" 2>/dev/null || true)
  fi
  if [ -n "$start" ]; then elapsed=$(( ( $(date -u +%s) - $(date -u -d "$start" +%s) ) / 60 )); fi
  case "$step" in
    agent)
      if [ -n "$limit" ] && [ "$elapsed" -ge $(( limit - 1 )) ]; then
        hl="the agent step hit its time limit (${limit} min; it ran about ${elapsed} min)"; hint="the request may be too large for one run; split it into smaller comments, or raise timeout-minutes"
      elif [ -z "${HAS_TOKEN:-true}" ] || [ "${HAS_TOKEN:-true}" = "false" ]; then
        hl="no Claude token available to this run"; hint="set the CLAUDE_CODE_OAUTH_TOKEN secret; fork pull requests never receive secrets"
      elif [ -n "$text" ]; then
        IFS='|' read -r hl hint < <(classify <<<"$text")
      else
        hl="the agent step failed before Claude produced a result"; hint="open the run log; this is usually the action's setup (token, network, or a GitHub outage)"
      fi ;;
    precheck) hl="the loop could not read the pull request from the GitHub API"; hint="usually a transient GitHub API problem; post a comment to retry" ;;
    postcondition)
      # no execution file at all means the action never ran Claude; the usual cause is its workflow-identity check
      if [ ! -f "$file" ] && ! git diff --quiet "origin/${DEFAULT_BRANCH:-main}" -- .github/workflows 2>/dev/null; then
        hl="the workflow files on this PR branch differ from ${DEFAULT_BRANCH:-main}, so the Claude action refused to run"
        hint="merge ${DEFAULT_BRANCH:-main} into the PR branch and push (workflow changes belong in their own PR)"
      else
        hl="the agent finished without posting its reply"; hint="see the run summary for refused tool calls; the agent may have been blocked from posting"
      fi ;;
    push) hl="the coder could not push"; hint="check push access and branch protection for the Claude app" ;;
    *) hl="a loop step failed (${step:-unknown})"; hint="see the run log" ;;
  esac
  {
    echo "headline=$hl"; echo "hint=$hint"
    echo "lines<<EOF_LINES"; [ -n "$text" ] && echo "agent: $text"; echo "failed step: ${step:-unknown}; agent ran ${elapsed} min"; echo "EOF_LINES"
  } >> "${GITHUB_OUTPUT:-/dev/stdout}"
  log "diagnosis: $hl"
}

# report PR ROLE: comment once, red status, error label. Uses the failing job's own diagnosis (DIAG_HEADLINE,
# DIAG_HINT, DIAG_LINES) when it produced one; otherwise it is a job that never reached its diagnose step
# (cancelled, timed out at job level, runner lost), and it falls back to the job log if GitHub already serves it.
report() {
  local pr=$1 role=$2 jobs logs lines hl hint body
  if [ -n "${DIAG_HEADLINE:-}" ]; then
    hl=$DIAG_HEADLINE; hint=${DIAG_HINT:-see the run log}; lines=${DIAG_LINES:-}
    post_report "$pr" "$role" "$hl" "$hint" "$lines"; return 0
  fi
  jobs=$(ghx api "repos/$R/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs" --jq \
    '.jobs[] | select((.conclusion == "failure" or .conclusion == "cancelled" or .conclusion == "timed_out")
       and ([.steps[]? | select(.conclusion != null and .conclusion != "skipped")] | length > 1)) | .id' || true)
  if [ -z "$jobs" ]; then log "no started job failed in this run (a queued run replaced by a newer one); nothing to report"; return 0; fi
  logs=""
  local j l try
  for j in $jobs; do
    # a finished job's log can take a few seconds to become downloadable
    for try in 1 2; do
      l=$(timeout 60 gh api "repos/$R/actions/jobs/$j/logs" 2>/dev/null || true)
      [ -n "$l" ] && break
      log "log of job $j not available yet (try $try)"; sleep 10
    done
    logs+="$l"$'\n'
  done
  lines=$(grep -E '##\[error\]|loop: FAIL|"is_error": *true|Error:|error:' <<<"$logs" | sed -E 's/^[0-9T:.Z-]+ //; s/##\[error\]//' \
          | grep -v '^\s*$' | awk '!seen[$0]++' | tail -8 | cut -c1-300 || true)
  IFS='|' read -r hl hint < <(classify <<<"$logs")
  if [ -z "$logs" ] || [ "$(tr -d '[:space:]' <<<"$logs")" = "" ]; then
    hl="the ${role} job stopped before it could diagnose itself (cancelled, timed out, or the runner was lost)"
    hint="open the run; post a comment or re-add the label to retry"
  fi
  post_report "$pr" "$role" "$hl" "$hint" "$lines"
}

post_report() {
  local pr=$1 role=$2 hl=$3 hint=$4 lines=$5 body
  local retry
  if [ "$role" = reviewer ]; then
    retry="To retry the review: remove and re-add the \`${LABEL}\` label, or run the claude-reviewer workflow from the Actions tab with PR number ${pr}."
  else
    retry="To retry: post any comment on this PR; the coder picks up every request it has not answered yet."
  fi
  body="[loop] ❌ **${role} failed: ${hl}.**

What to do: ${hint}. ${retry}

Run: ${RUN_URL}"
  if [ -n "$lines" ]; then body+="

Details:
\`\`\`
${lines}
\`\`\`"
  fi
  body+="
<!-- loop-incident: run-${GITHUB_RUN_ID}-${role} -->"
  ghx api -X POST "repos/$R/issues/$pr/comments" -f body="$body" > /dev/null || log "could not comment"
  status "$pr" failure "${role} failed: ${hl}"
  mark_error "$pr"
}

# Watchdog: loop incidents GitHub Actions itself cannot report (disabled workflows, lost triggers, dead runs).
STALL_MIN=${STALL_MIN:-30}
ACK_MIN=${ACK_MIN:-10}
incident() { # incident PR KEY TEXT
  local pr=$1 key=$2 text=$3 have
  have=$(list "repos/$R/issues/$pr/comments" | jq --arg k "loop-incident: $key" '[.[] | select(.body | contains($k))] | length')
  [ "$have" -gt 0 ] && { log "PR #$pr incident $key already reported"; return 0; }
  if [ -n "${DRY_RUN:-}" ]; then log "DRY_RUN: PR #$pr would report $key: $text"; return 0; fi
  ghx api -X POST "repos/$R/issues/$pr/comments" -f body="[loop] ⚠️ ${text}

<!-- loop-incident: $key -->" > /dev/null
  status "$pr" failure "${text:0:120}"
  mark_error "$pr"
  log "PR #$pr: reported $key"
}

watchdog() {
  local busy prs pr cut_ack cut_stall
  busy=$( { ghx api "repos/$R/actions/runs?status=in_progress&per_page=50" --jq '.workflow_runs[] | select(.name == "claude-coder" or .name == "claude-reviewer") | .id';
            ghx api "repos/$R/actions/runs?status=queued&per_page=50" --jq '.workflow_runs[] | select(.name == "claude-coder" or .name == "claude-reviewer") | .id'; } | wc -l)
  if [ "$busy" -gt 0 ]; then log "$busy agent run(s) in progress or queued; nothing to judge"; return 0; fi
  cut_ack=$(date -u -d "-${ACK_MIN} min" +%Y-%m-%dT%H:%M:%SZ)
  cut_stall=$(date -u -d "-${STALL_MIN} min" +%Y-%m-%dT%H:%M:%SZ)
  prs=$(ghx api "repos/$R/pulls?state=open&per_page=100" --jq ".[] | select(any(.labels[]; .name == \"$LABEL\")) | .number")
  for pr in $prs; do
    log "checking PR #$pr"
    local since comments inline unacked sha st bots
    # Copilot's reviews start no workflow (its review is itself produced by an Actions run), so the coder never
    # hears about them through an event; hand them over here
    bots=$(coder_requests "$pr" | jq '[.[] | select(.by | startswith("copilot"))] | length')
    if [ "$bots" -gt 0 ]; then log "PR #$pr: $bots Copilot review(s) the coder has not answered"; [ -n "${DRY_RUN:-}" ] || kick_coder "$pr"; continue; fi
    since=$(label_time "$pr")
    comments=$(list "repos/$R/issues/$pr/comments")
    inline=$(list "repos/$R/pulls/$pr/comments")
    # human comments after the label, older than ACK_MIN, that nobody acknowledged with 👀 and no [coder] reply followed
    unacked=$(jq -n --argjson c "$comments" --argjson i "$inline" --argjson h "$HUMANS" --arg s "$since" --arg cut "$cut_ack" --arg b "$BOT" '
      def marker: startswith("[coder]") or startswith("[reviewer]") or startswith("[loop]");
      ([$c[] | select(.user.login == $b and (.body | startswith("[coder]"))) | .created_at] | max // "") as $last
      | [ ($c[] + {k: "issues"}), ($i[] + {k: "pulls"}) ]
      | map(select(.user.type != "Bot" and (.author_association as $a | $h | index($a)) and ((.body // "") | marker | not)
                   and .created_at > $s and .created_at < $cut and .created_at > $last
                   and ((.reactions.eyes // 0) == 0)))
      | map({id, k, at: .created_at})')
    if [ "$(jq length <<<"$unacked")" -gt 0 ]; then
      local first; first=$(jq -r '.[0] | "\(.k)-\(.id)"' <<<"$unacked")
      incident "$pr" "unacked-$first" "no agent picked up a comment within ${ACK_MIN} minutes, and no agent run is active. GitHub Actions may be down or the claude-coder workflow disabled (Actions tab, workflow list). When it is back, post any comment on the PR to retry."
      continue
    fi
    sha=$(head_sha "$pr")
    st=$(ghx api "repos/$R/commits/$sha/status" --jq ".statuses[] | select(.context == \"$CONTEXT\") | \"\(.state) \(.updated_at)\"" | head -1 || true)
    if [ -z "$st" ] && reviewer_precheck "$pr" "$sha" 2>/dev/null; then
      local pushed later
      pushed=$(ghx api "repos/$R/commits/$sha" --jq '.commit.committer.date')
      # a head reviewed before this version recorded outcomes as statuses (a repo migrating to it) has no status;
      # a [reviewer] review submitted after the head commit was made counts as its review
      later=$(list "repos/$R/pulls/$pr/reviews" | jq --arg b "$BOT" --arg p "$pushed" \
        '[.[] | select(.user.login == $b and (.body | startswith("[reviewer]")) and .submitted_at > $p)] | length')
      if [ "$later" -eq 0 ] && [[ "$pushed" < "$cut_ack" && "$pushed" > "$since" ]]; then
        incident "$pr" "unreviewed-$sha" "the head commit ${sha:0:7} has had no review for over ${ACK_MIN} minutes and no agent run is active. The claude-reviewer workflow may be disabled or GitHub Actions down. Re-add the ${LABEL} label to retry."
      fi
    elif [[ "$st" == pending* ]] && [[ "${st#* }" < "$cut_stall" ]]; then
      incident "$pr" "stalled-$sha-${st#* }" "the loop has been waiting since ${st#* } (status pending) and no agent run is active: a run died without reporting, or the event that should have continued the loop was lost (for example while a workflow was disabled). Post a comment or re-add the ${LABEL} label to retry."
    fi
  done
}

# A threaded reply to an inline review comment, for the coder: reply PR COMMENT_ID BODY. The body gets the
# [coder] marker if it lacks it. A dedicated command keeps the coder's tool allow-list exact.
reply() {
  local pr=$1 id=$2 body=$3
  [[ "$body" == "[coder]"* ]] || body="[coder] $body"
  ghx api "repos/$R/pulls/$pr/comments/$id/replies" -f body="$body" --jq '"replied in thread \(.in_reply_to_id): \(.html_url)"'
}

# Summarise an agent run from the action's execution file into the job summary: turns, time, cost, and every
# tool call the allow-list refused (so a missing permission shows on the run page, not only as a vague excuse).
summary() {
  local file=$1 role=$2 out
  [ -f "$file" ] || { echo "no execution file for the ${role}" >> "${GITHUB_STEP_SUMMARY:-/dev/stderr}"; return 0; }
  out=$(jq -r --arg role "$role" '
    ([.[] | select(.type == "result")] | last) as $r
    | ([.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill")
        | (.input.skill // .input.name // "?")] | unique | join(", ")) as $skills
    | "### \($role) run\n\n| turns | duration | cost (API-equivalent) | refused tool calls | skills used |\n|---|---|---|---|---|\n"
      + "| \($r.num_turns // "?") | \((($r.duration_ms // 0) / 1000 | floor))s | $\($r.total_cost_usd // 0 | tostring | .[0:6]) | \(($r.permission_denials // []) | length) | \(if $skills == "" then "none" else $skills end) |\n"
      + (if (($r.permission_denials // []) | length) > 0 then
           "\nRefused (extend --allowedTools if these should be allowed):\n\n"
           + ([$r.permission_denials[] | "- `\(.tool_name)`: `\((.tool_input.command // (.tool_input | tostring))[0:200] | gsub("`"; "\u2032"))`"] | join("\n")) + "\n"
         else "" end)' "$file" 2>/dev/null || echo "could not read the execution file")
  echo "$out" >> "${GITHUB_STEP_SUMMARY:-/dev/stderr}"
  echo "$out"
  # the same list as a plain log line, so tests can grep for it
  jq -r '"loop: skills used: " + ([.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill")
         | (.input.skill // .input.name // "?")] | unique | join(", "))' "$file" 2>/dev/null || true
  # the agent's own error text, into the log where the report job can read and classify it
  jq -r '([.[] | select(.type == "result")] | last) as $r | select($r.is_error == true)
         | "loop: FAIL agent result (\($r.subtype // "?")): \(($r.result // "no result text") | tostring | gsub("\n"; " ") | .[0:400])"' \
    "$file" 2>/dev/null || true
}

# The round cap: one incident per label cycle. cap PR ROUNDS MAX
cap() {
  local pr=$1 n=$2 max=$3 since; since=$(label_time "$pr")
  incident "$pr" "cap-$since" "the review loop has reached its cap of $max change-request rounds since the ${LABEL} label was added. The reviewer's remaining findings are in its last review. A human decides now: fix by hand, close the PR, or remove and re-add the ${LABEL} label to allow another $max rounds. Team members' own comments still reach the coder."
}

cmd=${1:-}; shift || true
case "$cmd" in
  now) now ;;
  label-time) label_time "$@" ;;
  rounds) rounds "$@" ;;
  status) status "$@" ;;
  ack) ack "$@" ;;
  coder-requests) coder_requests "$@" ;;
  coder-precheck) coder_precheck "$@" ;;
  reviewer-precheck) reviewer_precheck "$@" ;;
  reviewed-outcome) reviewed_outcome "$@" ;;
  coder-posted) coder_posted "$@" ;;
  reviewer-state) reviewer_state "$@" ;;
  settle) settle "$@" ;;
  after-review) after_review "$@" ;;
  cancel-held) cancel_held ;;
  classify) classify ;;
  report) report "$@" ;;
  diagnose) diagnose "$@" ;;
  mark-error) mark_error "$@" ;;
  clear-error) clear_error "$@" ;;
  watchdog) watchdog ;;
  cap) cap "$@" ;;
  kick-coder) kick_coder "$@" ;;
  reply) reply "$@" ;;
  summary) summary "$@" ;;
  incident) incident "$@" ;;
  *) echo "usage: loop.sh <command> [args]; see the case list at the end of the file" >&2; exit 2 ;;
esac
