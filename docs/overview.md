# How Muxler fits together

Each color shortcut opens one tmux session per iTerm2 tab. The first uses the
current terminal; the rest open new tabs. Repeating a shortcut reconnects to
existing sessions.

## Pieces and responsibilities

| File | Responsibility |
| --- | --- |
| `sessions.local.sh`, `sessions.remote.sh` | Shortcut definitions: color, tab count, remote host. Optional `user.sessions.*.sh` files add or override them. |
| `.zsh_session` | Tab names, colors, iTerm2 tabs, and local/remote session orchestration. |
| `.tmux_session.local.sh`, `.tmux_session.remote.sh` | Directory handling and local/remote kill menus. |
| `.zsh_tmux` | Remote setup and SSH attachment. |
| `.tmux_session.shared.sh` | Session creation/reuse and pane prompt setup. |
| `scripts/tmux_remote_groups.sh` | Remote kill-menu listing and validation. |
| `ssh/config` | SSH host aliases for remote shortcuts and the kill menu. |

Source `.zsh_session` and `.zsh_tmux` locally ([setup](../README.md#setup)).
Remote shells only need the installed shared hook, not the local shortcuts.

## Two paths

**Open/reconnect:** a color shortcut prepares sessions, then each tab attaches.
Remote setup and attachment use SSH. See [Session lifecycle](session-lifecycle.md).

**Close a group:** `kill-local-tmux` or `kill-remote-tmux` lists marked sessions
and kills the selected group. See [Kill menus](remote-kill.md).

`.tmux.conf` and optional `.tmux.remote.conf` configure tmux, not session
creation. The remote config is not installed automatically.
