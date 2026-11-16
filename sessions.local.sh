local-muxler() {
  cd ~/.config/muxler
  local tabcount=5 split='3,4'; tmux_local_directory local-muxler muted_yellow "${1:-.}" "$tabcount" "$split";
}

local-purple() { 
  local tabcount=9 split='3,4'; tmux_local_directory local-purple muted_purple "${1:-.}" "$tabcount" "$split"; 
}

local-blue() { 
  local tabcount=9 split='3,4'; tmux_local_directory local-blue muted_blue "${1:-.}" "$tabcount" "$split";
}

local-red() { 
  local tabcount=9 split='3,4'; tmux_local_directory local-red muted_red "${1:-.}" "$tabcount" "$split"; 
}

# Define overrides or supplement in user.sessions.local.sh.
if [[ -f "$WORKSPACE_ROOT/user.sessions.local.sh" ]]; then
  . "$WORKSPACE_ROOT/user.sessions.local.sh"
fi
