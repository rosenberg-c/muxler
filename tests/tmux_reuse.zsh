#!/usr/bin/env zsh
set -eu

source "${0:A:h:h}/.tmux_session.shared.sh"
socket="workspace-reuse-$$-$RANDOM"
tmux() { command tmux -L "$socket" "$@"; }
trap 'tmux kill-server 2>/dev/null || true' EXIT

session_id=$(tmux_session_prepare "$PWD" reused_nvim 'bg=#354f75,fg=white' nvim)
[[ $(tmux show-option -v -t "$session_id" status-style) == 'bg=#354f75,fg=white' ]] || exit 1
reused_id=$(tmux_session_prepare "$PWD" reused_nvim 'bg=#3b6f4a,fg=white' nvim)
[[ $reused_id == "$session_id" ]] || { print -u2 'Did not reuse the session'; exit 1; }
[[ $(tmux show-option -v -t "$session_id" status-style) == 'bg=#3b6f4a,fg=white' ]] || {
  print -u2 'Reused session kept the old status color'
  exit 1
}

pane=$(tmux display-message -p -t "$session_id" '#{pane_id}')
tmux set-option -t "$pane" status-style 'bg=#354f75,fg=white'
TMUX=test TMUX_PANE=$pane tmux_session_prompt_setup
[[ $(tmux show-option -v -t "$pane" status-style) == 'bg=#3b6f4a,fg=white' ]] || {
  print -u2 'Prompt setup kept the old status color in the same directory'
  exit 1
}
print 'tmux reuse color test passed'
