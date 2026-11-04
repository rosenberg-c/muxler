#!/usr/bin/env zsh
set -eu

root=${0:A:h:h}
socket="workspace-config-$$-$RANDOM"
tmux() { command tmux -L "$socket" "$@"; }
trap 'tmux kill-server 2>/dev/null || true' EXIT
tmux -f "$root/.tmux.conf" new-session -d -s config

fail() { print -u2 -- "$1"; exit 1; }
[[ $(tmux show-options -gwv mode-keys) == vi ]] || fail 'vi copy mode'
[[ $(tmux show-options -gv set-clipboard) == on ]] || fail 'clipboard'
[[ $(tmux show-options -gv extended-keys) == always ]] || fail 'extended keys'
[[ $(tmux show-options -gv extended-keys-format) == csi-u ]] || fail 'extended key format'
[[ $(tmux show-options -gv allow-passthrough) == on ]] || fail 'OSC passthrough'
[[ $(tmux show-options -gv terminal-features) == *'*:clipboard'* && $(tmux show-options -gv terminal-features) == *'*:extkeys'* ]] || fail 'terminal features'

root_keys=$(tmux list-keys -T root)
copy_keys=$(tmux list-keys -T copy-mode-vi)
for key in h j k l; do
  [[ $root_keys == *"C-$key"*'if-shell'* ]] || fail "root navigation C-$key"
  [[ $copy_keys == *"C-$key"*'select-pane'* ]] || fail "copy navigation C-$key"
done
[[ $copy_keys == *'C-\\'*'select-pane -l'* ]] || fail 'copy previous pane'
[[ $root_keys == *'C-\\'*'if-shell'*'send-keys C-\\'*'select-pane -l'* ]] || fail 'root previous pane'
[[ $copy_keys == *' y '*'copy-selection'* ]] || fail 'copy selection'
print 'tmux config test passed'
