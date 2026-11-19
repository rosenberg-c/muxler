#!/usr/bin/env zsh
# Best-effort iTerm2 cleanup after `kill-session`.
#
# Panels are only closed when their outer iTerm tty was recorded by a muxler
# launch (@workspace_iterm_tty on the tmux session) AND the manifest written by
# that exact kill-session invocation verifies the sessions are gone. No title
# or process guessing is used, and any uncertainty leaves the tabs open.
set -u

MUXLER_CLOSEOUT_LOG=${MUXLER_CLOSEOUT_LOG:-$HOME/.muxler_closeout.log}
MUXLER_REMOTE_MANIFEST=${MUXLER_REMOTE_MANIFEST:-.muxler_closeout}
MUXLER_CLOSEOUT_AGE_LIMIT=${MUXLER_CLOSEOUT_AGE_LIMIT:-30}

closeout_log() {
  printf '%s muxler closeout: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$MUXLER_CLOSEOUT_LOG" 2>/dev/null || :
}

# Accept only the macos pty form iTerm2 reports. This also makes the value safe
# to embed in generated AppleScript.
valid_tty() {
  [[ $1 =~ '^/dev/ttys[0-9]+$' ]]
}

# tmux 3.8 returns rc=0 with empty stdout from display-message for a missing
# target, so its status alone is not a liveness check. has-session is the
# authority; display output is only a consistency check. Anything unexpected
# is treated as alive/uncertain, leaving tabs open.
muxler_session_gone() {
  local id=$1 out rc=0
  case $id in
    ''|\$|\$*[!0-9]*) return 1 ;;
    \$*) ;;
    *) return 1 ;;
  esac

  tmux has-session -t "$id" >/dev/null 2>&1 || rc=$?
  (( rc == 1 )) || return 1
  # A failed display here is consistent with tmux exiting after its last
  # session died; an exact id would contradict has-session.
  out=$(tmux display-message -p -t "$id" '#{session_id}' 2>/dev/null) || return 0
  [[ -z $out ]] || return 1
  return 0
}

close_ttys_from_file() {
  local tty_file=$1 line tmp err_tmp='' err_target=/dev/null osa_code='' tty_list
  local -a ttys=()
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    if ! valid_tty "$line"; then
      closeout_log "refusing to close invalid tty: $line"
      return 1
    fi
    ttys+=("$line")
  done < "$tty_file"
  (( ${#ttys} )) || return 0

  tty_list=$(printf '"%s",' "${ttys[@]}") || { closeout_log 'could not build tty list'; return 1; }
  tty_list=${tty_list%,}

  tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-iterm.XXXXXX" 2>/dev/null) || {
    closeout_log 'could not create AppleScript temp file'
    return 1
  }
  err_tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-iterm-err.XXXXXX" 2>/dev/null) || err_tmp=''
  [[ -n $err_tmp ]] && err_target=$err_tmp
  {
    print -r -- "set targetTtys to {$tty_list}"
    print -r -- 'set closeFailures to 0'
    print -r -- 'tell application "iTerm2"'
    print -r -- '  set windowCount to count of windows'
    print -r -- '  repeat with wi from windowCount to 1 by -1'
    print -r -- '    set w to window wi'
    print -r -- '    set tabCount to count of tabs of w'
    print -r -- '    repeat with ti from tabCount to 1 by -1'
    print -r -- '      set t to tab ti of w'
    print -r -- '      set sessionCount to count of sessions of t'
    print -r -- '      repeat with si from sessionCount to 1 by -1'
    print -r -- '        set s to session si of t'
    print -r -- '        if (tty of s) is in targetTtys then'
    print -r -- '          try'
    print -r -- '            close s'
    print -r -- '          on error'
    print -r -- '            set closeFailures to closeFailures + 1'
    print -r -- '          end try'
    print -r -- '        end if'
    print -r -- '      end repeat'
    print -r -- '    end repeat'
    print -r -- '  end repeat'
    print -r -- 'end tell'
    print -r -- 'if closeFailures > 0 then error "muxler closeout: some sessions could not be closed" number -128'
  } > "$tmp" || {
    rm -f -- "$tmp"
    [[ -z $err_tmp ]] || rm -f -- "$err_tmp"
    closeout_log 'could not write AppleScript'
    return 1
  }

  if ! osascript "$tmp" >/dev/null 2>"$err_target"; then
    # AppleScript errors can echo the script and its ttys; log only the error
    # code so a diagnostic never leaks pane identifiers.
    [[ -n $err_tmp ]] && osa_code=$(grep -Eo '\(-[0-9]+\)' "$err_tmp" 2>/dev/null | tail -n 1)
    if [[ -n $osa_code ]]; then
      closeout_log "iTerm2 automation failed ($osa_code); tabs left open"
    else
      closeout_log 'iTerm2 automation failed; tabs left open'
    fi
    rm -f -- "$tmp"
    [[ -z $err_tmp ]] || rm -f -- "$err_tmp"
    return 1
  fi
  rm -f -- "$tmp"
  [[ -z $err_tmp ]] || rm -f -- "$err_tmp"
  return 0
}

# Local manifest is written before the kills by .tmux_session.shared.sh. Poll
# briefly so the helper works whether it starts before or after the kills.
local_closeout() {
  local manifest=$1 id tty rest line
  local -a ids=() ttys=()
  local first=1 attempt alive=0 rc=0 tmp

  [[ -r $manifest ]] || return 0
  while IFS=$'\t' read -r id tty rest; do
    if (( first )); then
      first=0
      continue
    fi
    [[ -n $id && -n $tty ]] || continue
    valid_tty "$tty" || continue
    ids+=("$id")
    ttys+=("$tty")
  done < "$manifest"
  (( ${#ids} )) || return 0

  for (( attempt = 0; attempt < 25; attempt++ )); do
    alive=0
    for id in "${ids[@]}"; do
      if ! muxler_session_gone "$id"; then
        alive=1
        break
      fi
    done
    (( alive )) || break
    sleep 0.2
  done
  if (( alive )); then
    closeout_log 'local cleanup skipped: verified sessions still present'
    return 0
  fi

  tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-ttys.XXXXXX" 2>/dev/null) || {
    closeout_log 'could not create tty temp file'
    return 1
  }
  printf '%s\n' "${ttys[@]}" > "$tmp"
  close_ttys_from_file "$tmp"
  rc=$?
  rm -f -- "$tmp"
  return $rc
}

# Remote panes verify the outcome over a fresh SSH call after their attached
# session ends. The manifest is named for this attachment's token, checked for
# that token, and consumed once so a detach, stale file, or repeated observer
# cannot close unrelated panes.
remote_closeout() {
  local host=$1 session_name=$2 token=$3 manifest=${4:-$MUXLER_REMOTE_MANIFEST} tmp rc=0
  case $token in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 0 ;; esac
  case $manifest in ''|.|..|[!A-Za-z0-9.]*|*[!A-Za-z0-9._-]*) return 0 ;; esac

  tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-verify.XXXXXX" 2>/dev/null) || {
    closeout_log 'could not create verification temp file'
    return 1
  }
  if ! ssh "$host" "sh -s -- ${(qq)session_name} ${(qq)token} ${(qq)manifest} ${(qq)MUXLER_CLOSEOUT_AGE_LIMIT}" > "$tmp" <<'VERIFY_EOF'
set -eu
tab=$(printf '\t')
session_name=$1
token=$2
manifest=$3
age_limit=$4
case $manifest in ''|.|..|[!A-Za-z0-9.]*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
case $token in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) exit 0 ;; esac
# Same liveness rule as the local helper: has-session decides absence, and
# display output only rejects an inconsistent result. Fail open otherwise.
muxler_session_gone() {
  check_id=$1
  case $check_id in
    ''|\$|\$*[!0-9]*) return 1 ;;
    \$*) ;;
    *) return 1 ;;
  esac
  check_rc=0
  tmux has-session -t "$check_id" >/dev/null 2>&1 || check_rc=$?
  [ "$check_rc" = 1 ] || return 1
  check_out=$(tmux display-message -p -t "$check_id" '#{session_id}' 2>/dev/null) || return 0
  [ -z "$check_out" ] || return 1
  return 0
}
manifest_path="$HOME/$manifest.$token"
consumed_path="$manifest_path.consumed"
[ -r "$manifest_path" ] || exit 0
now=$(date +%s)
stamp=$(head -n 1 "$manifest_path" | cut -f1)
header_token=$(head -n 1 "$manifest_path" | cut -f2)
case $stamp in ''|*[!0-9]*) exit 0 ;; esac
[ "$header_token" = "$token" ] || exit 0
age=$((now - stamp))
[ "$age" -ge 0 ] && [ "$age" -le "$age_limit" ] || exit 0
tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-verified.XXXXXX") || exit 0
trap 'rm -f "$tmp"' 0
first=1
matched=0
while IFS="$tab" read -r id tty name; do
  if [ "$first" = 1 ]; then first=0; continue; fi
  [ -n "$id" ] || continue
  case $tty in
    /dev/ttys*) case ${tty#/dev/ttys} in ''|*[!0-9]*) exit 0 ;; esac ;;
    *) exit 0 ;;
  esac
  [ "$name" = "$session_name" ] && matched=1
  if ! muxler_session_gone "$id"; then
    exit 0
  fi
  printf '%s\n' "$tty" >> "$tmp"
done < "$manifest_path"
[ "$matched" = 1 ] || exit 0
mv -- "$manifest_path" "$consumed_path" || exit 0
cat "$tmp"
VERIFY_EOF
  then
    rm -f -- "$tmp"
    closeout_log "remote verification failed for $host"
    return 0
  fi
  if [[ ! -s $tmp ]]; then
    rm -f -- "$tmp"
    return 0
  fi

  close_ttys_from_file "$tmp"
  rc=$?
  rm -f -- "$tmp"
  return $rc
}

case ${1:-} in
  local)
    [[ $# -eq 2 ]] || exit 2
    local_closeout "$2"
    ;;
  remote)
    [[ $# -eq 5 ]] || exit 2
    remote_closeout "$2" "$3" "$4" "$5"
    ;;
  *)
    print -u2 -- 'usage: muxler_close_iterm.sh local <manifest> | remote <host> <session> <token> <manifest>'
    exit 2
    ;;
esac
