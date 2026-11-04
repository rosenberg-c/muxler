# Disable XFCE screen locking and screen blanking

Run these in the guest's XFCE session. This disables locking, so use only where that is appropriate.

```sh
sudo sed -i 's|^#\?xserver-command=.*|xserver-command=X -s 0 -dpms|' /etc/lightdm/lightdm.conf

xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s false
xfconf-query -c xfce4-session -p /general/LockCommand -s ""
pkill light-locker
```
