#!/usr/bin/env zsh
set -eu

source "${0:A:h:h}/.zsh_session"
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

  menu=$(kill-local-tmux <<< '')
[[ $menu == *'local-blue'* && $menu == *'local-yellow'* && $menu == *'local-purple'* && $menu == *'local-red'* && $menu == *'(3 sessions)'* ]] || {
  print -u2 'Missing or incorrect menu groups'
  exit 1
}
index=''
for line in ${(f)menu}; do
  [[ $line == *'local-blue'* ]] && index=${line%%\)*}
done
[[ -n $index ]] || exit 1
  if kill-local-tmux <<< '999' >/dev/null 2>&1; then
  print -u2 'Accepted invalid index'
  exit 1
fi
[[ -n $(tmux_session_id "$blue_nvim") ]] || exit 1
  kill-local-tmux <<< "$index" >/dev/null
[[ -z $(tmux_session_id "$blue_nvim") && -z $(tmux_session_id "$blue_notes") && -z $(tmux_session_id "$blue_old") ]] || exit 1
[[ -n $(tmux_session_id "$yellow_nvim") && -n $(tmux_session_id "$purple_nvim") && -n $(tmux_session_id "$red_nvim") && -n $(tmux_session_id "$old_name") && -n $(tmux_session_id unrelated_session) && -n $(tmux_session_id "$mismatch") ]] || {
  print -u2 'Killed unrelated local sessions'
  exit 1
}
print 'isolated local tmux kill test passed'
