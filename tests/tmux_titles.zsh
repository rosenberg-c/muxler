#!/usr/bin/env zsh
set -eu

root=${0:A:h:h}
source "$root/.zsh_tmux"
source "$root/.tmux_session.shared.sh"

fail() { print -u2 -- "$1"; exit 1; }

fixture=$(mktemp -d)
socket_dir=$fixture/socket
home=$fixture/home
work=$fixture/work/sample
managed_format='#{?@workspace_title,#{@workspace_title},#S}'
mkdir -p -- "$socket_dir" "$home" "$work"
cp -- "$root/.tmux_session.shared.sh" "$home/.tmux_session.shared.sh"

# Isolate a private tmux server via TMUX_TMPDIR so streamed hooks reach it too.
export TMUX_TMPDIR=$socket_dir
unset TMUX
trap 'command tmux kill-server 2>/dev/null || true; rm -rf -- "$fixture"' EXIT
tmux -f /dev/null new-session -d -s boot >/dev/null

# Global defaults deliberately differ from managed titles.
tmux set-option -g set-titles off
tmux set-option -g set-titles-string '#GLOBAL-SENTINEL'
tmux new-session -d -s unrelated
unrelated_titles=$(tmux show-options -pv -t unrelated set-titles)
unrelated_format=$(tmux show-options -pv -t unrelated set-titles-string)

# The helper scopes titles and format to one session only.
tmux new-session -d -s managed -n nvim
tmux_session_set_title managed remote-nvim nvim
[[ $(tmux show-option -qv -t managed @workspace_title) == REMOTE-NVIM-NVIM ]] || fail 'session title option'
[[ $(tmux show-options -pv -t managed set-titles) == on ]] || fail 'per-session set-titles'
[[ $(tmux show-options -pv -t managed set-titles-string) == $managed_format ]] || fail 'per-session title format'
[[ $(tmux display-message -p -t managed "$managed_format") == REMOTE-NVIM-NVIM ]] || fail 'managed title resolves'
[[ $(tmux show-options -gv set-titles) == off ]] || fail 'global set-titles changed by helper'
[[ $(tmux show-options -gv set-titles-string) == '#GLOBAL-SENTINEL' ]] || fail 'global format changed by helper'
[[ $(tmux show-options -pv -t unrelated set-titles) == "$unrelated_titles" ]] || fail 'unrelated session titles changed by helper'
[[ $(tmux show-options -pv -t unrelated set-titles-string) == "$unrelated_format" ]] || fail 'unrelated session format changed by helper'

# The prepare hook sets titles per session, never with -g, and stays valid sh.
ssh() { ssh_argv=$2; ssh_script=$(cat); }
tmux_prepare_remote fixture-host "$work" 'bg=#5f3030,fg=white' remote-magenta remote-magenta magenta_sample_nvim nvim
if [[ $ssh_script == *'set-option -g set-titles'* ]]; then fail 'prepare must not change global tmux title options'; fi
[[ $ssh_script == *'tmux_session_set_title "$session_id" "$title_prefix" "$title_label"'* ]] || fail 'prepare sets title per session'
print -r -- "$ssh_script" | sh -n || fail 'prepare script syntax'

# Executing the streamed hook titles only the managed session.
print -r -- "$ssh_script" > "$fixture/prepare.sh"
prepare_args=( ${(Q)${(z)ssh_argv}} )
HOME=$home sh "$fixture/prepare.sh" "${prepare_args[@]:3}" >/dev/null 2>&1 || true
[[ $(tmux show-option -qv -t magenta_sample_nvim @workspace_title) == REMOTE-MAGENTA-NVIM ]] || fail 'prepared session title'
[[ $(tmux show-options -pv -t magenta_sample_nvim set-titles) == on ]] || fail 'prepared session titles enabled'
[[ $(tmux show-options -pv -t magenta_sample_nvim set-titles-string) == $managed_format ]] || fail 'prepared session title format'
[[ $(tmux show-options -gv set-titles) == off ]] || fail 'prepare changed global set-titles'
[[ $(tmux show-options -gv set-titles-string) == '#GLOBAL-SENTINEL' ]] || fail 'prepare changed global format'
[[ $(tmux show-options -pv -t unrelated set-titles) == "$unrelated_titles" ]] || fail 'prepare changed unrelated session titles'
[[ $(tmux show-options -pv -t unrelated set-titles-string) == "$unrelated_format" ]] || fail 'prepare changed unrelated session format'

# A prepared session still attaches unchanged (standard launcher result).
ssh() { connect_cmd=$3; }
tmux_connect fixture-host magenta_sample_nvim remote-magenta nvim
[[ $connect_cmd == *'exec tmux attach-session -t "$session_id"'* ]] || fail 'connect attaches existing session'
HOME=$home sh -c "$connect_cmd" >/dev/null 2>&1 || true
[[ $(tmux show-option -qv -t magenta_sample_nvim @workspace_title) == REMOTE-MAGENTA-NVIM ]] || fail 'existing prepared title changed'

# A vanished prepared session is recreated with the intended title.
ssh() { connect_cmd=$3; }
tmux_connect fixture-host vanished_nvim remote-magenta nvim
expected_call='tmux_session_set_title "$session_id" '\''remote-magenta'\'' '\''nvim'\'''
[[ $connect_cmd == *"tmux new-session -d -P -F \"#{session_id}\" -s 'vanished_nvim'"* ]] || fail 'connect fallback creates session'
[[ $connect_cmd == *"$expected_call"* ]] || fail 'connect fallback reapplies title'
HOME=$home sh -c "$connect_cmd" >/dev/null 2>&1 || true
[[ $(tmux show-option -qv -t vanished_nvim @workspace_title) == REMOTE-MAGENTA-NVIM ]] || fail 'fallback session title'
[[ $(tmux show-options -pv -t vanished_nvim set-titles) == on ]] || fail 'fallback session titles enabled'
[[ $(tmux show-options -pv -t vanished_nvim set-titles-string) == $managed_format ]] || fail 'fallback session title format'
[[ $(tmux show-options -gv set-titles) == off ]] || fail 'fallback changed global set-titles'

# The remote launcher forwards the title to every connect (main tab and extras).
(
  source "$root/.zsh_session"
  tmux_prepare_remote() { prepare_args=("$@"); }
  tmux_connect() { connect_args=("$@"); }
  tmux_iterm_new_tabs() { shift 2; tab_commands=("$@"); }
  iterm_reset() {}
  iterm_muted_gray() {}
  tmux_remote_tabs 2 debian-dev '$HOME' project muted_gray white sessionkey my-launcher '' my-launcher >/dev/null
  [[ $connect_args[3] == my-launcher && $connect_args[4] == nvim ]] || fail 'connect receives title prefix and label'
  [[ $tab_commands[1] == 'tmux_connect debian-dev sessionkey_'*' my-launcher '* ]] || fail 'extra tab connect receives title prefix and label'
) || fail 'remote tab title propagation'

print 'tmux title tests passed'
