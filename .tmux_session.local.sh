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

# Select a managed local shortcut and directory; never target unmarked sessions.
kill-local-tmux() {
  local id group dir name marked_name key choice selected current_id
  local -a keys=() paths=() labels=() selected_ids=()
  local -A counts=() ids=()
  local -a active_ids=(${(f)"$(tmux list-sessions -F '#{session_id}' 2>/dev/null)"})
  for id in "${active_ids[@]}"; do
    group=$(tmux show-option -qv -t "$id" @workspace_local_group) || continue
    [[ -n $group ]] || continue
    dir=$(tmux show-option -qv -t "$id" @session_target_dir) || continue
    [[ -n $dir ]] || continue
    name=$(tmux display-message -p -t "$id" '#{session_name}') || continue
    key=$(tmux_local_project_name "$group" "$dir")
    marked_name=$(tmux show-option -qv -t "$id" @workspace_local_name) || continue
    if [[ -n $marked_name ]]; then
      [[ $name == "$marked_name" && $name == "session_${key}_"?* ]] || continue
    else
      # Older marked sessions have no name marker; keep their namespaced sessions visible.
      [[ $name == "session_${key}_"?* ]] || continue
    fi
    if [[ -z ${counts[$key]:-} ]]; then
      keys+=("$key") paths+=("$dir") labels+=("$group")
      counts[$key]=0
    fi
    (( counts[$key] += 1 ))
    ids[$key]+=" $id"
  done
  if (( ! ${#keys} )); then
    print 'No managed local sessions are active.'
    return 0
  fi
  local i
  for (( i = 1; i <= ${#keys}; i++ )); do
    print -r -- "$i) $labels[i]  $paths[i]  (${counts[$keys[i]]} sessions)"
  done
  read -r 'choice?Index to kill (blank cancels): ' || return 0
  [[ -z $choice ]] && return 0
  if [[ $choice != <-> || $choice == 0 || $choice -gt ${#keys} ]]; then
    print -u2 'Invalid selection.'
    return 1
  fi
  selected=$keys[choice]
  selected_ids=(${=ids[$selected]})
  current_id=${TMUX:+$(tmux display-message -p '#{session_id}' 2>/dev/null)}
  for id in "${selected_ids[@]}"; do
    [[ $id == "$current_id" ]] && continue
    tmux kill-session -t "$id" || return
  done
  if [[ -n $current_id && " ${selected_ids[*]} " == *" $current_id "* ]]; then
    tmux kill-session -t "$current_id"
  fi
}
