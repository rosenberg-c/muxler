# VirtualBox guest display auto-resize

First install [Guest Additions](02_GuestAdditions.md). If automatic resizing still does not work, this X11 workaround watches the modes advertised for `Virtual-1`. **Run `xrandr` from a terminal in the VM desktop, not over SSH:** an SSH shell does not have access to the desktop display by default. Check the actual output name there; replace `Virtual-1` if needed.

Create the polling script:

```sh
mkdir -p ~/.local/bin
nano ~/.local/bin/vbox-autoresize.sh
```

```sh
#!/bin/bash

OUTPUT="Virtual-1" # Replace with the output name reported by xrandr.
LAST_MODES=""

while true; do
    # Read the modes currently advertised for the virtual display
    MODES=$(xrandr --query | sed -n "/^$OUTPUT connected/,/^[^ ]/p")

    if [ "$MODES" != "$LAST_MODES" ]; then
        sleep 0.5
        xrandr --output "$OUTPUT" --auto
        LAST_MODES="$MODES"
    fi

    sleep 1
done
```

Make it executable:

```sh
chmod +x ~/.local/bin/vbox-autoresize.sh
```

In a terminal in the VM desktop, check `echo "$DISPLAY"` and `echo "$XAUTHORITY"`. In the wrapper below, replace the example display, authority path, and username with your values; do not assume `:0` or `~/.Xauthority` are correct:

```sh
nano ~/.local/bin/vbox-autoresize-wrapper.sh
```

```sh
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/user/.Xauthority
exec /home/user/.local/bin/vbox-autoresize.sh
```

```sh
chmod +x ~/.local/bin/vbox-autoresize-wrapper.sh
```

Create the user service (replace `/home/user` with your guest user's home path):

```sh
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/vbox-autoresize.service
```

```sh
[Unit]
Description=VirtualBox auto-resize for Virtual-1
After=graphical-session.target

[Service]
Type=simple
ExecStart=/home/user/.local/bin/vbox-autoresize-wrapper.sh
Restart=always

[Install]
WantedBy=default.target
```

Enable it, then resize the VM window to check it:

```sh
systemctl --user daemon-reload
systemctl --user enable --now vbox-autoresize.service
systemctl --user status vbox-autoresize.service
```
