# ODROID-HC4 encrypted root (LUKS) — design notes

Branch: **`odroid-hc4-encrypt-root`** (PRs target this branch until merged to `odroid-hc4`).

## Goal

Ship a `Tumbleweed.OdroidHC4` OEM `.raw` image where:

- **FAT `/boot`** (partition 1) stays **unencrypted**: U-Boot, extlinux, kernel, DTB, initrd.
- **Root** (partition 3, btrfs + Snapper) sits inside **LUKS2**.
- At **early boot**, the user is prompted for the **LUKS passphrase** (decryption) before the system pivots to the real root.

HC4 does **not** use GRUB cryptodisk on the boot path (U-Boot → extlinux → kernel + dracut initrd). Passphrase entry belongs in **dracut** (initrd), not in U-Boot/extlinux configuration.

References:

- [KIWI NG — disk setup for LUKS](https://osinside.github.io/kiwi/working_with_images/disk_setup_for_luks.html)
- [KIWI NG — customize boot / `rd.kiwi.oem.luks.*`](https://osinside.github.io/kiwi/concept_and_workflow/customize_the_boot_process.html)
- Existing x86_64 example (GRUB + PBKDF2): `rockstor.kiwi` `Leap16.0.x86_64` preferences (commented `luks`, `luksformat`).

## Current HC4 boot stack (unencrypted root)

| Layer | Role today |
|--------|------------|
| `rockstor.kiwi` `Tumbleweed.OdroidHC4` | MBR, `bootpartition="true"`, btrfs root, `editbootinstall_odroid_hc4.sh` |
| `editbootinstall_odroid_hc4.sh` | Recreate FAT `/boot`, patch initrd + extlinux, write Armbian U-Boot |
| `scripts/patch-hc4-initrd.sh` | HC4 MMC hooks, disable kiwi-repart, optional oem-resize flags |
| `scripts/patch-hc4-extlinux-root.sh` | `root=LABEL=ROOT` on **partition 3** |
| `config.sh` (OdroidHC4) | `hostonly=no`, MMC drivers in dracut |
| `pre_disk_sync.sh` | fstab `LABEL=ROOT` / `BOOT` / `SWAP` |
| `rockstor-hc4-expand-root.service` | Grow MBR p3 + btrfs (LUKS-aware work **not** implemented yet) |

Kernel cmdline (installer image): `console=ttyAML0,115200n8`, `plymouth.enable=0`, MMC `rd.driver.pre=*`.

## Recommended LUKS model for HC4

Use KIWI **partial encryption** (matches existing layout):

```xml
<type … bootpartition="true" … luks="…" luks_version="luks2">
  <luksformat>
    <option name="--pbkdf" value="PBKDF2"/>
  </luksformat>
  …
</type>
```

- `bootpartition="true"`: keep **512 MiB FAT `BOOT`**; encrypt **root** only ([KIWI LUKS docs](https://osinside.github.io/kiwi/working_with_images/disk_setup_for_luks.html)).
- `cryptsetup` is already in `rockstor.kiwi` image packages.
- **PBKDF2** matters mainly for GRUB cryptodisk on x86; HC4 can still use LUKS2 defaults, but aligning with the existing x86_64 profile avoids surprises if tooling assumes PBKDF2.

### Passphrase: build-time vs runtime

- The `luks="…"` attribute in `rockstor.kiwi` is **security-sensitive** (master passphrase baked at image build).
- For published images, plan **OEM first-boot re-encryption** so the shipped passphrase is not the long-term secret:
  - `rd.kiwi.oem.luks.reencrypt` — reencrypt when LUKS header matches the built image ([KIWI boot customization](https://osinside.github.io/kiwi/concept_and_workflow/customize_the_boot_process.html)).
  - Optionally `rd.kiwi.oem.luks.reencrypt_randompass` + later key escrow (TPM not available on HC4; user must set a new passphrase during/after reencrypt).
- Prefer `luks="file:///path/to/keyfile"` in **private build environments**, not committed XML.

### Where the user types the passphrase

| Approach | HC4 fit |
|----------|---------|
| GRUB cryptodisk | **No** — not the HC4 boot chain |
| **dracut `crypt` module** in initrd | **Yes** — unlock before `switch_root` |
| systemd mount only (late) | KIWI doc wording for `bootpartition="true"`; on openSUSE dracut still normally handles LUKS in initrd when `crypttab` / `rd.luks.*` is present |

**Initrd requirements:**

1. Include dracut **`crypt`** module (and dependencies: `cryptsetup`, `dm-crypt`).
2. Keep **`console=ttyAML0,115200n8`** (and `console=tty0`) so `systemd-ask-password` / dracut prompt works on **serial and HDMI**.
3. Consider `rd.systemd.show_status=1` during bring-up for visible prompts on tty0.
4. Extend `config.sh` `rockstor-odroid-hc4.conf` or `patch-hc4-initrd.sh` to force `add_dracutmodules+=" crypt "` if hostonly/no-crypt regressions appear.

**FAT `/boot` content:** unchanged role — only store **public** boot artifacts. Do **not** put LUKS keyfiles on FAT in production.

## `rockstor.kiwi` changes (HC4 profile)

On `Tumbleweed.OdroidHC4` `<type …>`:

1. Add `luks` + `luks_version="luks2"` (+ optional `<luksformat>` PBKDF2).
2. Add OEM kernel cmdline flags for reencrypt on first deployment, e.g. extend `kernelcmdline`:
   - `rd.kiwi.oem.luks.reencrypt` (and document user passphrase change flow).
3. Review **`oem-resize-once`**: conflicts with LUKS grow semantics; may need to stay disabled (as today via `patch-hc4-initrd.sh`) and rely on **`rockstor-hc4-expand-root`** after LUKS resize support exists.
4. Optional: profile suffix in version string (`5.5.3-0-luks`) for release naming.

Mirror comments from x86_64 block into HC4 preferences so maintainers see PBKDF2 / passphrase warnings in one place.

## Boot partition / extlinux (not “ask in extlinux”)

extlinux **cannot** unlock LUKS. It only loads kernel + initrd and passes **kernel command line**.

Today `patch-hc4-extlinux-root.sh` sets `root=LABEL=ROOT` by `blkid` on **partition 3**. With LUKS, partition 3 is **`crypto_LUKS`**; **LABEL=ROOT** is on the **opened** device / btrfs inside the mapper.

**Required updates:**

1. **`patch-hc4-extlinux-root.sh`**
   - If p3 is LUKS: set `rd.luks.uuid=<LUKS UUID>` (or `rd.luks.name=…`) on the `append` line.
   - Keep `root=` as btrfs UUID/LABEL **inside** the unlocked volume (as KIWI writes in `/config.bootoptions` / image root).
   - Do not point `root=` at the raw LUKS partition device.

2. **`scripts/validate-hc4-extlinux-root.sh`**
   - Validate LUKS UUID + inner root spec against loop-mounted image.

3. **`editbootinstall_odroid_hc4.sh`**
   - No passphrase UI here; ensure patched initrd on FAT is the **same** dracut image that contains `crypt` module.

4. **README** (`Tumbleweed.OdroidHC4`): document serial/HDMI prompt at boot, build passphrase vs post-install reencrypt, flash steps unchanged (`.raw.xz`).

## `config.sh` / dracut / initrd patch

| File | LUKS-related work |
|------|-------------------|
| `config.sh` | `add_dracutmodules+=" crypt "` for OdroidHC4; ensure `/etc/crypttab` generation by KIWI is not stripped |
| `scripts/patch-hc4-initrd.sh` | Verify `crypt` hooks present after unpack; optional `pre-mount` sanity; keep MMC hooks **before** crypt open |
| `pre_disk_sync.sh` | fstab: root on `/dev/mapper/…` or UUID of btrfs; confirm KIWI LUKS layout vs `LABEL=ROOT` |

## First-boot expand-root + LUKS

`rockstor-hc4-expand-root-partition.sh` today:

1. Grows MBR partition 3.
2. `btrfs filesystem resize max`.

With LUKS it must become:

1. Grow partition 3 (`parted`).
2. **`cryptsetup resize`** on the LUKS device (mapper).
3. **`btrfs filesystem resize max`** on the decrypted mapper.

Order and online/offline constraints must be tested on real HC4 hardware.

## OEM installer / Rockstor workflow

- Installer still dumps OEM image to target disk; LUKS header travels with the image.
- **Rockstor** on encrypted root: confirm Web UI and btrfs tools see `/` on mapper; Snapper subvol path `@/.snapshots/1/snapshot` unchanged.
- **Swap** (p2): typically **unencrypted** in partial-LUKS layouts; document threat model.

## Validation checklist

- [ ] `kiwi-ng` schema load for `Tumbleweed.OdroidHC4` with LUKS attrs (x86_64 cloud agent: schema only).
- [ ] Full build on arm64 + `validate-hc4-raw-uboot.sh` / extlinux validator (LUKS-aware).
- [ ] Boot HC4: prompt on **ttyAML0** and **HDMI**; successful unlock and `switch_root`.
- [ ] Reboot: same passphrase; marker for expand-root + resize inside LUKS.
- [ ] Flash script: no change expected (bit-copy `.raw`).

## Suggested implementation order (PRs on `odroid-hc4-encrypt-root`)

1. `rockstor.kiwi` + README + private build keyfile convention.
2. `config.sh` / dracut `crypt` module.
3. extlinux patch + validate scripts (LUKS UUID).
4. `patch-hc4-initrd.sh` / cmdline for reencrypt + serial console prompts.
5. `rockstor-hc4-expand-root-partition.sh` LUKS resize.
6. Experimental GitHub release notes (draft / dev disclaimer).

## Risks / open questions

- **Fixed passphrase in XML** if reencrypt is skipped — unacceptable for production; treat as dev-only until reencrypt flow is verified.
- **Dracut hostonly**: already `hostonly=no` on HC4; keep it for LUKS + MMC modules in initrd on FAT.
- **Performance**: LUKS on SD/eMMC; acceptable for NAS use but worth noting in release text.
- **Kiwi + `oem-resize-once`**: keep disabled on HC4; coordinate with LUKS grow.

## Comparison: Armbian MMGen tutorial (forum topic 15618)

Source: [Full root filesystem encryption on an Armbian system](https://forum.armbian.com/topic/15618-full-root-filesystem-encryption-on-an-armbian-system-new-replaces-2017-tutorial-on-this-topic/) (MMGen, 2020; automated sibling: [mmgen-geek-tools](https://github.com/mmgen/mmgen-geek-tools)). **Odroid HC4** is listed among boards the author tested (Debian Buster / Ubuntu Focal mainline).

### What the tutorial does

| Step | Armbian MMGen | Rockstor HC4 kiwi image today |
|------|----------------|-------------------------------|
| When | On a **running Armbian** host; blank SD/eMMC as target | **At image build** (`kiwi-ng` + `editbootinstall_odroid_hc4.sh`) |
| Bootloader | `dd` first N sectors from stock `.img` to target | Armbian **`u-boot.bin`** @ LBA 0 / sector 1 on `.raw` |
| Boot partition | **ext4** ~400 MiB, label `CRYPTO_BOOT`, `/boot` contents copied | **FAT32** 512 MiB `BOOT`, kernel/initrd/dtb/extlinux on FAT |
| Root | **LUKS on p2**, `ext4` on `/dev/mapper/rootfs` | **btrfs** (+ Snapper) on p3, unencrypted |
| Boot config | `armbianEnv.txt` **or** extlinux `root=/dev/mapper/rootfs` | extlinux `root=LABEL=ROOT` (patched post-build) |
| Initramfs | **Debian `initramfs-tools`** + `update-initramfs` | **dracut** (kiwi), patched by `patch-hc4-initrd.sh` |
| Unlock | `crypttab` + **`cryptsetup-initramfs`**; optional **`dropbear-initramfs`** (SSH :2222, `cryptroot-unlock`) | Not implemented; target **dracut `crypt`** + optional network unlock via dracut/network (different packages) |
| Resize | `touch .no_rootfs_resize` on Armbian | `rockstor-hc4-expand-root.service` grows p3 + btrfs |

### Can we apply it to our HC4 **image build**?

**Same goal, different implementation — do not run the tutorial verbatim on a Rockstor image.**

- **Applies in principle:** unencrypted boot + LUKS root; unlock in **initrd** before real root; extlinux only passes `root=` to the mapper (or btrfs inside LUKS after unlock). HC4 being on MMGen’s board list supports that **U-Boot + extlinux + LUKS mapper** works on this hardware.
- **Does not apply step-for-step:**
  - OS is **openSUSE Tumbleweed**, not Armbian — no `apt`, no `initramfs-tools`, no `armbianEnv.txt`, no `dropbear-initramfs` without porting to dracut/initrd.
  - Partition layout is **MBR p1 BOOT / p2 SWAP / p3 ROOT**, not two-partition Armbian layout; root is **btrfs** with `@/.snapshots/1/snapshot`, not ext4.
  - Our initrd is **dracut** on FAT `/boot`; Armbian stores initrd under ext4 `/boot` and regenerates with `update-initramfs`.
  - Build-time path should use **KIWI `luks=` + `bootpartition="true"`** ([design above](#recommended-luks-model-for-hc4)), not loop-mount + manual `rsync` from an Armbian `.img`.

**Equivalent mapping (what to implement in this repo instead of MMGen steps):**

| MMGen / Armbian | Rockstor HC4 encrypt-root branch |
|-----------------|----------------------------------|
| `cryptsetup luksFormat` + `luksOpen` on root partition | KIWI `luks` / `luks_version` on `Tumbleweed.OdroidHC4` |
| `etc/crypttab` (`initramfs,luks`) | Generated by kiwi into image; ensure dracut **`crypt`** includes it |
| extlinux `root=/dev/mapper/rootfs` | `rd.luks.uuid=…` + inner `root=` / `rootflags=subvol=…` in extlinux **append** (update `patch-hc4-extlinux-root.sh`) |
| `initramfs.conf` `IP=` / `DEVICE=` for SSH unlock | dracut **network** + optional **dropbear** in initrd (non-trivial on openSUSE; serial `ttyAML0` prompt is simpler first milestone) |
| `dropbear-initramfs` + `authorized_keys` | Optional later; not in current kiwi packages |
| `.no_rootfs_resize` | Disable conflicting kiwi repart (already); extend **`rockstor-hc4-expand-root`** for `cryptsetup resize` |

**Optional third path (not kiwi-native):** run a **post-flash migration** script on a live HC4 (inspired by MMGen or `mmgen-geek-tools`) that repartitions, LUKS-formats p3, rsyncs btrfs, rewrites extlinux/fstab/crypttab, and runs **`dracut -f`** — similar to `scripts/migrate-hc4-disk-armbian-layout.sh` scope. Heavier and riskier than baking LUKS in kiwi, but closest to the forum workflow.

**Recommendation:** Prefer **KIWI LUKS + dracut crypt** for the installer `.raw` on `odroid-hc4-encrypt-root`; treat the Armbian tutorial as validation that **HC4 + extlinux + LUKS mapper** is feasible, and as a reference for **remote unlock** (dropbear) if we add it later on openSUSE/dracut.
