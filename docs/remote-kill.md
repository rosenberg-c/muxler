# Kill menus and remote script

`kill-muxler --local` and `kill-muxler --remote` close a selected group of
sessions marked by the color shortcuts; unmarked tmux sessions are excluded.
`kill-local` and `kill-remote` are shortcuts for those modes. These functions
are loaded by `.zsh_session`. From a managed local or remote pane,
`kill-session` closes every marked tab session with the same shortcut group and
directory on that host, with the current session last. It requires no arguments
and reports an error outside tmux. In an unmarked session, it closes only the
current tmux session. Remote pane shells load it from `.tmux_session.shared.sh`;
the next remote shortcut refreshes that file on the host.

## Local groups

`kill-muxler --local` groups marked sessions by shortcut and directory and
checks their names before listing them. It kills only the selected IDs, with
the current session last. After each kill, the menu refreshes so another group
can be selected. An invalid choice shows an error and prompts again; a blank
choice exits.

## One remote menu across hosts

`kill-muxler --remote` queries every literal `Host` alias in `ssh/config`.
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
The menu refreshes across all hosts after each kill. An invalid index shows an
error and prompts again; blank exits.

## iTerm pane closeout

`kill-session` (not the `kill-local`/`kill-remote` menus) also asks iTerm2 to
close the panes belonging to the sessions it just killed. When a shortcut
launches a tab, the pane's outer iTerm tty is stored as `@workspace_iterm_tty`
on its tmux session. Before killing anything, `kill-session` writes a manifest
of the matching sessions and their recorded ttys. The separate closeout helper
(`scripts/muxler_close_iterm.sh`) only closes sessions whose tmux session is
verified gone and whose tty is in that manifest; it never matches by title.

For local sessions the helper is started detached before the kill, because the
pane running `kill-session` dies with its own session. For remote sessions,
`tmux_connect` generates a token for the attachment and stores it with the
manifest basename as `@workspace_iterm_token` and
`@workspace_closeout_manifest`. Each remote manifest is written as
`$HOME/<manifest>.<token>`, so overlapping kills cannot overwrite one another.
When each attached SSH session ends, the local wrapper passes that token back;
the helper re-checks the recent manifest, its token header, and session outcome
over SSH, then consumes the manifest once before closing any panes. An ordinary
detach or SSH disconnect has no manifest for its token and is a no-op.

The singleton fallback also participates: when `kill-session` kills only the
current session because group/name markers are absent, it prepares closeout if
that session has a recorded muxler tty and, remotely, a valid attachment token.
It matches the exact session name without requiring a group marker. Sessions
without that recorded metadata are still killed only, with no pane closeout.

Manifest creation and iTerm automation are strictly best effort: the tmux kill
always proceeds. Any failure or uncertainty (missing tty, session still alive,
stale manifest, invalid tty, AppleScript error) leaves tabs open and appends a
message to `~/.muxler_closeout.log`.

Pane closeout is controlled by repo-root `config.json`
(`close_tabs_on_kill_session: true` to enable). Missing config, a missing key,
invalid JSON, a non-boolean value, or unavailable Python/parser handling
defaults to `false`; the tmux kill still runs and closeout becomes a no-op when
disabled.
Config is read locally by the closeout helper and by local `kill-session`
preparation, so remote hosts do not need JSON tooling.
