# Kill menus and remote script

`kill-local-tmux` and `kill-remote-tmux` close a selected group of sessions
marked by the color shortcuts; unmarked tmux sessions are excluded.

## Local groups

`.tmux_session.local.sh` groups marked sessions by shortcut and directory and
checks their names before listing them. It kills only the selected IDs, with
the current session last. A blank choice cancels.

## One remote menu across hosts

`.tmux_session.remote.sh` queries every literal `Host` alias in `ssh/config`.
Entries begin with the hostname and are grouped by host, group, and directory;
you select a group without choosing a host first. Each host is queried with:

```sh
ssh "$host" 'sh -s -- list' < "$WORKSPACE_REMOTE_GROUPS_SCRIPT"
```

`WORKSPACE_REMOTE_GROUPS_SCRIPT` points to local
`scripts/tmux_remote_groups.sh`. Its `list` mode returns only sessions with
matching remote group, directory, and managed-name markers.

After selection, the same script runs in `kill` mode on **only that host**.
Before each kill it rechecks the session's group, directory, and name marker;
if a session changed or vanished, it stops.

### Why stream this script instead of using the installed shared file?

It only runs during the menu request, so streaming it uses the current local
version without installing it on each host. This is a design choice, not a tmux
requirement. The shared file *is* installed for future pane shells; see
[Session lifecycle](session-lifecycle.md#why-install-the-shared-file-remotely).

An SSH listing failure aborts the menu rather than showing a partial list.
Blank cancels; an invalid index is rejected.
