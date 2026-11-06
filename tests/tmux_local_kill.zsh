#!/usr/bin/env zsh
set -eu

source "${0:A:h:h}/.zsh_session"
(( ! $+functions[kill-local-tmux] && ! $+functions[kill-remote-tmux] )) || {
  print -u2 'Legacy kill commands are still defined'
  exit 1
}
WORKSPACE_TABS=(nvim notes)
socket="workspace-local-kill-$$-$RANDOM"
tmux() {
  [[ $1 == attach-session || $1 == switch-client ]] && return 0
  command tmux -L "$socket" "$@"
}
trap 'tmux kill-server 2>/dev/null || true' EXIT

make_group() {
  local group=$1 target_dir=$2 window=$3 key name id
  key=$(tmux_local_project_name "$group" "$target_dir")
  name="session_${key}_${window}"
  id=$(tmux_session_prepare "$target_dir" "$name" 'bg=#354f75,fg=white' "$window")
  tmux set-option -t "$id" @workspace_local_group "$group"
  print -r -- "$name"
}

blue_nvim=$(make_group local-blue "$PWD" nvim)
blue_notes=$(make_group local-blue "$PWD" notes)
blue_old=$(make_group local-blue "$PWD" tab9)
tmux_local "$PWD" "$(tmux_local_project_name local-blue "$PWD")" nvim 'bg=#354f75,fg=white' local-blue >/dev/null
[[ $(tmux show-option -qv -t "$(tmux_session_id "$blue_nvim")" @workspace_local_name) == "$blue_nvim" ]] || {
  print -u2 'Local session name was not marked'
  exit 1
}
yellow_nvim=$(make_group local-yellow "$PWD" nvim)
purple_nvim=$(make_group local-purple "$PWD" nvim)
red_nvim=$(make_group local-red "$PWD" nvim)
old_name=session_${PWD:t}_nvim
tmux_session_prepare "$PWD" "$old_name" 'bg=#5f3030,fg=white' nvim >/dev/null
stranger=$(tmux_session_prepare "$PWD" unrelated_session '' main)
tmux set-option -t "$stranger" @workspace_local_group blue_local
mismatch=$(make_group local-blue "$PWD" bogus)
tmux set-option -t "$(tmux_session_id "$mismatch")" @workspace_local_name session_wrong_nvim

menu=$(kill-muxler --local <<< '')
[[ $(kill-local <<< '') == "$menu" ]] || exit 1
if kill-muxler --invalid <<< '' >/dev/null 2>&1 || kill-muxler <<< '' >/dev/null 2>&1 || kill-muxler --local extra <<< '' >/dev/null 2>&1; then
  print -u2 'Accepted invalid kill-muxler arguments'
  exit 1
fi
[[ $menu == *'local-blue'* && $menu == *'local-yellow'* && $menu == *'local-purple'* && $menu == *'local-red'* && $menu == *'(3 sessions)'* ]] || {
  print -u2 'Missing or incorrect menu groups'
  exit 1
}
index=''
next_index=''
for line in ${(f)menu}; do
  [[ $line == *'local-blue'* ]] && index=${line%%\)*}
  [[ $line == *'local-yellow'* ]] && next_index=${line%%\)*}
done
[[ -n $index && -n $next_index ]] || exit 1
invalid_output=$(kill-muxler --local <<< $'999\n' 2>&1)
[[ $invalid_output == *'Invalid selection.'* && $invalid_output == *'local-blue'* ]] || {
  print -u2 'Invalid index did not re-prompt'
  exit 1
}
[[ -n $(tmux_session_id "$blue_nvim") ]] || exit 1
if (( next_index > index )); then
  (( next_index -= 1 ))
fi
selection_output=$(kill-local <<< "999
$index
$next_index
" 2>&1)
[[ $selection_output == *'Invalid selection.'* ]] || exit 1
[[ -z $(tmux_session_id "$blue_nvim") && -z $(tmux_session_id "$blue_notes") && -z $(tmux_session_id "$blue_old") ]] || exit 1
[[ -z $(tmux_session_id "$yellow_nvim") ]] || exit 1
[[ -n $(tmux_session_id "$purple_nvim") && -n $(tmux_session_id "$red_nvim") && -n $(tmux_session_id "$old_name") && -n $(tmux_session_id unrelated_session) && -n $(tmux_session_id "$mismatch") ]] || {
  print -u2 'Killed unrelated local sessions'
  exit 1
}
two_group_menu=$(kill-muxler --local <<< '')
[[ $two_group_menu == *'(1 sessions)'* && $two_group_menu == *'local-purple'* && $two_group_menu == *'local-red'* ]] || exit 1
for line in ${(f)two_group_menu}; do
  [[ $line == *'local-purple'* ]] && index=${line%%\)*}
done
selection_output=$(kill-muxler --local <<< "3
$index
" 2>&1)
[[ $selection_output == *'Invalid selection.'* ]] || exit 1
[[ -z $(tmux_session_id "$purple_nvim") && -n $(tmux_session_id "$red_nvim") ]] || {
  print -u2 'Invalid selection exited the two-group menu'
  exit 1
}
print 'isolated local tmux kill test passed'
