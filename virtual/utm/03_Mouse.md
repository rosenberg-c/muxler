# UTM guest mouse scrolling

These X11 commands require a graphical session. Inspect `xinput list` first; device IDs (such as 7, 8, and 10) vary, so use the device name when available.

```sh
sudo apt update
sudo apt install xinput
xinput list
```

For a QEMU USB Tablet, enable natural scrolling and turn off high-resolution wheel scrolling if needed:

```sh
xinput set-prop "QEMU QEMU USB Tablet" "libinput Natural Scrolling Enabled" 1
xinput set-prop "QEMU QEMU USB Tablet" "libinput High Resolution Wheel Scroll Enabled" 0
```

## Persist natural scrolling

Create a login script, replacing the device name if yours differs:

```sh
mkdir -p ~/bin

cat > ~/bin/natural-scroll.sh << 'EOF'
#!/bin/sh
xinput set-prop "QEMU QEMU USB Tablet" "libinput Natural Scrolling Enabled" 1
EOF
chmod +x ~/bin/natural-scroll.sh
```

In MATE Control Center → Startup Applications, add `~/bin/natural-scroll.sh` with a 10-second delay. Log back in and check the scroll direction.
