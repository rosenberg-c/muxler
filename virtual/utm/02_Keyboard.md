# UTM guest keyboard layout

Reconfigure the Debian guest's keyboard, then reboot. The choices below are an example for a Swedish Mac keyboard; select your own layout if different.

```sh
sudo dpkg-reconfigure keyboard-configuration
```

- Generic 105
- Swedish (Macintosh)
- Left Alt
- No compose
- X server: No

```sh
sudo reboot
```
