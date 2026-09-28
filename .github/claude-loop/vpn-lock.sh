#!/usr/bin/env bash
# Host-side lock for the Gnosis VPN test machine: at most one test at a time, whoever starts it (this repo's
# workflow, another repository, a person with the test-gnosis-vpn skill). Runs ON the host, piped over SSH:
#   ssh vpnhost 'bash -s' -- acquire "OWNER" [STALE_MIN] < vpn-lock.sh
# Commands: acquire OWNER [STALE_MIN] | refresh OWNER | release OWNER | status
# The lock is a directory under /run/lock: mkdir is atomic, and a reboot (the dead-man switch's last resort)
# clears it. Its `alive` file is touched by the tester's heartbeat; a lock silent for more than STALE_MIN minutes
# (default 15) belongs to a crashed tester and may be taken over.
# Exit codes: 0 done, 3 busy, 4 not the owner.
set -u
L=${GVPN_LOCK_DIR:-/run/lock/gvpn-test}
cmd=${1:-status}; owner=${2:-}; stale=${3:-15}
# every command runs inside a short critical section on a separate mutex file, so checking, taking over and
# releasing are atomic even when several testers start at the same second
exec 9> "$L.mutex" || { echo "cannot open $L.mutex"; exit 2; }
flock -w 20 9 || { echo "BUSY (could not enter the critical section)"; exit 3; }
now() { date +%s; }
# age of the last heartbeat; a lock without a heartbeat file yet counts from its own creation
age() { echo $(( $(now) - $(stat -c %Y "$L/alive" 2>/dev/null || stat -c %Y "$L" 2>/dev/null || now) )); }
take() { mkdir "$L" 2>/dev/null || return 1; printf '%s\n' "$owner" > "$L/owner"; touch "$L/alive"; }
case "$cmd" in
  acquire)
    [ -n "$owner" ] || { echo "usage: acquire OWNER [STALE_MIN]"; exit 2; }
    if take; then echo "ACQUIRED"; exit 0; fi
    cur=$(cat "$L/owner" 2>/dev/null || echo unknown)
    if [ "$cur" = "$owner" ]; then touch "$L/alive"; echo "ACQUIRED (already held)"; exit 0; fi
    a=$(age)
    if [ "$a" -gt $(( stale * 60 )) ]; then
      rm -rf "$L"
      if take; then echo "ACQUIRED (took over from '$cur', silent for ${a}s)"; exit 0; fi
    fi
    echo "BUSY held by '$cur', last heartbeat ${a}s ago"; exit 3 ;;
  refresh)
    if [ "$(cat "$L/owner" 2>/dev/null)" = "$owner" ]; then touch "$L/alive"; echo "OK"; else echo "NOT OWNER"; exit 4; fi ;;
  release)
    if [ "$(cat "$L/owner" 2>/dev/null)" = "$owner" ]; then rm -rf "$L"; echo "RELEASED"; else echo "NOT OWNER (held by '$(cat "$L/owner" 2>/dev/null || echo nobody)')"; exit 4; fi ;;
  status)
    if [ -d "$L" ]; then echo "HELD by '$(cat "$L/owner" 2>/dev/null)', last heartbeat $(age)s ago"; else echo "FREE"; fi ;;
  *) echo "usage: vpn-lock.sh acquire|refresh|release|status OWNER [STALE_MIN]"; exit 2 ;;
esac
