# Shared Bash/Zsh prompt setup. No input is sent to tmux panes.
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
