# UTM guest display auto-resize

For a Debian MATE guest using X11, this workaround adjusts the display when the UTM window changes size.

## Check the display

In the guest's graphical session, check the output name and environment:

```sh
xrandr
echo "$DISPLAY"
echo "$XAUTHORITY"
```

The examples below use output `Virtual-1`, display `:0`, and `/home/user`. Replace them with your values; `XAUTHORITY` may be empty in some sessions.

## Create the resize script

```sh
mkdir -p ~/bin
nano ~/bin/autoresize.sh
```

Save this script, changing `Virtual-1` if needed:

```sh
#!/bin/bash
while true; do
    xrandr --output Virtual-1 --auto
    sleep 2
done
```

```sh
chmod +x ~/bin/autoresize.sh
```

Run it from the graphical session to test, then stop with Ctrl+C (it may fail over SSH without display access):

```sh
~/bin/autoresize.sh
```

## Run at login

Create a wrapper. Replace the example display, authority path, and home directory with the values for your guest:

```sh
nano ~/bin/autoresize-wrapper.sh
```

```sh
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/home/user/.Xauthority
exec /home/user/bin/autoresize.sh
```

```sh
chmod +x ~/bin/autoresize-wrapper.sh
```

Create a user service; replace `/home/user` with your guest home path:

```sh
mkdir -p ~/.config/systemd/user
nano ~/.config/systemd/user/autoresize.service
```

```ini
[Unit]
Description=UTM auto-resize for Virtual-1
After=graphical-session.target

[Service]
Type=simple
ExecStart=/home/user/bin/autoresize-wrapper.sh
Restart=always

[Install]
WantedBy=default.target
```

Enable and check the service:

```sh
systemctl --user daemon-reload
systemctl --user enable --now autoresize.service
systemctl --user status autoresize.service
```

Resize the UTM window to verify. If it does not adjust, inspect the logs:

```sh
journalctl --user -u autoresize.service -f
```
