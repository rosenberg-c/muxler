remote-magenta() {
  local host=debian-dev base_path='$HOME' tabcount=9
  tmux_remote_directory "$1" "$host" "$base_path" muted_magenta remote-magenta magenta_ "$tabcount"
}

remote-orange() {
  local host=debian-dev base_path='$HOME' tabcount=9
  tmux_remote_directory "$1" "$host" "$base_path" muted_orange remote-orange orange_ "$tabcount"
}

remote-cyan() {
  local host=debian-dev base_path='$HOME' tabcount=9
  tmux_remote_directory "$1" "$host" "$base_path" muted_cyan remote-cyan cyan_ "$tabcount"
}

remote-green() {
  local host=debian-dev base_path='$HOME' tabcount=9
  tmux_remote_directory "$1" "$host" "$base_path" muted_green remote-green green_ "$tabcount"
}

# Define overrides or supplement in user.sessions.remote.sh.
if [[ -f "$WORKSPACE_ROOT/user.sessions.remote.sh" ]]; then
  . "$WORKSPACE_ROOT/user.sessions.remote.sh"
fi
