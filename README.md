# M10 MTK Preloader Recovery and OobConfig Removal

Owner-authorized recovery notes for the `M10_4G` (`ML_JI0L_M10_4G`) tablet,
tested on the MediaTek MT6765/MT8768t platform with dynamic partitions.

This project documents how to:

- connect to an authorized device through MediaTek Preloader/BROM;
- use a matching preloader image only as DRAM initialization data;
- restore a known-good `super` image;
- remove Google Device Setup (`com.google.android.apps.work.oobconfig`);
- prepare `vbmeta_a` for a deliberately modified logical partition;
- verify the result over ADB and detect a package restored by an OTA.

It is not a carrier/SIM unlock, FRP bypass, bootloader unlock, or authorization to
modify a managed device. Use it only on hardware you own or are authorized to
service. Removing enrollment/provisioning software may violate an organization's
policy or local law. All commands are destructive unless explicitly described as
read-only.

## Tested layout

The tested GPT contained a 4 GiB `super` partition. Slot 0 metadata described:

| Logical partition | First sector in `super` | Byte offset | Size |
| --- | ---: | ---: | ---: |
| `product_a` | 2,048 | 1,048,576 | 1,218,813,952 bytes |
| `vendor_a` | 2,383,872 | 1,220,542,464 | 186,642,432 bytes |
| `system_a` | 2,748,416 | 1,407,188,992 | 1,263,587,328 bytes |

Never reuse these offsets blindly. Verify them with `lpdump` on the exact image.
The tested OobConfig files existed only at:

```text
product_a:/priv-app/OobConfig/
```

No second copy was found in `system_a`.

## Requirements

- Linux with Python 3, `libusb`, and FUSE access
- [mtkclient](https://github.com/bkerler/mtkclient)
- Android platform-tools (`adb`)
- Android logical-partition tools (`lpdump`, `lpunpack`, `lpmake`)
- `fuse2fs`, `debugfs`, and `apkanalyzer`
- a device-specific preloader extracted from the same firmware/device family
- verified backups of `super`, `vbmeta_a`, and critical device partitions

The preloader used in the tested session had this SHA-256:

```text
ca8c09a3b283289779be321eb11a25d601154786a7cc33757ea5a4ef541f8e6d
```

That hash is documentation, not proof that the file matches another tablet.
Never flash the preloader as part of this procedure; pass it only via
`--preloader=...` for DRAM setup.

## 1. Verify inputs

```bash
sha256sum /path/to/preloader.bin /path/to/super_full.bin /path/to/vbmeta_a.bin
lpdump /path/to/super_full.bin
```

Confirm the hardware, image provenance, logical partition names, extents, and
sizes before connecting the tablet.

## 2. Read the GPT through BROM

Run from the mtkclient checkout:

```bash
python3 mtk.py printgpt --preloader=/path/to/preloader.bin
```

Power the tablet off. For BROM, connect USB while holding both volume buttons.
The successful tested sequence reported `DRAM setup passed` before listing GPT.
Stop if the chipset, eMMC, partition layout, or DRAM setup differs.

## 3. Prepare a modified `super` image

Preserve the original and work on a copy:

```bash
cp --reflink=auto super_full.bin super_patched.bin
mkdir -p mnt_product
lpdump super_patched.bin
```

For the tested layout only, mount `product_a` at byte offset 1,048,576:

```bash
fuse2fs super_patched.bin mnt_product \
  -o rw,fakeroot,offset=1048576
```

Verify the APK identity before removal:

```bash
apkanalyzer manifest application-id \
  mnt_product/priv-app/OobConfig/OobConfig.apk
```

Expected output:

```text
com.google.android.apps.work.oobconfig
```

Remove only the verified directory, sync, and unmount:

```bash
rm -rf -- mnt_product/priv-app/OobConfig
sync
fusermount3 -u mnt_product
```

Mount the same offset read-only and confirm that `find` returns no match before
flashing. Run `lpdump` again to ensure the logical-partition metadata is intact.

## 4. Prepare `vbmeta_a`

Changing `product_a` invalidates its verified-boot hash. On an owner-unlocked
device, prepare a copy of the matching `vbmeta_a` with flags `3` (disable verity
and verification):

```bash
python3 scripts/patch_vbmeta_flags.py \
  /path/to/vbmeta_a.bin vbmeta_a_flags3.bin
```

The script refuses non-AVB images and unexpected existing flags. This does not
unlock a bootloader. A locked device can reject modified images or fail to boot.

## 5. Flash and factory-reset

The following commands overwrite data. Keep stable USB power and do not unplug
during writes:

```bash
python3 mtk.py w super /path/to/super_patched.bin \
  --preloader=/path/to/preloader.bin

python3 mtk.py w vbmeta_a /path/to/vbmeta_a_flags3.bin \
  --preloader=/path/to/preloader.bin

python3 mtk.py e userdata,metadata \
  --preloader=/path/to/preloader.bin
```

The tested tablet used slot `_a`. Verify the active slot instead of assuming it.
Do not erase `system_a`; it is a logical partition inside `super`.

## 6. Verify after boot

Enable USB debugging, authorize the host, then run:

```bash
./scripts/verify_oobconfig.sh
```

Expected results include `sys.boot_completed=1`, no OobConfig package/activity,
and the normal Google packages still installed.

## OTA behavior

A reboot or factory reset does not recreate a file removed from `product_a`.
A full firmware flash or OTA may replace `product_a` and restore the package.
The Android developer setting below disables automatic OTA application on builds
that honor it, but does not prevent a user-initiated update:

```bash
adb shell settings put global ota_disable_automatic_update 1
```

After any update, run:

```bash
./scripts/oobconfig_post_ota_guard.sh
```

If the package is absent, the script changes nothing. If it has returned, the
script disables its reset Activity, applies background app-ops where supported,
and disables the package for user 0. Review the script before use.

## Recovery

If Android fails to boot, return to BROM using the matching preloader as DRAM
data and restore the unmodified, checksum-verified `super` and `vbmeta_a` backups.
Do not experiment with `preloader`, `nvram`, `nvdata`, `persist`, `proinfo`, RPMB,
or OTP; those partitions can contain device-unique calibration or security data.

