#!/usr/bin/env zsh
set -eu

root=${0:A:h:h}
fixture=$(mktemp -d)
socket="workspace-config-toggle-$$-$RANDOM"
trap 'command tmux -L "$socket" kill-server 2>/dev/null || true; rm -rf -- "$fixture"' EXIT

mkdir -p -- "$fixture/bin" "$fixture/home"
export MUXLER_CLOSEOUT_LOG="$fixture/closeout.log"
export MUXLER_TEST_HELPER_LOG="$fixture/helper.log"
export MUXLER_REMOTE_MANIFEST=.muxler_closeout

tmux() { /opt/homebrew/bin/tmux -L "$socket" "$@"; }

# Mocks for the closeout helper.
cat > "$fixture/bin/osascript" <<'EOF'
#!/bin/sh
cat -- "$1" >> "$MUXLER_TEST_OSA_LOG"
EOF
cat > "$fixture/bin/tmux" <<'EOF'
#!/bin/sh
cmd=${1:-}; shift || true
target=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -t ]; then shift; target=${1:-}; fi
  shift
done
case $cmd in
  has-session) exit 1 ;;
  display-message) exit 0 ;;
esac
exit 1
EOF
chmod +x "$fixture/bin/"*
export PATH="$fixture/bin:$PATH"
export MUXLER_TEST_OSA_LOG="$fixture/osa.log"

fail() { print -u2 -- "$1"; exit 1; }

source "$root/.tmux_session.shared.sh"

run_local_case() {
  local label=$1 file=$2 json=$3 expect_invoke=$4
  if [[ -n $json ]]; then printf '%s\n' "$json" > "$file"; else rm -f -- "$file"; fi
  export MUXLER_CONFIG="$file"
  : > "$MUXLER_TEST_HELPER_LOG"
  id=$(tmux_session_prepare "$PWD" "cfg_${label}" 'bg=#354f75,fg=white' nvim)
  tmux set-option -t "$id" @workspace_local_group local-blue
  tmux set-option -t "$id" @workspace_local_name "cfg_${label}"
  tmux set-option -t "$id" @workspace_iterm_tty /dev/ttys012
  p=$(tmux list-panes -t "$id" -F '#{pane_id}')
  TMUX=isolated TMUX_PANE="$p" kill-session || fail "kill failed for $label"
  [[ -z $(tmux_session_id "cfg_${label}" 2>/dev/null) ]] || fail "kill did not remove session for $label"
  if [[ $expect_invoke == invoke ]]; then
    [[ -s "$MUXLER_TEST_HELPER_LOG" ]] || fail "closeout not invoked for $label"
  else
    [[ ! -s "$MUXLER_TEST_HELPER_LOG" ]] || fail "closeout invoked for $label"
  fi
}

# Local explicit false gate: no manifest/helper invocation, but kills still happen.
export MUXLER_CONFIG="$fixture/false.json"
printf '{ "close_tabs_on_kill_session": false }\n' > "$fixture/false.json"
helper="$fixture/helper-false.sh"
cat > "$helper" <<'EOF'
#!/bin/sh
printf 'called\n' >> "$MUXLER_TEST_HELPER_LOG"
exit 0
EOF
chmod +x "$helper"
export MUXLER_CLOSEOUT_SCRIPT="$helper"
: > "$MUXLER_TEST_HELPER_LOG"

id1=$(tmux_session_prepare "$PWD" "cfg_false_one" 'bg=#354f75,fg=white' nvim)
id2=$(tmux_session_prepare "$PWD" "cfg_false_two" 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$id1" @workspace_local_group local-blue
tmux set-option -t "$id1" @workspace_local_name cfg_false_one
tmux set-option -t "$id1" @workspace_iterm_tty /dev/ttys010
tmux set-option -t "$id2" @workspace_local_group local-blue
tmux set-option -t "$id2" @workspace_local_name cfg_false_two
tmux set-option -t "$id2" @workspace_iterm_tty /dev/ttys011
pane=$(tmux list-panes -t "$id2" -F '#{pane_id}')
TMUX=isolated TMUX_PANE="$pane" kill-session || fail 'local false kill-session failed'
[[ -z $(tmux_session_id cfg_false_one 2>/dev/null) && -z $(tmux_session_id cfg_false_two 2>/dev/null) ]] || fail 'false config skipped kills'
[[ ! -s "$MUXLER_TEST_HELPER_LOG" ]] || fail 'false config invoked closeout helper'

# Explicit true invokes; missing/invalid/type default false and do not invoke.
run_local_case "true" "$fixture/true.json" '{ "close_tabs_on_kill_session": true }' invoke
run_local_case "missing" "$fixture/missing.json" "" noinvoke
run_local_case "key" "$fixture/key.json" '{ "unrelated": 1 }' noinvoke
run_local_case "bad" "$fixture/bad.json" '{ bad json' noinvoke
run_local_case "type" "$fixture/type.json" '{ "close_tabs_on_kill_session": 7 }' noinvoke

# Parser unavailable defaults false (local gate).
printf '{ "close_tabs_on_kill_session": true }\n' > "$fixture/parser.json"
export MUXLER_CONFIG="$fixture/parser.json"
: > "$MUXLER_TEST_HELPER_LOG"
id=$(tmux_session_prepare "$PWD" "cfg_parser" 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$id" @workspace_local_group local-blue
tmux set-option -t "$id" @workspace_local_name cfg_parser
tmux set-option -t "$id" @workspace_iterm_tty /dev/ttys013
p=$(tmux list-panes -t "$id" -F '#{pane_id}')
if PATH= TMUX=isolated TMUX_PANE="$p" kill-session; then :; else fail 'parser-unavailable kill failed'; fi
[[ ! -s "$MUXLER_TEST_HELPER_LOG" ]] || fail 'parser-unavailable invoked closeout helper'

# Direct default checks.
[[ $(MUXLER_CONFIG="$fixture/missing.json" muxler_config_close_tabs_value "$fixture/missing.json") == false ]] || fail 'missing file did not default false'
[[ $(printf '{ "unrelated": 1 }\n' > "$fixture/key2.json"; MUXLER_CONFIG="$fixture/key2.json" muxler_config_close_tabs_value "$fixture/key2.json") == false ]] || fail 'missing key did not default false'
[[ $(printf '{ "close_tabs_on_kill_session": true }\n' > "$fixture/t.json"; MUXLER_CONFIG="$fixture/t.json" muxler_config_close_tabs_value "$fixture/t.json") == true ]] || fail 'explicit true not preserved'
[[ $(printf '{ "close_tabs_on_kill_session": false }\n' > "$fixture/f.json"; MUXLER_CONFIG="$fixture/f.json" muxler_config_close_tabs_value "$fixture/f.json") == false ]] || fail 'explicit false not preserved'

# Helper false config prevents osascript.
export MUXLER_CONFIG="$fixture/helper-false.json"
printf '{ "close_tabs_on_kill_session": false }\n' > "$fixture/helper-false.json"
printf '1700000000\tlocal-blue\t%s\n' "$PWD" > "$fixture/helper.manifest"
printf '$1\t/dev/ttys020\tsession_helper\n' >> "$fixture/helper.manifest"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper false run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'false helper invoked osascript'

# Helper true config allows closeout.
export MUXLER_CONFIG="$fixture/helper-true.json"
printf '{ "close_tabs_on_kill_session": true }\n' > "$fixture/helper-true.json"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper true run failed'
[[ -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'true helper did not invoke osascript'

# Helper missing file defaults false (no osascript).
export MUXLER_CONFIG="$fixture/helper-missing.json"
rm -f -- "$fixture/helper-missing.json"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper missing run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'missing helper invoked osascript'

# Helper missing key defaults false.
export MUXLER_CONFIG="$fixture/helper-key.json"
printf '{ "unrelated": 1 }\n' > "$fixture/helper-key.json"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper key run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'missing-key helper invoked osascript'

# Helper invalid JSON defaults false.
export MUXLER_CONFIG="$fixture/helper-bad.json"
printf '{ bad json\n' > "$fixture/helper-bad.json"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper bad run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'invalid helper invoked osascript'

# Helper non-boolean defaults false.
export MUXLER_CONFIG="$fixture/helper-type.json"
printf '{ "close_tabs_on_kill_session": 7 }\n' > "$fixture/helper-type.json"
: > "$MUXLER_TEST_OSA_LOG"
zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper type run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'type helper invoked osascript'

# Helper parser unavailable defaults false.
export MUXLER_CONFIG="$fixture/helper-parser.json"
printf '{ "close_tabs_on_kill_session": true }\n' > "$fixture/helper-parser.json"
: > "$MUXLER_TEST_OSA_LOG"
PATH= /bin/zsh "$root/scripts/muxler_close_iterm.sh" local "$fixture/helper.manifest" || fail 'helper parser run failed'
[[ ! -s "$MUXLER_TEST_OSA_LOG" ]] || fail 'parser-unavailable helper invoked osascript'

# Remote writer ignores remote config/Python and still writes a manifest.
unset MUXLER_CLOSEOUT_SCRIPT
unset WORKSPACE_ROOT
export MUXLER_CONFIG="$fixture/remote-false.json"
printf '{ "close_tabs_on_kill_session": false }\n' > "$fixture/remote-false.json"
PATH="/usr/bin:/bin"  # hide python3 if present
remote_id=$(tmux_session_prepare "$PWD" "remote_cfg" 'bg=#354f75,fg=white' nvim)
tmux set-option -t "$remote_id" @workspace_remote_group remote-cyan
tmux set-option -t "$remote_id" @workspace_remote_name remote_cfg
tmux set-option -t "$remote_id" @workspace_iterm_tty /dev/ttys030
tmux set-option -t "$remote_id" @workspace_iterm_token remoteTokenCfg
tmux set-option -t "$remote_id" @workspace_closeout_manifest .muxler_closeout
remote_pane=$(tmux list-panes -t "$remote_id" -F '#{pane_id}')
HOME="$fixture/home" TMUX=isolated TMUX_PANE="$remote_pane" kill-session
[[ -r "$fixture/home/.muxler_closeout.remoteTokenCfg" ]] || fail 'remote writer did not write manifest'
[[ $(<"$fixture/home/.muxler_closeout.remoteTokenCfg") == *'/dev/ttys030'* ]] || fail 'remote manifest lacks tty'

# Shell syntax compatibility.
bash -n "$root/.tmux_session.shared.sh" || fail 'shared bash syntax'
sh -n "$root/.tmux_session.shared.sh" || fail 'shared sh syntax'

print 'config toggle tests passed'
