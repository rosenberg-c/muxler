# UTM shared folder (Debian guest)

Enable a shared folder in UTM first. Reference: <https://docs.getutm.app/guest-support/linux/>.

Install guest support and create the mount points:

```sh
sudo apt install bindfs -y
sudo apt install spice-vdagent -y
sudo apt install qemu-guest-agent -y
sudo mkdir -p /mnt/utm
mkdir -p ~/utm
```

Add this line to `/etc/fstab` with `sudo nano /etc/fstab`:

```text
share /mnt/utm 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail,auto 0 0
```

Reload the mount units, mount, and inspect ownership:

```sh
sudo systemctl daemon-reload
sudo mount -a
ls -na /mnt/utm
```

If the shared files have a different UID/GID than your guest user, use `id` to find your guest UID/GID, then add a bindfs remap line to `/etc/fstab`. Replace `501`, `20`, `1000`, and `/home/user` with your actual values:

```text
/mnt/utm /home/user/utm fuse.bindfs map=501/1000:@20/@1000,x-systemd.requires=/mnt/utm,_netdev,nofail,auto 0 0
```

Reload and verify both mounts:

```sh
sudo systemctl daemon-reload
sudo mount -a
ls -la ~/utm
```
