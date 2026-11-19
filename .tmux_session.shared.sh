# Shared Bash/Zsh prompt setup. No input is sent to tmux panes.
# Keep this file sourceable by sh during remote setup; pane shells use Bash/Zsh.
tmux_kill_session_matches() {
  local id=$1 group_option=$2 name_option=$3 group=$4 dir=$5 name marked_name
  [ "$(tmux show-option -qv -t "$id" "$group_option")" = "$group" ] || return 1
  [ "$(tmux show-option -qv -t "$id" @session_target_dir)" = "$dir" ] || return 1
  name=$(tmux display-message -p -t "$id" '#{session_name}') || return 1
  marked_name=$(tmux show-option -qv -t "$id" "$name_option") || return 1
  [ -n "$marked_name" ] && [ "$name" = "$marked_name" ]
}

tmux_valid_closeout_tty() {
  case $1 in
    /dev/ttys*) case ${1#/dev/ttys} in ''|*[!0-9]*) return 1 ;; esac ;;
    *) return 1 ;;
  esac
  return 0
}

tmux_valid_closeout_token() {
  case $1 in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

tmux_valid_closeout_manifest() {
  case $1 in ''|.|..|[!A-Za-z0-9.]*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}

# Record exactly which panes this kill-session invocation intends to close.
# The manifest is written before any kill and only includes sessions with a
# tty recorded at launch. All failures are swallowed: a missing manifest means
# "no cleanup", never "skip the kill". Remote manifests are named per attached
# pane token, so overlapping kills cannot overwrite each other.
tmux_kill_session_prepare_closeout() {
  local kind=$1 group=$2 dir=$3 id tty name tmp ids_tmp rows_tmp token manifest target count=0
  [ "$kind" = local ] || [ "$kind" = remote ] || return 0
  ids_tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-ids.XXXXXX" 2>/dev/null) || return 0
  cat > "$ids_tmp" 2>/dev/null || { rm -f -- "$ids_tmp"; return 0; }

  if [ "$kind" = local ]; then
    tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-closeout.XXXXXX" 2>/dev/null) || {
      rm -f -- "$ids_tmp"
      return 0
    }
    if ! printf '%s\t%s\t%s\n' "$(date +%s)" "$group" "$dir" > "$tmp" 2>/dev/null; then
      rm -f -- "$tmp" "$ids_tmp"
      return 0
    fi
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      tty=$(tmux show-option -qv -t "$id" @workspace_iterm_tty 2>/dev/null) || tty=''
      tmux_valid_closeout_tty "$tty" || continue
      name=$(tmux display-message -p -t "$id" '#{session_name}' 2>/dev/null) || continue
      [ -n "$name" ] || continue
      if ! printf '%s\t%s\t%s\n' "$id" "$tty" "$name" >> "$tmp" 2>/dev/null; then
        rm -f -- "$tmp" "$ids_tmp"
        return 0
      fi
      count=$((count + 1))
    done < "$ids_tmp"
    rm -f -- "$ids_tmp"
    if [ "$count" -gt 0 ]; then
      # Detached: the pane running this function dies with the current session.
      ( nohup zsh "$MUXLER_CLOSEOUT_SCRIPT" local "$tmp" </dev/null >/dev/null 2>&1 & ) 2>/dev/null || :
    else
      rm -f -- "$tmp"
    fi
    return 0
  fi

  rows_tmp=$(mktemp "${TMPDIR:-/tmp}/muxler-rows.XXXXXX" 2>/dev/null) || {
    rm -f -- "$ids_tmp"
    return 0
  }
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    tty=$(tmux show-option -qv -t "$id" @workspace_iterm_tty 2>/dev/null) || tty=''
    tmux_valid_closeout_tty "$tty" || continue
    name=$(tmux display-message -p -t "$id" '#{session_name}' 2>/dev/null) || continue
    [ -n "$name" ] || continue
    if ! printf '%s\t%s\t%s\n' "$id" "$tty" "$name" >> "$rows_tmp" 2>/dev/null; then
      rm -f -- "$rows_tmp" "$ids_tmp"
      return 0
    fi
    count=$((count + 1))
  done < "$ids_tmp"
  if [ "$count" -eq 0 ]; then
    rm -f -- "$rows_tmp" "$ids_tmp"
    return 0
  fi

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    token=$(tmux show-option -qv -t "$id" @workspace_iterm_token 2>/dev/null) || token=''
    manifest=$(tmux show-option -qv -t "$id" @workspace_closeout_manifest 2>/dev/null) || manifest=''
    [ -n "$manifest" ] || manifest=${MUXLER_REMOTE_MANIFEST:-.muxler_closeout}
    tmux_valid_closeout_token "$token" || continue
    tmux_valid_closeout_manifest "$manifest" || continue
    tmp=$(mktemp "$HOME/.${manifest#.}.XXXXXX" 2>/dev/null) || continue
    target="$HOME/$manifest.$token"
    if printf '%s\t%s\t%s\t%s\n' "$(date +%s)" "$token" "$group" "$dir" > "$tmp" 2>/dev/null &&
       cat -- "$rows_tmp" >> "$tmp" 2>/dev/null; then
      mv -f -- "$tmp" "$target" 2>/dev/null || rm -f -- "$tmp"
    else
      rm -f -- "$tmp"
    fi
  done < "$ids_tmp"
  rm -f -- "$rows_tmp" "$ids_tmp"
  return 0
}

tmux_kill_session() {
  if [ "$#" -ne 0 ] || [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
    printf '%s\n' 'usage: kill-session (from inside tmux)' >&2
    return 1
  fi
  local current_id group_option name_option group dir ids id selected
  current_id=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}') || return 1
  [ -n "$current_id" ] || return 1
  group_option=@workspace_local_group name_option=@workspace_local_name
  group=$(tmux show-option -qv -t "$current_id" "$group_option") || return 1
  if [ -z "$group" ]; then
    group_option=@workspace_remote_group name_option=@workspace_remote_name
    group=$(tmux show-option -qv -t "$current_id" "$group_option") || return 1
  fi
  dir=$(tmux show-option -qv -t "$current_id" @session_target_dir) || return 1
  if [ -z "$group" ] || [ -z "$dir" ] || ! tmux_kill_session_matches "$current_id" "$group_option" "$name_option" "$group" "$dir"; then
    # Singleton fallback: only a recorded muxler tty makes closeout safe. A
    # remote fallback also needs its attachment token; the writer validates
    # both and skips unmarked sessions that never came from muxler.
    if [ -n "${MUXLER_CLOSEOUT_SCRIPT:-}" ] && [ -r "$MUXLER_CLOSEOUT_SCRIPT" ]; then
      tmux_kill_session_prepare_closeout local '' '' <<EOF
$current_id
EOF
    else
      tmux_kill_session_prepare_closeout remote '' '' <<EOF
$current_id
EOF
    fi
    tmux kill-session -t "$current_id"
    return $?
  fi
  ids=$(tmux list-sessions -F '#{session_id}') || return 1
  selected=$current_id
  while IFS= read -r id; do
    [ -n "$id" ] && [ "$id" != "$current_id" ] || continue
    tmux_kill_session_matches "$id" "$group_option" "$name_option" "$group" "$dir" || continue
    selected=$(printf '%s\n%s' "$selected" "$id")
  done <<EOF
$ids
EOF
  if [ -n "${MUXLER_CLOSEOUT_SCRIPT:-}" ] && [ -r "$MUXLER_CLOSEOUT_SCRIPT" ]; then
    tmux_kill_session_prepare_closeout local "$group" "$dir" <<EOF
$selected
EOF
  elif [ "$group_option" = @workspace_remote_group ]; then
    tmux_kill_session_prepare_closeout remote "$group" "$dir" <<EOF
$selected
EOF
  fi
  while IFS= read -r id; do
    [ -n "$id" ] && [ "$id" != "$current_id" ] || continue
    tmux_kill_session_matches "$id" "$group_option" "$name_option" "$group" "$dir" || continue
    tmux kill-session -t "$id" || return 1
  done <<EOF
$ids
EOF
  tmux_kill_session_matches "$current_id" "$group_option" "$name_option" "$group" "$dir" || return 1
  tmux kill-session -t "$current_id"
}
if [ -n "${ZSH_VERSION:-}" ] || { [ -n "${BASH_VERSION:-}" ] && ! shopt -oq posix; }; then
  eval 'kill-session() { tmux_kill_session "$@"; }'
fi

# Set the iTerm title for a managed session without renaming tmux sessions or windows.
# Options are set per session so global tmux defaults and other sessions are untouched.
tmux_session_set_title() {
  [ "$#" -eq 3 ] || return 0
  local session_id=$1 title_prefix=$2 title_label=$3 title
  [ -n "$session_id" ] && [ -n "$title_prefix" ] || return 0
  title=$(printf '%s-%s\n' "$title_prefix" "$title_label" | tr '[:lower:]' '[:upper:]') || return 1
  tmux set-option -t "$session_id" @workspace_title "$title" || return 1
  tmux set-option -t "$session_id" set-titles on || return 1
  tmux set-option -t "$session_id" set-titles-string '#{?@workspace_title,#{@workspace_title},#S}'
}

# Find a session by its exact name, including names containing colons.
tmux_session_id() {
  local session_name=$1 session_info
  # Resolve literal names, including colons, without tmux's target syntax.
  tmux list-sessions -F '#{session_id} #{session_name}' | while IFS= read -r session_info; do
    if [ "${session_info#* }" = "$session_name" ]; then
      printf '%s\n' "${session_info%% *}"
      break
    fi
  done
}

# Apply the prepared directory and status style once when a pane's shell prompts.
tmux_session_prompt_setup() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  local setup_id target_dir status_style
  setup_id=$(tmux show-option -qv -t "$TMUX_PANE" @session_setup_id) || return 0
  [ -n "$setup_id" ] && [ "$setup_id" != "${_tmux_session_setup_id:-}" ] || return 0
  target_dir=$(tmux show-option -qv -t "$TMUX_PANE" @session_target_dir) || return 0
  status_style=$(tmux show-option -qv -t "$TMUX_PANE" @session_status_style) || return 0
  [ -d "$target_dir" ] || return 0

  if [ "$(pwd -P)" != "$target_dir" ]; then
    cd -- "$target_dir" || return 0
  fi
  if [ -n "$status_style" ]; then
    tmux set-option -t "$TMUX_PANE" status-style "$status_style" || return 0
  fi
  _tmux_session_setup_id=$setup_id
}

# Reuse or create a session, then store its pane setup options.
tmux_session_prepare() {
  local target_dir=$1 session_name=$2 status_style=${3:-} window_name=${4:-main}
  local session_id
  case "$target_dir" in
    '$HOME'|'~') target_dir=$HOME ;;
    '$HOME/'*) target_dir="$HOME/${target_dir#\$HOME/}" ;;
    '~/'*) target_dir="$HOME/${target_dir#\~/}" ;;
  esac
  target_dir=$(CDPATH= cd -- "$target_dir" && pwd -P) || return
  [ -n "$session_name" ] || return 1

  session_id=$(tmux_session_id "$session_name" 2>/dev/null) || return
  if [ -z "$session_id" ]; then
    if ! session_id=$(tmux new-session -d -P -F '#{session_id}' -s "$session_name" -n "$window_name" -c "$target_dir" 2>&1); then
      local creation_error=$session_id
      session_id=$(tmux_session_id "$session_name" 2>/dev/null) || return
      if [ -z "$session_id" ]; then
        printf '%s\n' "$creation_error" >&2
        return 1
      fi
    fi
  fi
  [ -n "$session_id" ] || return 1
  if [ -n "$status_style" ]; then
    tmux set-option -t "$session_id" @session_target_dir "$target_dir" || return
    tmux set-option -t "$session_id" @session_status_style "$status_style" || return
    tmux set-option -t "$session_id" @session_setup_id "$$-$(date +%s)-${RANDOM:-0}-$session_id" || return
    tmux set-option -t "$session_id" status-style "$status_style" || return
  fi
  printf '%s\n' "$session_id"
}

# Add the remote hook to Bash and Zsh startup files if not already present.
tmux_session_install() {
  local startup source_line='[ ! -r "$HOME/.tmux_session.shared.sh" ] || . "$HOME/.tmux_session.shared.sh"'
  for startup in "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc"; do
    if ! grep -Fqx -- "$source_line" "$startup" 2>/dev/null; then
      printf '\n%s\n' "$source_line" >> "$startup" || return
    fi
  done
}

# Run pane setup from the prompt hook of whichever shell sources this file.
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd tmux_session_prompt_setup
elif [ -n "${BASH_VERSION:-}" ]; then
  case "$(declare -p PROMPT_COMMAND 2>/dev/null)" in
    'declare -a '*)
      case ";${PROMPT_COMMAND[*]};" in
        *tmux_session_prompt_setup*) ;;
        *) eval 'PROMPT_COMMAND+=(tmux_session_prompt_setup)' ;;
      esac ;;
    *)
      case ";${PROMPT_COMMAND:-};" in
        *tmux_session_prompt_setup*) ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND
}tmux_session_prompt_setup" ;;
      esac ;;
  esac
fi
