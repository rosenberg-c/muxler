#!/usr/bin/env zsh
set -eu

source "${0:A:h:h}/.zsh_session"
source "${0:A:h}/config.zsh"
WORKSPACE_TEST_HOST=debian-dev
socket="workspace-remote-kill-$$-$RANDOM"
other_socket="workspace-remote-kill-other-$$-$RANDOM"
stub_dir=$(mktemp -d)
tmux_bin=$(whence -p tmux)
trap '"$tmux_bin" -L "$socket" kill-server 2>/dev/null || true; "$tmux_bin" -L "$other_socket" kill-server 2>/dev/null || true; rm -rf -- "$stub_dir"' EXIT
cat > "$stub_dir/tmux" <<EOF
#!/bin/sh
exec '$tmux_bin' -L "\${TMUX_TEST_SOCKET:-$socket}" "\$@"
EOF
chmod +x "$stub_dir/tmux"
export PATH="$stub_dir:$PATH"
tmux() { "$tmux_bin" -L "${TMUX_TEST_SOCKET:-$socket}" "$@"; }
ssh() {
  local host=$1
  [[ $host == $WORKSPACE_TEST_HOST || $host == debian-new ]] || return 1
  shift
  ( export TMUX_TEST_SOCKET=$([[ $host == debian-new ]] && print -r -- "$other_socket" || print -r -- "$socket"); eval "$1" )
}

make_remote() {
  local group=$1 dir=$2 name=$3 id
  id=$(tmux_session_prepare "$dir" "$name" 'bg=#354f75,fg=white' nvim)
  tmux set-option -t "$id" @workspace_remote_group "$group"
  tmux set-option -t "$id" @workspace_remote_name "$name"
  print -r -- "$id"
}

blue=$(make_remote remote-cyan "$PWD" cyan_sample_nvim)
second=$(make_remote remote-cyan "$PWD" cyan_sample_notes)
green=$(make_remote remote-green "$PWD" green_sample_nvim)
other=$(TMUX_TEST_SOCKET="$other_socket" make_remote remote-cyan "$PWD" other_cyan_nvim)
unmarked=$(tmux_session_prepare "$PWD" magenta_old_nvim 'bg=#354f75,fg=white' nvim)
unrelated=$(tmux_session_prepare "$PWD" unrelated '' main)
tmux set-option -t "$unrelated" @workspace_remote_group remote-cyan

menu=$(kill-remote-tmux <<< '')
[[ $menu == *'debian-dev  remote-cyan'* && $menu == *'debian-new  remote-cyan'* && $menu == *'remote-green'* && $menu == *'(2 sessions)'* ]] || {
  print -u2 -- "Missing remote groups: $menu"
  exit 1
}
[[ $menu != *'magenta_old'* && $menu != *'unrelated'* ]] || exit 1
[[ -n $(tmux display-message -p -t "$blue" '#{session_id}') ]] || exit 1
[[ -n $(tmux_session_id cyan_sample_nvim) && -n $(TMUX_TEST_SOCKET="$other_socket" tmux_session_id other_cyan_nvim) ]] || exit 1
if kill-remote-tmux <<< '99' >/dev/null 2>&1; then
  print -u2 'Invalid group index was accepted'
  exit 1
fi

index=
for line in ${(f)menu}; do
  [[ $line == *'debian-dev  remote-cyan'* ]] && index=${line%%\)*}
done
[[ -n $index ]] || exit 1
kill-remote-tmux <<< "$index" >/dev/null
[[ -z $(tmux_session_id cyan_sample_nvim) && -z $(tmux_session_id cyan_sample_notes) ]] || exit 1
[[ -n $(tmux_session_id green_sample_nvim) && -n $(tmux_session_id magenta_old_nvim) && -n $(tmux_session_id unrelated) ]] || exit 1
[[ -n $(TMUX_TEST_SOCKET="$other_socket" tmux_session_id other_cyan_nvim) ]] || exit 1

if sh "${0:A:h:h}/scripts/tmux_remote_groups.sh" kill remote-green "$PWD" "$unmarked" >/dev/null 2>&1; then
  print -u2 'Unmarked session was killable'
  exit 1
fi
if sh "${0:A:h:h}/scripts/tmux_remote_groups.sh" kill remote-cyan "$PWD" "$green" >/dev/null 2>&1; then
  print -u2 'Session from another group was killable'
  exit 1
fi
print 'isolated remote tmux kill test passed'
