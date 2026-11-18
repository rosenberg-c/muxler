# Muxler

Muxler is my iTerm2 and tmux workspace setup for local and remote development. It provides color-coded shell shortcuts that open or reconnect to local and SSH-backed tmux sessions, along with guides for setting up Debian virtual machines as remote development hosts. It’s a working reference, not a general-purpose installer.

## Use

Requires zsh, tmux, and iTerm2; remote sessions also need SSH access. Shortcuts open one tmux session per tab or pane and reconnect to existing sessions when run again.

```zsh
local-blue path/to/project  # Relative to the current directory
remote-cyan                 # Remote home directory on debian-dev (same as remote-cyan .)
remote-cyan path/to/project # Relative to the remote home directory
```

Local colors: `local-blue`, `local-red`, `local-yellow`, `local-purple`. Remote colors: `remote-magenta`, `remote-orange`, `remote-cyan`, `remote-green`. Remote shortcuts default to the `debian-dev` SSH alias; with no directory argument, they open their configured base path (for example, `remote-webcv` opens its configured webcv path). Supplied paths are relative to that base path and cannot contain `..` segments. Run `kill-local` or `kill-remote` (or `kill-muxler --local|--remote`) to select and close a group of managed sessions; the remote menu lists groups across hosts with hostnames first. Other tmux sessions are left alone. Inside a managed local or remote tmux pane, `kill-session` closes all tabs' sessions in that shortcut's group and directory on its host, without a menu. If the current session has no valid workspace markers, `kill-session` closes only that tmux session; unrelated sessions are left alone. Remote panes receive the command when the next remote shortcut refreshes the shared hook.

Managed iTerm tabs show `LAUNCHER-TAB`, for example `LOCAL-SPICY-NVIM` or `REMOTE-NVIM-LAZYGIT`; other tmux sessions keep their session name. Remote setup enables tmux titles on the remote server, so no remote tmux config is required for titles.

For an explanation of the scripts and how they work together, see [How Muxler fits together](docs/overview.md), [Session lifecycle](docs/session-lifecycle.md), and [Kill menus and remote script](docs/remote-kill.md).

Edit `WORKSPACE_TABS` in `.zsh_session` to choose tab names (nine by default). Shortcuts set their tab count in `sessions.local.sh` and `sessions.remote.sh`; `local-yellow` opens five tabs by default, while the others open nine. Set `tabcount=4` to open the first four tabs (`nvim`, `lazygit`, `opencode`, `tab4`). Keep `tabcount` between 1 and the number of names in `WORKSPACE_TABS`. Set each remote shortcut's `host` in `sessions.remote.sh`; `kill-remote` lists the hosts from `ssh/config`.

For personal shortcuts, create `user.sessions.local.sh` or `user.sessions.remote.sh`. `.zsh_session` loads each file if present, after the built-in shortcuts, so you can add or override aliases without editing tracked files. Both user files are gitignored. For example, in `user.sessions.local.sh`:

```zsh
local-blue() { local tabcount=4; tmux_local_directory local-blue muted_blue "${1:-.}" "$tabcount"; }
```

To put positions 3 and 4 side by side in one iTerm tab, pass an optional split pair after the tab count. The right pane defaults to roughly 25% of the tab width; set `WORKSPACE_SPLIT_RIGHT_PERCENT` to a number from 1 to 99 to change it (for example, `WORKSPACE_SPLIT_RIGHT_PERCENT=40`). The first position still uses the invoking terminal; split pairs must be adjacent positions between 2 and `tabcount`.

```zsh
local-octop() {
  cd ~/personal/dev/octop || return
  local tabcount=6 split='3,4'
  tmux_local_directory local-octop muted_cyan "${1:-.}" "$tabcount" "$split"
}

remote-octop() {
  local host=debian-dev base_path='$HOME' tabcount=6 split='3,4'
  tmux_remote_directory "${1:-.}" "$host" "$base_path" muted_cyan remote-octop octop_ "$tabcount" "$split"
}
```

## Setup

Clone the repo anywhere and run `make install` from the repo to symlink it to `~/.config/muxler` (the command refuses to replace an existing path). Alternatively, move the repo to `~/.config/muxler`. Then add to `~/.zshrc`:

```zsh
source "$HOME/.config/muxler/.zsh_session"
source "$HOME/.config/muxler/.zsh_tmux"
```

Load the local tmux config from `~/.tmux.conf`:

```tmux
source-file ~/.config/muxler/.tmux.conf
```

For remote shortcuts, copy `ssh/config.example` to `ssh/config`, set your host details, and add this to `~/.ssh/config`:

```sshconfig
Include ~/.config/muxler/ssh/config
```
Install tmux on the remote host (`sudo apt install tmux` on Debian).

Remote setup copies `.tmux_session.shared.sh` to the remote home directory and adds source lines to its Bash and Zsh startup files. It does **not** install a remote tmux config. To use the optional smaller config, copy it and add `source-file ~/.tmux.muxler.conf` to the remote `~/.tmux.conf`:

```sh
scp "$HOME/.config/muxler/.tmux.remote.conf" debian-dev:~/.tmux.muxler.conf
```

The remote config supports OSC 52 clipboard copy, extended keys, and Neovim-aware pane navigation (`Ctrl-\` needs `bc`). [`examples/nvim/tmux.lua`](examples/nvim/tmux.lua) is an optional Neovim navigation example; remote Neovim needs its own clipboard setup.

Run the tests with `zsh tests/sessions.zsh`, `zsh tests/tmux_config.zsh`, `zsh tests/tmux_reuse.zsh`, `zsh tests/tmux_local_kill.zsh`, and `zsh tests/tmux_remote_kill.zsh`. Remote tests stub SSH and use temporary host configs, so they do not require aliases in `ssh/config`.

## VM setup notes

- [VirtualBox](virtual/virtualbox/README.md): Debian guest networking, Guest Additions, shared folders, display resizing, and XFCE screen locking.
- [UTM](virtual/utm/README.md): Debian MATE display, keyboard, mouse, and shared-folder setup.
- [VM memory](virtual/NOTE-ON-MEMORY.md): host-memory observations and planning notes.
