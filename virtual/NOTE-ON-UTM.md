## UTM Linux/Debian Black-Screen Bug

**Symptoms:**
- VM works normally for several hours, then the display goes black or freezes.
- SSH remains functional, indicating Debian is still running.
- Restarting the VM temporarily fixes the issue.

**Likely cause:**
- Virtual GPU (`virtio_gpu`) or Linux display-server (Xorg/Wayland) hang.

**Workarounds:**
- Restart the display manager via SSH.
- Disable 3D acceleration or switch virtual GPU settings.
- Restart the VM if other methods fail.

**Fix status (November 2026):**
- The black-screen issue may be fixed in the latest UTM version, but I have not confirmed it for my setup.
- UTM 5.x includes related GPU fixes.
- Issue #7414 was closed after Debian updates appeared to resolve it.
- Issue #5008 remains open.

**Separate disk issue:** My virtual hard drive became corrupted. My computer entering sleep mode may have caused it, possibly due to a UTM bug. Another user reported a disk image that QEMU could not read after a suspected wake-related crash (#4076); a Debian user reported I/O hangs when macOS slept (#7475). Neither report confirms the cause of my corruption.

I am using VirtualBox for the time being.
Keeping setups for future reference

**References:**
- #7414 — Linux display freezes, SSH works:
  https://github.com/utmapp/UTM/issues/7414
- #5008 — Xorg hangs in VirtIO GPU:
  https://github.com/utmapp/UTM/issues/5008
- #3859 — Debian XFCE black screen:
  https://github.com/utmapp/UTM/issues/3859
- UTM releases:
  https://github.com/utmapp/UTM/releases
- #4076 — Disk image unreadable after suspected wake-related crash:
  https://github.com/utmapp/UTM/issues/4076
- #7475 — Debian I/O hang when macOS sleeps:
  https://github.com/utmapp/UTM/issues/7475
