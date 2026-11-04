tmux_remote_project() {
  local tabcount=${8:-${#WORKSPACE_TABS}}
  tmux_remote_tabs "$tabcount" "${@:1:7}"
}
WORKSPACE_REMOTE_GROUPS_SCRIPT=${${(%):-%x}:A:h}/scripts/tmux_remote_groups.sh

# The kill menu lists literal Host aliases from this repo's SSH config.
WORKSPACE_REMOTE_HOSTS_CONFIG=${${(%):-%x}:A:h}/ssh/config

tmux_remote_hosts() {
  local line host
  local -a fields=() hosts=()
  local -A seen=()
  [[ -r $WORKSPACE_REMOTE_HOSTS_CONFIG ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%\#*}
    fields=(${=line})
    [[ ${(L)fields[1]-} == host ]] || continue
    for host in ${fields[@]:1}; do
      [[ $host != *[\*\?\!]* && -z ${seen[$host]:-} ]] || continue
      seen[$host]=1
      hosts+=("$host")
    done
  done < "$WORKSPACE_REMOTE_HOSTS_CONFIG"
  for host in ${(o)hosts}; do
    print -r -- "$host"
  done
}

tmux_remote_directory() {
  local directory=$1 host=$2 base_path=$3 iterm_color=$4 command_name=$5
  local session_namespace=${6:-}
  local tabcount=${7:-${#WORKSPACE_TABS}}
  if [[ "$directory" == . ]]; then
    local root_name=${base_path##*/}
    local session_key=$root_name
    if [[ "$root_name" == '$HOME' ]]; then
      root_name=home
      session_key=main
    fi
    [[ -n "$session_namespace" ]] && session_key='%2E'
    tmux_remote_project "$host" "$base_path" "$root_name" "$iterm_color" white "${session_namespace}${session_key}" "$command_name" "$tabcount"
    return
  fi
  if [[ -z "$directory" || "$directory" == /* || "$directory" == */ ||
        "$directory" == *//* || "$directory" == .. || "$directory" == ../* ||
        "$directory" == */../* || "$directory" == */.. || "$directory" == ./* ||
        "$directory" == */./* || "$directory" == */. ]]; then
    echo "usage: $command_name <relative-directory|.>"
    return 1
  fi

  # Escape percent first so nested paths cannot collide with literal directory names.
  local session_key=${directory//\%/%25}
  session_key=${session_key//\//%2F}
  tmux_remote_project "$host" "$base_path/$directory" "$directory" "$iterm_color" white "${session_namespace}${session_key}" "$command_name" "$tabcount"
}

kill-remote-tmux() {
  local host choice line id group dir name key selected i listing command
  local host_list
  host_list=$(tmux_remote_hosts) || return 1
  local -a hosts=(${(f)host_list}) keys=() paths=() labels=() group_hosts=()
  local -A counts=() ids=()
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
  read -r 'choice?Index to kill (blank cancels): ' || return 0
  [[ -z $choice ]] && return 0
  if [[ $choice != <-> || $choice == 0 || $choice -gt ${#keys} ]]; then
    print -u2 'Invalid selection.'
    return 1
  fi
  selected=$keys[choice]
  command="sh -s -- kill ${(qq)labels[choice]} ${(qq)paths[choice]}"
  for id in ${=ids[$selected]}; do command+=" ${(qq)id}"; done
  ssh "$group_hosts[choice]" "$command" < "$WORKSPACE_REMOTE_GROUPS_SCRIPT"
}
