# VirtualBox shared folder access

After adding a shared folder in VirtualBox, add your guest user to `vboxsf`. Log out and back in for the new group membership to apply.

```sh
sudo usermod -aG vboxsf "$USER"
```
