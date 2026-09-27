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
  local reqs n; reqs=$(coder_requests "$1"); n=$(jq length <<<"$reqs")
  if [ "$n" -eq 0 ]; then log "nothing new for the coder on PR #$1"; return 10; fi
  jq -c '.[]' <<<"$reqs"
}

# exit 10 when the reviewer already reviewed this head since the label was added
reviewer_precheck() {
  local pr=$1 sha=$2 since done_
  since=$(label_time "$pr")
  done_=$(list "repos/$R/pulls/$pr/reviews" | jq --arg b "$BOT" --arg s "$sha" --arg t "$since" \
    '[.[] | select(.user.login == $b and (.body | startswith("[reviewer]")) and .commit_id == $s and .submitted_at > $t)] | length')
  if [ "$done_" -gt 0 ]; then log "head $sha of PR #$pr already reviewed since the label"; return 10; fi
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

# Settle the status after a run that did not push: approved head -> green, otherwise waiting.
settle() {
  local pr=$1 sha state
  sha=$(head_sha "$pr")
  state=$(list "repos/$R/pulls/$pr/reviews" | jq -r --arg b "$BOT" --arg s "$sha" \
    '[.[] | select(.user.login == $b and (.body | startswith("[reviewer]")) and .commit_id == $s)] | last | .state // ""')
  case "$state" in
    APPROVED) status "$pr" success "approved by the reviewer" "$sha"; clear_error "$pr" ;;
    CHANGES_REQUESTED) status "$pr" pending "changes requested; waiting for the coder or a human" "$sha" ;;
    *) status "$pr" pending "waiting for the reviewer or a human" "$sha" ;;
  esac
}

# After a review: status from the review state. after_review PR STATE ROUNDS MAX
after_review() {
  local pr=$1 st=$2 n=$3 max=$4
  case "$st" in
    APPROVED) status "$pr" success "approved by the reviewer"; clear_error "$pr" ;;
    CHANGES_REQUESTED) status "$pr" pending "changes requested (round $((n + 1)) of $max); coder is next" ;;
    COMMENTED) status "$pr" failure "round cap reached ($max); a human decides"; mark_error "$pr" ;;
  esac
}

# Cancel reviewer runs GitHub is holding for approval (pushes from workflows are attributed to github-actions[bot]).
cancel_held() {
  local ids; ids=$(ghx api "repos/$R/actions/runs?status=action_required&per_page=50" \
    --jq '.workflow_runs[] | select(.name == "claude-reviewer") | .id' || true)
  for id in $ids; do ghx api -X POST "repos/$R/actions/runs/$id/cancel" > /dev/null && log "cancelled held run $id" || true; done
}

# Classify a failure from log text on stdin: prints "headline|hint"
classify() {
  local t; t=$(cat)
  if grep -qiE 'workflow validation|identical content to the version' <<<"$t"; then
    echo "workflow file on the PR branch differs from main|merge main into the PR branch and push; see README, 'workflow identity'"
  elif grep -qiE 'CLAUDE_CODE_OAUTH_TOKEN is required|ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN|no credentials|secret.*not set' <<<"$t"; then
    echo "no Claude token available to this run|set the CLAUDE_CODE_OAUTH_TOKEN secret; fork pull requests never receive secrets"
  elif grep -qiE 'usage limit|rate.?limit|quota|(status|error|http|code)[: ]*429|429 too many|too many requests|limit reached|out of (usage|credits)|overloaded_error' <<<"$t"; then
    echo "Claude usage limit or rate limit reached|wait for the subscription window to reset, then comment on the PR or re-add the label"
  elif grep -qiE '(status|error|http|code)[: ]*401|401 unauthorized|authentication_error|authentication failed|invalid.*(token|api key|x-api-key)|unauthori[sz]ed|OAuth token (has )?expired|invalid bearer' <<<"$t"; then
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

# report PR ROLE: read the failed jobs of this run, classify, comment once, red status, error label
report() {
  local pr=$1 role=$2 jobs logs lines hl hint body
  jobs=$(ghx api "repos/$R/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs" --jq \
    '.jobs[] | select((.conclusion == "failure" or .conclusion == "cancelled" or .conclusion == "timed_out")
       and ([.steps[]? | select(.conclusion != null and .conclusion != "skipped")] | length > 1)) | .id' || true)
  if [ -z "$jobs" ]; then log "no started job failed in this run (a queued run replaced by a newer one); nothing to report"; return 0; fi
  logs=""
  for j in $jobs; do logs+=$(timeout 60 gh api "repos/$R/actions/jobs/$j/logs" 2>/dev/null || true); logs+=$'\n'; done
  lines=$(grep -E '##\[error\]|loop: FAIL|"is_error": *true|Error:|error:' <<<"$logs" | sed -E 's/^[0-9T:.Z-]+ //; s/##\[error\]//' \
          | grep -v '^\s*$' | awk '!seen[$0]++' | tail -8 | cut -c1-300 || true)
  IFS='|' read -r hl hint < <(classify <<<"$logs")
  body="[loop] ❌ **${role} failed: ${hl}.**

What to do: ${hint}.

Run: ${RUN_URL}"
  if [ -n "$lines" ]; then body+="

Last error lines from the log:
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
    local since comments inline unacked sha st
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
      local pushed; pushed=$(ghx api "repos/$R/commits/$sha" --jq '.commit.committer.date')
      if [[ "$pushed" < "$cut_ack" && "$pushed" > "$since" ]]; then
        incident "$pr" "unreviewed-$sha" "the head commit ${sha:0:7} has had no review for over ${ACK_MIN} minutes and no agent run is active. The claude-reviewer workflow may be disabled or GitHub Actions down. Re-add the ${LABEL} label to retry."
      fi
    elif [[ "$st" == pending* ]] && [[ "${st#* }" < "$cut_stall" ]]; then
      incident "$pr" "stalled-$sha-${st#* }" "the loop has been waiting since ${st#* } (status pending) and no agent run is active: a run died without reporting. Post a comment or re-add the ${LABEL} label to retry."
    fi
  done
}

# The round cap: one incident per label cycle. cap PR ROUNDS MAX
cap() {
  local pr=$1 n=$2 max=$3 since; since=$(label_time "$pr")
  incident "$pr" "cap-$since" "the reviewer has requested changes $n times since the ${LABEL} label was added (cap: $max). The loop stops here and a human decides. To grant another $max rounds, remove and re-add the ${LABEL} label."
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
  coder-posted) coder_posted "$@" ;;
  reviewer-state) reviewer_state "$@" ;;
  settle) settle "$@" ;;
  after-review) after_review "$@" ;;
  cancel-held) cancel_held ;;
  classify) classify ;;
  report) report "$@" ;;
  mark-error) mark_error "$@" ;;
  clear-error) clear_error "$@" ;;
  watchdog) watchdog ;;
  cap) cap "$@" ;;
  incident) incident "$@" ;;
  *) echo "usage: loop.sh <command> [args]; see the case list at the end of the file" >&2; exit 2 ;;
esac
