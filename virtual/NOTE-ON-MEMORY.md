# VM memory on Apple Silicon

On my M1 Mac, UTM and VirtualBox have reported host memory use above the VM's configured RAM. The increase can develop over time rather than appearing immediately after startup, so a quick check may miss it. For UTM/QEMU, I use **up to 2× guest RAM as a planning allowance**, not as a measured physical-memory multiplier.

| UTM/QEMU measurement | Value |
|---|---:|
| Configured guest RAM | 2 GB |
| Activity Monitor (QEMULauncher) | 3.99 GB |
| `footprint` categorized total | 2,037 MB |
| `phys_footprint` auxiliary value | 4,085 MB |
| Ballooning | Enabled |

These counters do **not** prove the VM used 4 GB of unique physical RAM. Allocate only what the guest needs, then check macOS Memory Pressure and Swap Used before and after starting the VM and after idle. Don't assume ballooning returns memory to the host.

## References

- [UTM: approximately doubled memory](https://github.com/utmapp/UTM/discussions/5647)
- [UTM: memory growth](https://github.com/utmapp/UTM/issues/7764)
- [UTM: QEMULauncher memory](https://github.com/utmapp/UTM/issues/4958)
- [Lima: memory ballooning tracking](https://github.com/lima-vm/lima/issues/4220)
- [Lima: ballooning implementation](https://github.com/lima-vm/lima/pull/4226)
- [VirtualBox 7.2 known issues](https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/EN-VBOX-7-2-USER.pdf)
- [VirtualBox Guest Additions and memory overcommitment](https://docs.oracle.com/en/virtualization/virtualbox/7.1/user/guestadditions.html)

Oracle documents that VirtualBox memory ballooning is **not supported on macOS hosts**. The VirtualBox references do not establish the 2× observation; I did not verify an open VirtualBox bug for that exact behavior.
