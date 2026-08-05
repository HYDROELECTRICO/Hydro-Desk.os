# Hydro Desk OS Architecture

Hydro Desk OS is a minimal Debian Live based operating system intended to boot directly from USB. The user-facing environment is restricted to two graphical applications:

1. **Google Chrome Stable** — installed from Google's official Linux repository during the ISO build.
2. **PCManFM File Manager** — used for local files and removable USB/media browsing.

No desktop environment, panel, app store, office suite, games, terminal launcher, package GUI, installer, or extra application menu is included.

## Boot flow

1. The ISO boots with Debian `live-boot` / `live-config`.
2. The live user is created as `hydro` from `/etc/skel`.
3. A `getty@tty1` systemd drop-in logs `hydro` into TTY1 automatically after `live-config` finishes.
4. `/etc/skel/.bash_profile` immediately runs `startx`.
5. `.xinitrc` starts a DBus session and launches Openbox.
6. Openbox autostart runs `pcmanfm --desktop --profile hydro-desk` to show only the desktop icons in `~/Desktop`.

## User-visible surface

- Desktop icon: **Chrome**
- Desktop icon: **File Manager**
- Right-click Openbox menu: **Chrome** and **File Manager** only
- Keyboard shortcuts:
  - `Super+C`: Chrome
  - `Super+F`: File Manager

## Required non-visible plumbing

A live OS cannot boot with literally only two packages. The build includes minimal supporting components: Linux kernel, systemd, live-boot, Xorg, Openbox, DBus, fonts, NetworkManager backend, udisks/gvfs for removable-drive mounting, and certificate authorities for HTTPS.

These components are not exposed as user applications.

## Design constraints

- Bootable as an `iso-hybrid` image, suitable for USB writing with `dd`, Rufus, Balena Etcher, GNOME Disks, or `scripts/write-usb.sh`.
- No Debian installer is included.
- No memtest boot entry is included.
- APT recommends are disabled to reduce accidental extra packages.
- Temporary build helpers for Chrome (`wget`, `gnupg`) are purged after Chrome is installed.
