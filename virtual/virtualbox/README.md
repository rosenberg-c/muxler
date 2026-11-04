# VirtualBox guest setup

Notes for a Debian guest in VirtualBox. Commands run inside the guest unless noted.

## First-time setup

1. Install Debian from the [netinst image](https://www.debian.org/CD/netinst/).
2. **Boot the installed guest once with only Adapter 1. Do not add Adapter 2 until after this first boot.**
3. For sudo access, run `su -`, install `sudo` if needed (`apt install sudo`), then run `usermod -aG sudo <username>`. Log out and back in before using `sudo`.
4. Shut down the VM, add host-only Adapter 2 in VirtualBox, and boot it. Once it has a host-only IP, SSH in and follow [Networking](01_Network.md) to configure the interfaces (use the VM console first if SSH is not yet reachable). Recheck the IP after reboot; it may change.
5. **XFCE:** If Guest Additions does not resize the screen, follow the [display workaround](AutoResizeScreen.md).
6. **External monitor:** If the resolution is off, disable the workaround service with `systemctl --user disable --now vbox-autoresize.service`, choose **View → Scaled Mode** in VirtualBox, and set the guest resolution manually.

## Guides

- [Networking](01_Network.md): Adapter 1 for internet; host-only Adapter 2 for SSH from the host.
- [Guest Additions](02_GuestAdditions.md): install the guest-side display and shared-folder support.
- [Shared folders](03_Share.md): grant the guest user access to VirtualBox shares.
- [Display resizing](AutoResizeScreen.md): X11 workaround if Guest Additions do not resize the display.
- [XFCE screen locking](XFCE_disable_lockout.md): disable locking when appropriate.
