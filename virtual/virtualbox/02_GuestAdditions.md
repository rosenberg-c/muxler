# VirtualBox Guest Additions (Debian guest)

Insert the Guest Additions ISO from the VirtualBox menu first. Use the installer matching your guest architecture; the command below is for ARM64.

Reference: <https://www.server-world.info/en/note?os=Debian_13&p=virtualbox&f=3>

```sh
sudo apt install gcc make bzip2 linux-headers-$(uname -r)
sudo mkdir -p /mnt/guest
sudo mount /dev/cdrom /mnt/guest
sudo /mnt/guest/VBoxLinuxAdditions-arm64.run
```
