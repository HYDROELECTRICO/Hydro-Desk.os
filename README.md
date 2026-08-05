# Hydro Desk OS

Hydro Desk OS એક મિનિમલ live-USB ઓપરેટિંગ સિસ્ટમ છે. USB માંથી સીધી boot થાય છે અને graphical desktop પર ફક્ત બે જ user-facing apps બતાવે છે:

- **Google Chrome**
- **File Manager**

Desktop environment, panel, app store, office suite, games, terminal shortcut, installer અથવા extra application menu સામેલ નથી.

## GitHub પરથી ISO download

હા — ISO GitHub Actions પર પણ build થઈ શકે છે. GitHub પર **Actions → Build Hydro Desk OS ISO → Run workflow** ચલાવો. Workflow પૂરો થયા પછી artifact/release માંથી `hydro-desk-os-amd64.iso` download કરો અને USB માં write કરીને boot કરો.

વિગતવાર steps: [`docs/github-build.md`](docs/github-build.md)

## ISO build કરવી

Debian 12/Ubuntu પર sudo access સાથે:

```bash
./scripts/build-iso.sh --install-deps --clean
```

Output files:

```text
out/hydro-desk-os-amd64.iso
out/hydro-desk-os-amd64.iso.sha256
```

## USB માં લખવું

> ચેતવણી: પસંદ કરેલી USB drive સંપૂર્ણ erase થશે.

```bash
lsblk
sudo ./scripts/write-usb.sh /dev/sdX out/hydro-desk-os-amd64.iso
```

`/dev/sdX` ને તમારી USB device સાથે બદલો. Partition path જેમ કે `/dev/sdX1` આપવો નહીં.

Rufus, Balena Etcher, GNOME Disks અથવા hybrid ISO support કરતી કોઈપણ tool થી પણ ISO USB માં લખી શકાય છે.

## Live boot

1. USB drive insert કરો.
2. Computer boot menu માંથી USB select કરો.
3. Hydro Desk OS automatic live boot થશે અને `hydro` user તરીકે login થશે.
4. Desktop પર ફક્ત **Chrome** અને **File Manager** launchers દેખાશે.

## નોંધ

- Reliable hardware boot support માટે આ Debian Live based છે.
- Google Chrome build સમયે Google ની official Linux repository માંથી install થાય છે.
- Networking, graphics અને USB mounting services Chrome અને File Manager ચલાવવા માટે hidden OS plumbing તરીકે જ સામેલ છે; extra user apps તરીકે નથી.
