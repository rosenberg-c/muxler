#!/bin/sh
set -eu

# Only sessions marked during remote shortcut setup are eligible.
sessions() {
  tmux list-sessions -F '#{session_id}	#{session_name}	#{@workspace_remote_group}	#{@session_target_dir}	#{@workspace_remote_name}' 2>/dev/null || :
}

case ${1:-} in
  list)
    sessions | while IFS="$(printf '\t')" read -r id name group dir marked_name; do
      [ -n "$group" ] && [ -n "$dir" ] && [ -n "$marked_name" ] && [ "$name" = "$marked_name" ] || continue
      case "$id$group$dir$name$marked_name" in
        *"
"*|*"$(printf '\t')"*) continue ;;
      esac
      printf '%s\t%s\t%s\t%s\n' "$id" "$name" "$group" "$dir"
    done
    ;;
  kill)
    [ "$#" -ge 4 ] || exit 1
    group=$2 dir=$3
    shift 3
    for selected_id do
      # Recheck options before each kill in case sessions changed after listing.
      current_group=$(tmux show-option -qv -t "$selected_id" @workspace_remote_group) || exit 1
      current_dir=$(tmux show-option -qv -t "$selected_id" @session_target_dir) || exit 1
      [ "$current_group" = "$group" ] && [ "$current_dir" = "$dir" ] || exit 1
      name=$(tmux display-message -p -t "$selected_id" '#{session_name}') || exit 1
      marked_name=$(tmux show-option -qv -t "$selected_id" @workspace_remote_name) || exit 1
      [ -n "$marked_name" ] && [ "$name" = "$marked_name" ] || exit 1
      tmux kill-session -t "$selected_id" || exit 1
    done
    ;;
  *) exit 1 ;;
esac
