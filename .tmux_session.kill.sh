# Select a managed local shortcut and directory; never target unmarked sessions.
tmux_kill_local() {
  local id group dir name marked_name key choice selected current_id
  local -a keys=() paths=() labels=() selected_ids=()
  local -A counts=() ids=()
  local i
  local -a active_ids=()
  while true; do
    keys=() paths=() labels=() selected_ids=()
    counts=() ids=()
    active_ids=(${(f)"$(tmux list-sessions -F '#{session_id}' 2>/dev/null)"})
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
    for (( i = 1; i <= ${#keys}; i++ )); do
      print -r -- "$i) $labels[i]  $paths[i]  (${counts[$keys[i]]} sessions)"
    done
    while true; do
      read -r 'choice?Index to kill (blank cancels): ' || return 0
      [[ -z $choice ]] && return 0
      [[ $choice == <-> && $choice != 0 && $choice -le ${#keys} ]] && break
      print -u2 'Invalid selection.'
    done
    selected=$keys[choice]
    selected_ids=(${=ids[$selected]})
    current_id=${TMUX:+$(tmux display-message -p '#{session_id}' 2>/dev/null)}
    for id in "${selected_ids[@]}"; do
      [[ $id == "$current_id" ]] && continue
      tmux kill-session -t "$id" || return
    done
    if [[ -n $current_id && " ${selected_ids[*]} " == *" $current_id "* ]]; then
      tmux kill-session -t "$current_id" || return
    fi
  done
}

tmux_kill_remote() {
  local host choice line id group dir name key selected i listing command
  local host_list
  local -a hosts=() keys=() paths=() labels=() group_hosts=()
  local -A counts=() ids=()
  while true; do
    host_list=$(tmux_remote_hosts) || return 1
    hosts=(${(f)host_list}) keys=() paths=() labels=() group_hosts=()
    counts=() ids=()
    if (( ! ${#hosts} )); then
      print 'No remote hosts are configured.'
      return 0
    fi
    for host in "${hosts[@]}"; do
      listing=$(ssh "$host" 'sh -s -- list' < "$WORKSPACE_REMOTE_GROUPS_SCRIPT") || return
      for line in ${(f)listing}; do
        IFS=$'\t' read -r id name group dir <<< "$line"
        [[ -n $id && -n $name && -n $group && -n $dir ]] || continue
        key="$host"$'\t'"$group"$'\t'"$dir"
        if [[ -z ${counts[$key]:-} ]]; then
          keys+=("$key") group_hosts+=("$host") paths+=("$dir") labels+=("$group")
          counts[$key]=0
        fi
        (( counts[$key] += 1 ))
        ids[$key]+=" $id"
      done
    done
    if (( ! ${#keys} )); then
      print 'No managed remote sessions are active.'
      return 0
    fi
    for (( i = 1; i <= ${#keys}; i++ )); do
      print -r -- "$i) $group_hosts[i]  $labels[i]  $paths[i]  (${counts[$keys[i]]} sessions)"
    done
    while true; do
      read -r 'choice?Index to kill (blank cancels): ' || return 0
      [[ -z $choice ]] && return 0
      [[ $choice == <-> && $choice != 0 && $choice -le ${#keys} ]] && break
      print -u2 'Invalid selection.'
    done
    selected=$keys[choice]
    command="sh -s -- kill ${(qq)labels[choice]} ${(qq)paths[choice]}"
    for id in ${=ids[$selected]}; do command+=" ${(qq)id}"; done
    ssh "$group_hosts[choice]" "$command" < "$WORKSPACE_REMOTE_GROUPS_SCRIPT" || return
  done
}

kill-muxler() {
  if (( $# != 1 )); then
    print -u2 'usage: kill-muxler --local|--remote'
    return 1
  fi
  case $1 in
    --local) tmux_kill_local ;;
    --remote) tmux_kill_remote ;;
    *) print -u2 'usage: kill-muxler --local|--remote'; return 1 ;;
  esac
}

kill-local() { kill-muxler --local "$@"; }
kill-remote() { kill-muxler --remote "$@"; }
