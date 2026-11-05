# Muxler

Muxler is my iTerm2 and tmux workspace setup for local and remote development. It provides color-coded shell shortcuts that open or reconnect to local and SSH-backed tmux sessions, along with guides for setting up Debian virtual machines as remote development hosts. It’s a working reference, not a general-purpose installer.

## Use

Requires zsh, tmux, and iTerm2; remote sessions also need SSH access. Shortcuts open one tmux session per tab and reconnect to existing sessions when run again.

```zsh
local-blue path/to/project  # Relative to the current directory
remote-cyan .               # Remote home directory on debian-dev
remote-cyan path/to/project # Relative to the remote home directory
```

Local colors: `local-blue`, `local-red`, `local-yellow`, `local-purple`. Remote colors: `remote-magenta`, `remote-orange`, `remote-cyan`, `remote-green`. Remote shortcuts default to the `debian-dev` SSH alias; they accept relative paths without `..` segments. Run `kill-local-tmux` or `kill-remote-tmux` to select and close a group of managed sessions; the remote menu lists groups across hosts with hostnames first. Other tmux sessions are left alone.

For an explanation of the scripts and how they work together, see [How Muxler fits together](docs/overview.md), [Session lifecycle](docs/session-lifecycle.md), and [Kill menus and remote script](docs/remote-kill.md).

Edit `WORKSPACE_TABS` in `.zsh_session` to choose tab names (nine by default). Shortcuts set their tab count in `sessions.local.sh` and `sessions.remote.sh`; `local-yellow` opens five tabs by default, while the others open nine. Set `tabcount=4` to open the first four tabs (`nvim`, `lazygit`, `opencode`, `tab4`). Keep `tabcount` between 1 and the number of names in `WORKSPACE_TABS`. Set each remote shortcut's `host` in `sessions.remote.sh`; `kill-remote-tmux` lists the hosts from `ssh/config`.

For personal shortcuts, create `user.sessions.local.sh` or `user.sessions.remote.sh`. `.zsh_session` loads each file if present, after the built-in shortcuts, so you can add or override aliases without editing tracked files. Both user files are gitignored. For example, in `user.sessions.local.sh`:

```zsh
local-blue() { local tabcount=4; tmux_local_directory local-blue muted_blue "${1:-.}" "$tabcount"; }
```

## Setup

Clone or move this repo to `~/.config/muxler`, then add to `~/.zshrc`:

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
