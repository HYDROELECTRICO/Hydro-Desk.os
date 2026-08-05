# GitHub પરથી ISO Build અને Download

Hydro Desk OS ની bootable ISO GitHub Actions પર સંપૂર્ણ રીતે build થઈ શકે છે. એટલે તમારા computer પર `live-build` ચલાવવાની જરૂર નથી.

## Manual build

1. GitHub પર repository ખોલો.
2. **Actions** tab ખોલો.
3. **Build Hydro Desk OS ISO** workflow પસંદ કરો.
4. **Run workflow** દબાવો.
5. Temporary download જોઈએ હોય તો **publish_release** disabled રાખો.
6. Job finish થાય ત્યાં સુધી રાહ જુઓ.
7. Completed workflow run ખોલો.
8. `hydro-desk-os-amd64-<run-number>` artifact download કરો.
9. Download થયેલું ZIP extract કરો. તેમાં આ files મળશે:

```text
hydro-desk-os-amd64.iso
hydro-desk-os-amd64.iso.sha256
```

Artifact 30 દિવસ સુધી GitHub પર રહેશે.

## Permanent GitHub Release બનાવવી

કાયમી ISO download link જોઈએ હોય તો release publish કરો.

### Option A: Actions માંથી manual release

1. **Actions** → **Build Hydro Desk OS ISO** → **Run workflow** ખોલો.
2. **publish_release** enable કરો.
3. Release tag લખો, ઉદાહરણ:

```text
v0.1.0
```

4. Workflow run કરો.
5. Finish થયા પછી GitHub Release create/update થશે અને ISO files attach થશે.

### Option B: version tag push કરવો

`v0.1.0` જેવો tag push કરવાથી workflow ISO build કરીને Release માં attach કરશે.

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Download કરેલી ISO USB માં નાખવી

Linux પર:

```bash
lsblk
sudo ./scripts/write-usb.sh /dev/sdX hydro-desk-os-amd64.iso
```

`/dev/sdX` ને USB device સાથે બદલો. `/dev/sdX1` જેવી partition path આપવી નહીં.

Windows/macOS પર Rufus, Balena Etcher, GNOME Disks અથવા hybrid ISO support કરતી કોઈપણ tool વાપરી શકાય.
