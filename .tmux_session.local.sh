tmux_local_project_name() {
  local encoded_dir=${2:A}
  encoded_dir=${encoded_dir//\%/%25}
  encoded_dir=${encoded_dir//\//%2F}
  print -r -- "workspace_${1}_${encoded_dir}"
}

tmux_local_directory() {
  local shortcut=$1 color=$2 directory=${3:-.}
  local tabcount=${4:-${#WORKSPACE_TABS}}
  if [[ ! -d "$directory" ]]; then
    print -u2 -- "usage: $shortcut [directory]"
    return 1
  fi
  local target_dir=${directory:A}
  tmux_local_tabs "$target_dir" \
    "$(tmux_local_project_name "$shortcut" "$target_dir")" "$color" \
    "$(tmux_status_bg_color "$color")" white "$shortcut" "$tabcount"
}
