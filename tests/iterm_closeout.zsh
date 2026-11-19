#!/usr/bin/env zsh
set -eu

root=${0:A:h:h}
fixture=$(mktemp -d)
socket=''
trap '[[ -z $socket ]] || command tmux -L "$socket" kill-server 2>/dev/null || true; rm -rf -- "$fixture"' EXIT
mkdir -p -- "$fixture/bin" "$fixture/home"
export MUXLER_CLOSEOUT_LOG="$fixture/closeout.log"
export MUXLER_TEST_OSA_LOG="$fixture/osa.log"
export MUXLER_TEST_SEQUENCE_LOG="$fixture/sequence.log"
export MUXLER_REMOTE_MANIFEST=.muxler_closeout

fail() { print -u2 -- "$1"; exit 1; }

cat > "$fixture/bin/osascript" <<'EOF'
#!/bin/sh
[ -z "${MUXLER_TEST_SEQUENCE_LOG:-}" ] || printf 'osascript\n' >> "$MUXLER_TEST_SEQUENCE_LOG"
cat -- "$1" >> "$MUXLER_TEST_OSA_LOG"
if [ "${MUXLER_TEST_OSA_MODE:-}" = fail ]; then
  printf '%s: execution error: iTerm2 got an error: cannot close /dev/ttys001 (-1719)\n' "$1" >&2
  exit 1
fi
EOF
cat > "$fixture/bin/tmux" <<'EOF'
#!/bin/sh
cmd=${1:-}
[ "$#" -gt 0 ] && shift
target=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -t ]; then
    shift
    target=${1:-}
  fi
  shift
done
[ -z "${MUXLER_TEST_TMUX_LOG:-}" ] || printf 'tmux %s %s\n' "$cmd" "$target" >> "$MUXLER_TEST_TMUX_LOG"
[ -z "${MUXLER_TEST_SEQUENCE_LOG:-}" ] || printf 'tmux %s %s\n' "$cmd" "$target" >> "$MUXLER_TEST_SEQUENCE_LOG"

mock_live() {
  [ -n "$target" ] || return 1
  case ${MUXLER_TEST_TMUX_ALIVE:-0} in
    1|all) return 0 ;;
  esac
  if [ -n "${MUXLER_TEST_TMUX_LIVE_FILE:-}" ] && [ -r "$MUXLER_TEST_TMUX_LIVE_FILE" ]; then
    while IFS= read -r live; do
      [ "$target" = "$live" ] && return 0
    done < "$MUXLER_TEST_TMUX_LIVE_FILE"
  fi
  for live in ${MUXLER_TEST_TMUX_LIVE_IDS:-}; do
    [ "$target" = "$live" ] && return 0
  done
  return 1
}

case $cmd in
  has-session)
    if mock_live; then exit 0; fi
    case ${MUXLER_TEST_TMUX_MODE:-} in
      uncertain) exit 2 ;;
    esac
    exit 1
    ;;
  display-message)
    if mock_live; then
      printf '%s\n' "$target"
      exit 0
    fi
    case ${MUXLER_TEST_TMUX_MODE:-} in
      uncertain) exit 1 ;;
    esac
    # tmux 3.8: a missing target is rc=0 with empty stdout.
    exit 0
    ;;
esac
exit 1
EOF
cat > "$fixture/bin/sleep" <<'EOF'
#!/bin/sh
[ -z "${MUXLER_TEST_SEQUENCE_LOG:-}" ] || printf 'sleep\n' >> "$MUXLER_TEST_SEQUENCE_LOG"
if [ -n "${MUXLER_TEST_SLEEP_CLEAR_FILE:-}" ]; then
  : > "$MUXLER_TEST_SLEEP_CLEAR_FILE"
fi
exit 0
EOF
cat > "$fixture/bin/ssh" <<'EOF'
#!/bin/sh
case ${MUXLER_TEST_SSH_MODE:-} in
  verified) printf '%s\n' /dev/ttys003 ;;
  invalid) printf '%s\n' ../../not-a-tty ;;
esac
exit 0
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
helper="$root/scripts/muxler_close_iterm.sh"

# The mock reproduces the tmux 3.8 behavior that caused the bug.
: > "$MUXLER_TEST_SEQUENCE_LOG"
missing_out=$(tmux display-message -p -t '$987654' '#{session_id}')
missing_rc=$?
[[ $missing_rc == 0 && -z $missing_out ]] || fail 'mock lacks tmux 3.8 missing-target behavior'
if tmux has-session -t '$987654' >/dev/null 2>&1; then
  fail 'mock reported a missing session as alive'
fi
: > "$MUXLER_TEST_SEQUENCE_LOG"

# A verified local manifest closes only the recorded ttys, never a title match.
: > "$MUXLER_TEST_OSA_LOG"
: > "$fixture/local_tmux.log"
printf '1700000000\tlocal-blue\t%s\n' "$PWD" > "$fixture/local.manifest"
printf '$1\t/dev/ttys001\tsession_one\n$2\t/dev/ttys002\tsession_two\n' >> "$fixture/local.manifest"
MUXLER_TEST_TMUX_LOG="$fixture/local_tmux.log" \
  zsh "$helper" local "$fixture/local.manifest" || fail 'local closeout failed'
grep -Fq 'has-session $1' "$fixture/local_tmux.log" || fail 'local liveness check skipped has-session'
grep -Fq 'has-session $2' "$fixture/local_tmux.log" || fail 'local liveness check skipped a recorded id'
script=$(<"$MUXLER_TEST_OSA_LOG")
[[ $script == *'tell application "iTerm2"'* ]] || fail 'no iTerm automation generated'
[[ $script == *'{"/dev/ttys001","/dev/ttys002"}'* ]] || fail 'recorded ttys were not targeted'
[[ $script != *'title'* && $script != *'name of'* ]] || fail 'closeout used title or name guessing'

# Mutation-safe traversal: closing a target must not invalidate the collection
# still being walked (the "only the first tab closes" regression).
if grep -Eq 'repeat with [A-Za-z_]+ in ' "$MUXLER_TEST_OSA_LOG"; then
  fail 'closeout iterated a live window/tab/session collection'
fi
grep -Fq 'repeat with wi from windowCount to 1 by -1' "$MUXLER_TEST_OSA_LOG" ||
  fail 'windows were not traversed by descending index'
grep -Fq 'set w to window wi' "$MUXLER_TEST_OSA_LOG" || fail 'window was not resolved by index'
grep -Fq 'repeat with ti from tabCount to 1 by -1' "$MUXLER_TEST_OSA_LOG" ||
  fail 'tabs were not traversed by descending index'
grep -Fq 'set t to tab ti of w' "$MUXLER_TEST_OSA_LOG" || fail 'tab was not resolved by index'
grep -Fq 'repeat with si from sessionCount to 1 by -1' "$MUXLER_TEST_OSA_LOG" ||
  fail 'sessions were not traversed by descending index'
grep -Fq 'set s to session si of t' "$MUXLER_TEST_OSA_LOG" || fail 'session was not resolved by index'
grep -Fq 'if (tty of s) is in targetTtys then' "$MUXLER_TEST_OSA_LOG" ||
  fail 'close was not restricted to targeted ttys'
[[ $(grep -Fc 'close s' "$MUXLER_TEST_OSA_LOG") == 1 ]] || fail 'unexpected close statements'

# AppleScript failures are logged by numeric code only, never script or tty text.
: > "$MUXLER_CLOSEOUT_LOG"
if MUXLER_TEST_OSA_MODE=fail zsh "$helper" local "$fixture/local.manifest" >/dev/null 2>&1; then
  fail 'osascript failure was not propagated'
fi
[[ $(<"$MUXLER_CLOSEOUT_LOG") == *'(-1719)'* ]] || fail 'AppleScript error code was not preserved'
[[ $(<"$MUXLER_CLOSEOUT_LOG") != *'/dev/ttys001'* ]] || fail 'diagnostic leaked a tty value'

# If any verified session is still present, uncertainty keeps every tab open.
: > "$MUXLER_TEST_OSA_LOG"
MUXLER_TEST_TMUX_ALIVE=1 zsh "$helper" local "$fixture/local.manifest" || fail 'uncertain closeout should be harmless'
[[ ! -s $MUXLER_TEST_OSA_LOG ]] || fail 'uncertain local closeout closed panes'
[[ $(<"$MUXLER_CLOSEOUT_LOG") == *'still present'* ]] || fail 'uncertainty was not reported in log'

# Unexpected tmux failures are also uncertainty, not proof that a pane died.
: > "$MUXLER_TEST_OSA_LOG"
MUXLER_TEST_TMUX_MODE=uncertain zsh "$helper" local "$fixture/local.manifest" || fail 'failed liveness check should be harmless'
[[ ! -s $MUXLER_TEST_OSA_LOG ]] || fail 'failed liveness check closed panes'

# A multi-tab manifest closes only after every recorded session id is gone.
# The first poll sees $12 alive; the sleep stub retires it for the second poll.
: > "$MUXLER_TEST_OSA_LOG"
: > "$MUXLER_TEST_SEQUENCE_LOG"
: > "$fixture/multi_tmux.log"
live_file="$fixture/multi_live"
printf '$12\n' > "$live_file"
printf '1700000000\tlocal-multi\t%s\n' "$PWD" > "$fixture/multi.manifest"
printf '$11\t/dev/ttys040\tmulti_one\n$12\t/dev/ttys041\tmulti_two\n' >> "$fixture/multi.manifest"
MUXLER_TEST_TMUX_LIVE_FILE=$live_file \
  MUXLER_TEST_SLEEP_CLEAR_FILE=$live_file \
  MUXLER_TEST_TMUX_LOG="$fixture/multi_tmux.log" \
  zsh "$helper" local "$fixture/multi.manifest" || fail 'multi-tab closeout failed'
[[ $(grep -Fc 'has-session $11' "$fixture/multi_tmux.log") == 2 ]] ||
  fail 'multi-tab helper did not repoll the first id'
[[ $(grep -Fc 'has-session $12' "$fixture/multi_tmux.log") == 2 ]] ||
  fail 'multi-tab helper did not wait for the live id to die'
[[ $(<"$MUXLER_TEST_OSA_LOG") == *'{"/dev/ttys040","/dev/ttys041"}'* ]] ||
  fail 'multi-tab closeout did not target both recorded ttys'
osa_line=$(grep -n '^osascript$' "$MUXLER_TEST_SEQUENCE_LOG" | head -n 1 | cut -d: -f1)
sleep_line=$(grep -n '^sleep$' "$MUXLER_TEST_SEQUENCE_LOG" | head -n 1 | cut -d: -f1)
last_live_line=$(grep -n '^tmux has-session \$12$' "$MUXLER_TEST_SEQUENCE_LOG" | tail -n 1 | cut -d: -f1)
[[ -n $osa_line && -n $sleep_line && $sleep_line -lt $osa_line ]] ||
  fail 'osascript ran before the live id was observed dead'
[[ -n $last_live_line && $osa_line -gt $last_live_line ]] ||
  fail 'osascript did not follow the final liveness check'

# Remote closeout acts only on an SSH-verified manifest with valid ttys.
: > "$MUXLER_TEST_OSA_LOG"
MUXLER_TEST_SSH_MODE=verified zsh "$helper" remote debian-dev session_one tokenA .muxler_closeout ||
  fail 'remote closeout failed'
[[ $(<"$MUXLER_TEST_OSA_LOG") == *'{"/dev/ttys003"}'* ]] || fail 'verified remote tty was not closed'
: > "$MUXLER_TEST_OSA_LOG"
zsh "$helper" remote debian-dev session_one tokenMissing .muxler_closeout ||
  fail 'missing manifest closeout failed'
[[ ! -s $MUXLER_TEST_OSA_LOG ]] || fail 'missing remote manifest closed panes'
if MUXLER_TEST_SSH_MODE=invalid zsh "$helper" remote debian-dev session_one tokenA .muxler_closeout >/dev/null 2>&1; then
  fail 'invalid tty from remote verification was accepted'
fi
[[ ! -s $MUXLER_TEST_OSA_LOG ]] || fail 'invalid tty triggered iTerm automation'
[[ $(<"$MUXLER_CLOSEOUT_LOG") == *'refusing to close invalid tty'* ]] || fail 'invalid tty was not reported'
: > "$MUXLER_TEST_OSA_LOG"
zsh "$helper" remote debian-dev session_one 'bad/token' .muxler_closeout || fail 'invalid token was not rejected'
[[ ! -s $MUXLER_TEST_OSA_LOG ]] || fail 'invalid token triggered iTerm automation'

# Exercise the streamed verifier itself. Each token has its own manifest, is
# consumed once, and cannot be replayed or used by another attachment.
mkdir -p -- "$fixture/remote_home" "$fixture/verify_bin"
cp -- "$fixture/bin/tmux" "$fixture/verify_bin/tmux"
chmod +x "$fixture/verify_bin/tmux"
sed -n '/^set -eu$/,/^VERIFY_EOF$/p' "$helper" | sed '$d' > "$fixture/verify.sh"
sh -n "$fixture/verify.sh" || fail 'streamed verifier is not valid sh'
verify() {
  PATH="$fixture/verify_bin:$PATH" HOME="$fixture/remote_home" \
    sh "$fixture/verify.sh" "$@"
}
now=$(date +%s)
printf '%s\ttokenA\tremote-cyan\t/tmp\n$1\t/dev/ttys010\tsession_x\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenA"
printf '%s\ttokenB\tremote-cyan\t/tmp\n$2\t/dev/ttys011\tsession_y\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenB"
: > "$fixture/verify_tmux.log"
[[ $(MUXLER_TEST_TMUX_LOG="$fixture/verify_tmux.log" \
    verify session_x tokenA .muxler_closeout 30) == /dev/ttys010 ]] ||
  fail 'verifier did not emit token A tty'
grep -Fq 'has-session $1' "$fixture/verify_tmux.log" ||
  fail 'remote verifier skipped has-session'
[[ -e $fixture/remote_home/.muxler_closeout.tokenA.consumed ]] || fail 'token A manifest was not consumed'
[[ -e $fixture/remote_home/.muxler_closeout.tokenB ]] || fail 'token B manifest was overwritten'
[[ -z $(verify session_x tokenA .muxler_closeout 30) ]] || fail 'consumed manifest was replayed'
[[ $(verify session_y tokenB .muxler_closeout 30) == /dev/ttys011 ]] || fail 'token B manifest was not usable'
[[ -e $fixture/remote_home/.muxler_closeout.tokenB.consumed ]] || fail 'token B manifest was not consumed'

# A custom manifest name is honored by the verifier, with the same validation.
printf '%s\ttokenC\tremote-cyan\t/tmp\n$1\t/dev/ttys012\tsession_c\n' "$now" \
  > "$fixture/remote_home/.custom.tokenC"
[[ $(verify session_c tokenC .custom 30) == /dev/ttys012 ]] || fail 'custom manifest was not verified'
[[ -z $(verify session_c tokenC '.muxler/closeout' 30) ]] || fail 'manifest path traversal was accepted'
[[ -e $fixture/remote_home/.custom.tokenC.consumed ]] || fail 'custom manifest was not consumed'

# Stale, wrong-token, and live-session manifests are ignored and not consumed.
printf '1\ttokenD\tremote-cyan\t/tmp\n$1\t/dev/ttys013\tsession_d\n' \
  > "$fixture/remote_home/.muxler_closeout.tokenD"
[[ -z $(verify session_d tokenD .muxler_closeout 30) ]] || fail 'stale manifest was accepted'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenD.consumed ]] || fail 'stale manifest was consumed'
printf '%s\totherToken\tremote-cyan\t/tmp\n$1\t/dev/ttys014\tsession_e\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenE"
[[ -z $(verify session_e tokenE .muxler_closeout 30) ]] || fail 'wrong header token was accepted'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenE.consumed ]] || fail 'wrong-token manifest was consumed'
printf '%s\ttokenG\tremote-cyan\t/tmp\n$1\t/dev/ttys016\tsession_other\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenG"
[[ -z $(verify session_x tokenG .muxler_closeout 30) ]] || fail 'wrong attachment session was accepted'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenG.consumed ]] || fail 'wrong-session manifest was consumed'
printf '%s\ttokenF\tremote-cyan\t/tmp\n$1\t/dev/ttys015\tsession_f\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenF"
[[ -z $(MUXLER_TEST_TMUX_ALIVE=all \
    verify session_f tokenF .muxler_closeout 30) ]] || fail 'live-session manifest was accepted'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenF.consumed ]] || fail 'live-session manifest was consumed'

# The remote verifier applies the same rule to every recorded id: any live id
# blocks consumption, and an unexpected tmux failure also fails open.
: > "$fixture/remote_tmux.log"
printf '%s\ttokenH\tremote-cyan\t/tmp\n$20\t/dev/ttys042\tsession_h\n$21\t/dev/ttys043\tsession_h\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenH"
printf '$21\n' > "$fixture/remote_live"
[[ -z $(MUXLER_TEST_TMUX_LIVE_FILE="$fixture/remote_live" \
    MUXLER_TEST_TMUX_LOG="$fixture/remote_tmux.log" \
    verify session_h tokenH .muxler_closeout 30) ]] ||
  fail 'remote verifier accepted a manifest with a live id'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenH.consumed ]] ||
  fail 'remote manifest with a live id was consumed'
: > "$fixture/remote_live"
verified_ttys=$(MUXLER_TEST_TMUX_LOG="$fixture/remote_tmux.log" \
  verify session_h tokenH .muxler_closeout 30)
[[ $verified_ttys == $'/dev/ttys042\n/dev/ttys043' ]] ||
  fail 'remote verifier did not emit both dead-session ttys'
[[ $(grep -Fc 'has-session $21' "$fixture/remote_tmux.log") == 2 ]] ||
  fail 'remote verifier did not check every recorded id'
[[ -e $fixture/remote_home/.muxler_closeout.tokenH.consumed ]] ||
  fail 'fully dead remote manifest was not consumed'

printf '%s\ttokenI\tremote-cyan\t/tmp\n$1\t/dev/ttys044\tsession_i\n' "$now" \
  > "$fixture/remote_home/.muxler_closeout.tokenI"
[[ -z $(MUXLER_TEST_TMUX_MODE=uncertain \
    verify session_i tokenI .muxler_closeout 30) ]] ||
  fail 'remote verifier accepted an uncertain liveness result'
[[ ! -e $fixture/remote_home/.muxler_closeout.tokenI.consumed ]] ||
  fail 'uncertain remote manifest was consumed'

# kill-session still kills when the closeout helper is missing or fails.
socket="workspace-closeout-$$-$RANDOM"
PATH="${PATH#$fixture/bin:}"  # restore real tmux for the integration part
tmux() { command tmux -L "$socket" "$@"; }
source "$root/.tmux_session.shared.sh"
cat > "$fixture/failing_helper" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$MUXLER_TEST_HELPER_LOG"
exit 1
EOF
chmod +x "$fixture/failing_helper"
export MUXLER_TEST_HELPER_LOG="$fixture/helper.log"
export MUXLER_CLOSEOUT_SCRIPT="$fixture/failing_helper"
unset MUXLER_TEST_TMUX_ALIVE

make_session() {
  local name=$1 tty=$2 group=$3 marker=$4 id
  id=$(tmux_session_prepare "$PWD" "$name" 'bg=#354f75,fg=white' nvim)
  tmux set-option -t "$id" @workspace_local_group "$group"
  tmux set-option -t "$id" @workspace_local_name "$marker"
  [[ -z $tty ]] || tmux set-option -t "$id" @workspace_iterm_tty "$tty"
  print -r -- "$id"
}

paired=$(make_session closeout_one /dev/ttys004 local-blue closeout_one)
current=$(make_session closeout_two /dev/ttys005 local-blue closeout_two)
unmarked=$(make_session closeout_other '' local-blue closeout_other)
pane=$(tmux list-panes -t "$current" -F '#{pane_id}')
TMUX=isolated TMUX_PANE="$pane" kill-session || fail 'kill-session failed when closeout helper fails'
[[ -z $(tmux_session_id closeout_one 2>/dev/null) && -z $(tmux_session_id closeout_two 2>/dev/null) && -z $(tmux_session_id closeout_other 2>/dev/null) ]] || fail 'kill-session skipped kills on closeout failure'
i=0
while (( i < 20 )) && [[ ! -s $MUXLER_TEST_HELPER_LOG ]]; do sleep 0.1; (( ++i )); done
[[ -s $MUXLER_TEST_HELPER_LOG ]] || fail 'closeout helper was not signalled'
[[ ${$(<"$MUXLER_TEST_HELPER_LOG")[1]} == local ]] || fail 'closeout helper received wrong mode'

# A remote group writes a manifest named for that attachment's token and
# configured manifest basename; the kill still proceeds.
remote=$(tmux_session_prepare "$PWD" remote_one 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$remote" @workspace_remote_group remote-cyan
tmux set-option -t "$remote" @workspace_remote_name remote_one
tmux set-option -t "$remote" @workspace_iterm_tty /dev/ttys006
tmux set-option -t "$remote" @workspace_iterm_token remoteToken1
tmux set-option -t "$remote" @workspace_closeout_manifest .muxler_closeout
remote_pane=$(tmux list-panes -t "$remote" -F '#{pane_id}')
[[ ! -e $fixture/home/.muxler_closeout ]] || fail 'manifest existed before remote kill-session'
HOME=$fixture/home MUXLER_CLOSEOUT_SCRIPT= TMUX=isolated TMUX_PANE="$remote_pane" kill-session ||
  fail 'remote kill-session failed'
[[ -r $fixture/home/.muxler_closeout.remoteToken1 ]] || fail 'remote kill-session did not write a token manifest'
[[ ! -e $fixture/home/.muxler_closeout ]] || fail 'remote kill-session wrote the shared manifest path'
[[ $(<"$fixture/home/.muxler_closeout.remoteToken1") == *'/dev/ttys006'* ]] || fail 'remote manifest lacks verified tty'
[[ $(<"$fixture/home/.muxler_closeout.remoteToken1") == *$'\t'remoteToken1$'\t'* ]] || fail 'remote manifest lacks its token header'
[[ -z $(tmux_session_id remote_one 2>/dev/null) ]] || fail 'remote kill-session did not kill its session'

# Singleton fallback: a recorded muxler tty is enough for local closeout, even
# without group/name markers. Unmarked sessions without it stay kill-only.
helper_count() {
  local lines
  lines=$(wc -l < "$MUXLER_TEST_HELPER_LOG")
  print -r -- "${lines// /}"
}
local -a helper_args=()
before=$(helper_count)
fallback_local=$(tmux_session_prepare "$PWD" fallback_local 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$fallback_local" @workspace_iterm_tty /dev/ttys030
fallback_pane=$(tmux list-panes -t "$fallback_local" -F '#{pane_id}')
TMUX=isolated TMUX_PANE="$fallback_pane" kill-session || fail 'local fallback kill-session failed'
[[ -z $(tmux_session_id fallback_local 2>/dev/null) ]] || fail 'local fallback did not kill its session'
after=$(helper_count)
(( after == before + 2 )) || fail 'local fallback did not prepare closeout'
helper_args=()
while IFS= read -r arg; do helper_args+=("$arg"); done < "$MUXLER_TEST_HELPER_LOG"
fallback_manifest=${helper_args[$((before + 2))]}
[[ $(<"$fallback_manifest") == *'/dev/ttys030'* ]] || fail 'local fallback manifest lacks its tty'

before=$(helper_count)
unrelated_local=$(tmux_session_prepare "$PWD" fallback_unrelated 'bg=#354f75,fg=white' nvim)
unrelated_pane=$(tmux list-panes -t "$unrelated_local" -F '#{pane_id}')
TMUX=isolated TMUX_PANE="$unrelated_pane" kill-session || fail 'unrelated local kill-session failed'
[[ -z $(tmux_session_id fallback_unrelated 2>/dev/null) ]] || fail 'unrelated local session was not killed'
[[ $(helper_count) == $before ]] || fail 'unmarked unrelated session signalled closeout'

before=$(helper_count)
external_local=$(tmux_session_prepare "$PWD" fallback_external 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$external_local" @workspace_iterm_tty /dev/ttys031
tmux kill-session -t "$external_local"
[[ $(helper_count) == $before ]] || fail 'external local kill signalled closeout'

# Remote fallback has no group/name marker, but a valid token and recorded tty
# identify the exact session name used by the verifier.
mkdir -p -- "$fixture/fallback_home"
fallback_remote=$(tmux_session_prepare "$PWD" remote_fallback 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$fallback_remote" @workspace_iterm_tty /dev/ttys032
tmux set-option -t "$fallback_remote" @workspace_iterm_token remoteFallbackToken
tmux set-option -t "$fallback_remote" @workspace_closeout_manifest .muxler_closeout
fallback_remote_pane=$(tmux list-panes -t "$fallback_remote" -F '#{pane_id}')
HOME=$fixture/fallback_home MUXLER_CLOSEOUT_SCRIPT= TMUX=isolated TMUX_PANE="$fallback_remote_pane" \
  kill-session || fail 'remote fallback kill-session failed'
fallback_remote_manifest="$fixture/fallback_home/.muxler_closeout.remoteFallbackToken"
[[ -r $fallback_remote_manifest ]] || fail 'remote fallback did not write a token manifest'
[[ $(<"$fallback_remote_manifest") == *'/dev/ttys032'* ]] || fail 'remote fallback manifest lacks its tty'
[[ $(<"$fallback_remote_manifest") == *'remote_fallback'* ]] || fail 'remote fallback manifest lacks exact session name'
verified=$(PATH="$fixture/verify_bin:$PATH" HOME="$fixture/fallback_home" \
  sh "$fixture/verify.sh" remote_fallback remoteFallbackToken .muxler_closeout 30)
[[ $verified == /dev/ttys032 ]] || fail 'remote fallback was not verified without a group marker'
[[ -e $fallback_remote_manifest.consumed ]] || fail 'remote fallback manifest was not consumed'

# A remote fallback without a trustworthy token stays kill-only.
fallback_files_before=$(find "$fixture/fallback_home" -maxdepth 1 -type f | wc -l | tr -d ' ')
no_token=$(tmux_session_prepare "$PWD" remote_no_token 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$no_token" @workspace_iterm_tty /dev/ttys033
no_token_pane=$(tmux list-panes -t "$no_token" -F '#{pane_id}')
HOME=$fixture/fallback_home MUXLER_CLOSEOUT_SCRIPT= TMUX=isolated TMUX_PANE="$no_token_pane" \
  kill-session || fail 'remote fallback without token failed'
[[ -z $(tmux_session_id remote_no_token 2>/dev/null) ]] || fail 'remote fallback without token was not killed'
fallback_files_after=$(find "$fixture/fallback_home" -maxdepth 1 -type f | wc -l | tr -d ' ')
[[ $fallback_files_after == $fallback_files_before ]] || fail 'untrusted remote fallback wrote a manifest'

# Remote external kills and ordinary detaches produce no manifest to consume.
mkdir -p -- "$fixture/external_home" "$fixture/detach_home"
external_remote=$(tmux_session_prepare "$PWD" remote_external 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$external_remote" @workspace_iterm_tty /dev/ttys034
tmux set-option -t "$external_remote" @workspace_iterm_token externalToken
tmux set-option -t "$external_remote" @workspace_closeout_manifest .muxler_closeout
HOME=$fixture/external_home tmux kill-session -t "$external_remote"
[[ ! -e $fixture/external_home/.muxler_closeout.externalToken ]] || fail 'external remote kill wrote a manifest'
detached=$(PATH="$fixture/verify_bin:$PATH" HOME="$fixture/detach_home" \
  sh "$fixture/verify.sh" remote_fallback detachToken .muxler_closeout 30)
[[ -z $detached ]] || fail 'ordinary detach triggered closeout'
[[ ! -e $fixture/detach_home/.muxler_closeout.detachToken.consumed ]] || fail 'ordinary detach consumed a manifest'

# Direct writer tests cover overlap, custom manifest names, and strict ttys.
mkdir -p -- "$fixture/writer_home"
make_writer_session() {
  local name=$1 tty=$2 token=$3 manifest=$4 id
  id=$(tmux_session_prepare "$PWD" "$name" 'bg=#354f75,fg=white' nvim)
  tmux set-option -t "$id" @workspace_iterm_tty "$tty"
  tmux set-option -t "$id" @workspace_iterm_token "$token"
  [[ -z $manifest ]] || tmux set-option -t "$id" @workspace_closeout_manifest "$manifest"
  print -r -- "$id"
}
writer_a=$(make_writer_session writer_a /dev/ttys020 writerTokenA '')
writer_b=$(make_writer_session writer_b /dev/ttys021 writerTokenB '')
printf '%s\n' "$writer_a" |
  HOME=$fixture/writer_home MUXLER_REMOTE_MANIFEST=.muxler_closeout \
    tmux_kill_session_prepare_closeout remote writer-group "$PWD"
printf '%s\n' "$writer_b" |
  HOME=$fixture/writer_home MUXLER_REMOTE_MANIFEST=.muxler_closeout \
    tmux_kill_session_prepare_closeout remote writer-group "$PWD"
[[ $(<"$fixture/writer_home/.muxler_closeout.writerTokenA") == *'/dev/ttys020'* ]] || fail 'writer A manifest is wrong'
[[ $(<"$fixture/writer_home/.muxler_closeout.writerTokenB") == *'/dev/ttys021'* ]] || fail 'writer B manifest overwrote A'
[[ $(<"$fixture/writer_home/.muxler_closeout.writerTokenB") != *'/dev/ttys020'* ]] || fail 'writer B manifest leaked A tty'

writer_c=$(make_writer_session writer_c /dev/ttys022 writerTokenC .custom)
printf '%s\n' "$writer_c" |
  HOME=$fixture/writer_home MUXLER_REMOTE_MANIFEST=.ignored \
    tmux_kill_session_prepare_closeout remote writer-group "$PWD"
[[ -r $fixture/writer_home/.custom.writerTokenC ]] || fail 'writer ignored @workspace_closeout_manifest'
[[ ! -e $fixture/writer_home/.ignored.writerTokenC ]] || fail 'writer used the wrong manifest override'
writer_d=$(make_writer_session writer_d /dev/ttys023 writerTokenD '')
printf '%s\n' "$writer_d" |
  HOME=$fixture/writer_home MUXLER_REMOTE_MANIFEST=.env_custom \
    tmux_kill_session_prepare_closeout remote writer-group "$PWD"
[[ -r $fixture/writer_home/.env_custom.writerTokenD ]] || fail 'writer ignored MUXLER_REMOTE_MANIFEST'
writer_bad=$(make_writer_session writer_bad /dev/ttys009junk writerTokenBad '')
printf '%s\n' "$writer_bad" |
  HOME=$fixture/writer_home MUXLER_REMOTE_MANIFEST=.muxler_closeout \
    tmux_kill_session_prepare_closeout remote writer-group "$PWD"
[[ ! -e $fixture/writer_home/.muxler_closeout.writerTokenBad ]] || fail 'writer accepted a lax tty glob'

# The local SSH attachment records the outer tty and passes a fresh token and
# manifest name to both the remote options and the closeout helper.
source "$root/.zsh_tmux"
export MUXLER_TEST_CONNECT_LOG="$fixture/connect.log"
cat > "$fixture/connect_helper" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >> "$MUXLER_TEST_CONNECT_LOG"
EOF
chmod +x "$fixture/connect_helper"
ssh() { connect_command=$3; }
tty() { print -r -- /dev/ttys007; }
TMUX= MUXLER_CLOSEOUT_SCRIPT= MUXLER_REMOTE_MANIFEST=.connect_custom \
  tmux_connect debian-dev session_x >/dev/null
[[ $connect_command == *'@workspace_iterm_tty'*'/dev/ttys007'* ]] || fail 'remote attach did not record the outer tty'
[[ $connect_command == *'@workspace_closeout_manifest'*'.connect_custom'* ]] || fail 'remote attach did not pass the manifest override'
token_line=$(grep -F '@workspace_iterm_token' <<< "$connect_command")
token=${token_line##*@workspace_iterm_token }
token=${token//\'/}
token=${token%% *}
[[ $token == [A-Za-z0-9]* ]] || fail 'remote attach did not generate a valid token'
: > "$MUXLER_TEST_CONNECT_LOG"
TMUX= MUXLER_CLOSEOUT_SCRIPT="$fixture/connect_helper" MUXLER_REMOTE_MANIFEST=.connect_custom \
  tmux_connect debian-dev session_x >/dev/null
token2_line=$(grep -F '@workspace_iterm_token' <<< "$connect_command")
token2=${token2_line##*@workspace_iterm_token }
token2=${token2//\'/}
token2=${token2%% *}
[[ $token2 == [A-Za-z0-9]* && $token2 != "$token" ]] || fail 'token was reused across attachments'
local -a connect_args=()
while IFS= read -r arg; do connect_args+=("$arg"); done < "$MUXLER_TEST_CONNECT_LOG"
[[ ${connect_args[1]} == remote && ${connect_args[2]} == debian-dev && ${connect_args[3]} == session_x ]] ||
  fail 'remote closeout got the wrong host or session'
[[ ${connect_args[4]} == "$token2" ]] || fail 'remote closeout got the wrong token'
[[ ${connect_args[5]} == .connect_custom ]] || fail 'remote closeout got the wrong manifest'

print 'iTerm closeout tests passed'
