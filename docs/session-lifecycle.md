# Session lifecycle

## Local shortcut

1. `sessions.local.sh` calls `tmux_local_directory` with a directory, color,
   and tab count. `.tmux_session.local.sh` resolves the path and names the group.
2. `.zsh_session` selects tab names from `WORKSPACE_TABS`, colors them, and opens
   extra iTerm2 tabs; the first session attaches in the current terminal.
3. `tmux_local` uses `tmux_session_prepare` from `.tmux_session.shared.sh` to
   find or create each session. It marks managed sessions with
   `@workspace_local_group` and `@workspace_local_name` for the kill menu.

## Remote shortcut

1. `sessions.remote.sh` chooses the host and base path; `.tmux_session.remote.sh`
   checks the relative path (`.` means the base path) and names the group.
2. `.zsh_session` names the tab sessions. `.zsh_tmux` sends the current
   `.tmux_session.shared.sh` over SSH, installs it as
   `~/.tmux_session.shared.sh`, and sources it. It adds source lines to the
   remote Bash/Zsh startup files and prepares all tab sessions in one SSH call.
   Each is marked with `@workspace_remote_group` and `@workspace_remote_name`.
3. `tmux_connect` attaches each tab over SSH, creating a missing session if
   needed. Extra tabs use new iTerm2 tabs; the first uses the current terminal.

### Why install the shared file remotely?

`tmux_session_prepare` stores the target directory, status style, and setup ID
on each session. At a pane's first prompt, the shared hook reads those options,
changes directory, and applies the style. Remote panes may start **after** the
setup SSH call ends, so their shells must be able to source the installed file.
The next remote shortcut run refreshes that copy.
