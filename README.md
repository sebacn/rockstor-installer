
# Rockstor "Built on openSUSE" Installer Recipe

This repo contains the [kiwi-ng](https://github.com/OSInside/kiwi) configuration used to create Rockstor 'Built on openSUSE' installers.
Please see the excellent [kiwi ng docs](https://osinside.github.io/kiwi/) for configuration options.

Pull requests are most welcome; especially new target system profiles.
Please test your modifications on all affected profiles prior to submission and provide details of how you tested the resulting installer.

## License:

The Rockstor installer configuration, this repo, is developed under the following licensing:

* [GPL-3.0-or-later](https://www.gnu.org/licenses/gpl-3.0-standalone.html)
* Additional licenses for the included Rockstor custom grub theme: [MIT](https://opensource.org/license/mit-0) AND [CC-BY-SA-3.0](https://creativecommons.org/licenses/by-sa/3.0/)

Making the repository license, overall, as per the **Fedora Project Wiki**:
[Packaging:LicensingGuidelines](https://fedoraproject.org/wiki/Packaging:LicensingGuidelines#Mixed_Source_Licensing_Scenario):

* **"GPL-3.0-or-later AND (MIT AND CC-BY-SA-3.0)"**

*Note: All additional software mentioned below that needs to be installed to make this installer configuration operational,
as well as software installed as part of the installer build, and its use, is subject to the individual projects' licensing terms.*

See the [SPDX License List](https://spdx.org/licenses) for details on the above assertions.

## Profile Anatomy
Profiles are named after their upstream distribution base, i.e. openSUSE Leap version,
and then the intended target system; with the two elements separated by a ".".

The "target system" element is either generic, i.e. **x86_64** or **AArch64**, or target system specific, i.e. **RaspberryPi4/5**, or **ARM64EFI**.
With the latter ARM64EFI spanning both generic (Arm64) and specific (64 bit EFI).

## Core Profiles
Our current pre-built installers are built using the following profiles (see: [Downloads](https://rockstor.com/dls.html)):

- **Leap16.0.x86_64**
- **Leap16.0.RaspberryPi4**
- **Leap16.0.ARM64EFI**
- **Slowroll.x86_64**
- **Tumbleweed.x86_64**
- **Tumbleweed.RaspberryPi4**
- **Tumbleweed.ARM64EFI**

Experimental Profiles:
- **Tumbleweed.RaspberryPi5**
- **Tumbleweed.OdroidHC4** (MBR + U-Boot; Hardkernel ODROID-HC4)

### RaspberryPi USB boot
USB booting on the Pi 4 may require a bootloader update via a fully updated Raspberry OS.
Pi4 EEPROM/bootloader version "Jun 15 2020" or later will be required for USB boot, regardless of any installer/EFI file changes.
For the Pi 5 apply the latest bootloader available, as this is still in active development.

### Special mention
- ARM64EFI

We are fortunate & thankful to have had contributions from/for the innovative [Traverse Ten64](https://www.crowdsupply.com/traverse-technologies/ten64) AArch64 platform.
[Traverse technologies](https://traverse.com.au/) have been instrumental in achieving our initial AArch64 compatibility aims.
The resulting installer is intended to support 64-bit ARM systems that implement the [Embedded Boot](https://github.com/ARM-software/ebbr) or [Server boot](https://github.com/ARM-software/sbsa-acs) standard.
Note that additional drives may be required for your specific hardware,
if so consider [Installing the Stable Kernel Backport](https://rockstor.com/docs/howtos/stable_kernel_backport.html).
Also see the following subsection for enabling these same repositories/facilities within the resulting installer itself.

## Contributing a Profile
If you would like to add a specific target system installer profile,
please take a look at the [examples](https://github.com/OSInside/kiwi-descriptions) referenced in the second link above.
The `rockstor.kiwi` file itself also contains comments with links to example configs used during its development. 
We can make no promises for the 'supported' status of any additional profiles,
but '[The Rockstor Project](https://rockstor.com/about-us.html)' will endeavour to make available the more popular resulting installers.
See our [Community Contributions](https://rockstor.com/docs/contribute_section.html) doc section for an overview to contributing,
and the [howto subsection](#howto) below to test proposed changes. 

## HOWTO

Please see the [kiwi-ng docs overview](https://osinside.github.io/kiwi/overview.html) for the canonical
[System Requirements](https://osinside.github.io/kiwi/overview.html#system-requirements) for building the installer:
e.g. 15 GB free space, Python version, etc.
It is recommended to use at least kiwi-ng v10.3.0 to build our [Core Profiles](#core-profiles).

Given our profiles' target OSs are exclusively 'Built on openSUSE',
a vanilla openSUSE Leap 15.6 instance is recommended if not using the kiwi-ng boxbuild method.
But if the newer kiwi-ng boxbuild method in "Building on any linux host... " is used,
any relatively modern linux system can be used to build the installer.

### rockstor-installer local copy

In order to build the installer you need a local copy of the [rockstor-installer](https://github.com/rockstor/rockstor-installer) GitHub repository.
This README.md file is part of that repository.
To get this copy you simply need to 'git clone' that repository to your local openSUSE instance:

```shell
zypper in git
git clone https://github.com/rockstor/rockstor-installer.git
cd rockstor-installer/
```  

The above commands install the 'git' program, and use it to 'clone' (read copy locally) the GitHub repo,
before setting your working directory to be inside this local copy.
Now you just need the kiwi-ng program this config requires to make the actual installer. 

### Building on any linux host (KVM support required)
Kiwi now has support for using KVM virtual machines to build in an isolated environments, regardless of the linux host.

With the release of version 10.x of `kiwi ng` the minimum required python version is now `3.9` or higher.
On any linux platform with KVM virtualization enabled and the corresponding python3 version,
you can use an isolated python virtual environment to build the installer without modifying your host OS,
or needing to manually set up an openSUSE virtual machine (see below for this alternative).
This boxbuild approach does have some overheads compared to building on a baremetal installation,
but on reasonably powerful hardware it can still take less than twenty minutes.

By default, the kiwi-boxed-plugin will reserve 8GB of memory, and 4 CPU cores.
This can be modified with `--box-memory=<vm>G --box-smp-cpus=<number>`, e.g., `--box-memory 4G --box-smp-cpus=2`.
On machines with low RAM, building with as low as 1GB has been tested successfully.
Assigning too much RAM will crash your host, so be sure to set a safe amount smaller than your current available host ram.
Arguments before the `--` are passed to boxbuild, and after are passed to the kiwi-ng build itself.

**Note on using a host OS within a Virtual Machine:**
If using a Linux OS in a Virtual Machine,
any shared folders from the host are not properly recognized by the KVM/QEMU that is generated by `kiwi-ng`'s boxbuild approach.
This can lead to `chroot` errors and terminate the installer generation.
The recommendation in this case is to clone the installer git directly into the VM directory,
and edit the relevant files (e.g., `rockstor.kiwi`) before executing the box build.
Or to edit them outside of the VM and transfer them back into the VM's installer directory using a shared folder.
At the end of installer creation the `.iso` file must then be copied from within the VM directory back onto the VM's host for further use.

**Note on `pip` usage:**
Some distros might still have a split between Python 2.x/3.x usage of `pip` (i.e. pip3 vs. pip),
or an existing system that is being used had both installed over time.
If that is the case, one wants to ensure that the 3.x version is used, by explicitly declaring `pip3` in the below command line. 
Otherwise, this can lead to execution errors down the line.

```shell
python3 -m venv kiwi-env
```

**Note on virtual environment with a specific python3 version:**
In case multiple python3 versions are installed (e.g., 3.11 was added to enable the usage of `kiwi`),
the `venv` should be created using the specific version.
Otherwise, the kiwi and box-plugin versions will revert to a lower version than 10x.
Therefore, unless the higher python3 version has been set up to be the default version,
the virtual environment should be created (using the example of version `3.11`):

```shell
python3.11 -m venv kiwi-env
```

If the system/distro has dropped python 2.x support, or if it is not installed on the system that is used for the build:
```shell
./kiwi-env/bin/pip install kiwi kiwi-boxed-plugin
```
Or go with the explicit version 3.x of pip:
```shell
./kiwi-env/bin/pip3 install kiwi kiwi-boxed-plugin
```
The rest remains the same (make sure to consider the memory and CPU defaults mentioned above)
```shell
./kiwi-env/bin/kiwi-ng --profile=Leap15.6.x86_64 --type oem \
  system boxbuild --box leap -- --description ./ --target-dir ./images
```

### For building on dedicated openSUSE installations
This was the preferred method before the above kiwi-ng boxbuild capability existed.

#### kiwi-ng install
For an openSUSE Leap 15.6 OS from kiwi-ng's doc [Installation](https://osinside.github.io/kiwi/installation.html#installation) section we have:

#### x86_64 host for x86_64 profiles
Any x86_64 machine, keeping in mind that building an installer is computationally expensive,
so systems with a decent-sized CPU/RAM combination released in the last 5-7 years is recommended.

##### Host with Leap 16.x or Tumbleweed
As the newer distributions already have the required python3 versions,
just add the the required repository as per distribution (for Slowroll use `openSUSE_Tumbleweed` as well):

e.g. for 16.0:
```shell
sudo zypper addrepo https://download.opensuse.org/repositories/Virtualization:/Appliances:/Builder/openSUSE_LEAP_16.0/ appliance-builder
```

and install kiwi and the additional requirements as shown below:

```shell
sudo zypper install python3-kiwi btrfsprogs qemu-tools gptfdisk e2fsprogs squashfs xorriso dosfstools binutils
```

##### Host with Leap < 16.0
The openSUSE host version should ideally be at least the version of the target profile.
Since older Leap versions (EOL) can ship with a default python version that is less than the minimum requirement of `python 3.9`,
it is necessary to install a higher python version (e.g., `3.13`):

```shell
sudo zypper in python313
```

then add the required repository, e.g.

for 15.6

```shell
sudo zypper addrepo https://download.opensuse.org/repositories/Virtualization:/Appliances:/Builder/openSUSE_Leap_15.6/ appliance-builder
```

Then proceed to install kiwi and the additional requirements as above.

#### AArch64 host (e.g. a Pi4) for AArch64 profiles
See [HCL:Raspberry Pi4](https://en.opensuse.org/HCL:Raspberry_Pi4).
Install, for example, an appliance JeOS Leap 16.0 image as the host OS.
Enabling USB boot on older Pi4 systems will allow for the use of, for example, an SSD as the system drive which will massively speed up installer building.
See [Pi4 USB boot](#pi4-usb-boot).

### Edit rockstor.kiwi
No edit is required if you wish to use the generic installer filename and default rockstor package version (recommended).
To change these defaults edit all lines directly preceded by **<!--Change to ...** as per the **...** details given.
Our release infrastructure performs these same edits to set official installer filenames and rockstor package versions.

#### Stable Kernel Backport & matching btrfs-progs (only applicable for OpenSUSE LEAP < 16.0)
To enable the use of 'Stable Kernel Backport' and 'filesystems' repositories within our `rockstor.kiwi` config,
uncomment the corresponding repositories.
For more information about using the most recent kernels see
[Installing the Stable Kernel Backport](https://rockstor.com/docs/howtos/stable_kernel_backport.html).

#### Root disk LUKS encryption
If you want to enable LUKS encryption of the Root disk (where Rockstor is installed),
uncomment the relevant parameters available as example in the **Leap16.0.x86_64** profile.
This will enable `LUKS2` encryption and utilize PBKDF2, as grub does not yet support the more recent `argon2id` algorithm.

N.B.: The `luksformat` parameter's preceding hyphens have to be escaped to exist as a comment.
When adding more non-commented parameters,
the required double-hyphens can be inserted without escaping them to their Unicode character codes.

### Leap16.0.x86_64 profile
Executed, as the root user, in the directory containing this repository's `rockstor.kiwi` file.

```shell
kiwi-ng --profile=Leap16.0.x86_64 --type oem system build --description ./ --target-dir /home/kiwi-images/
```

### Leap16.0.RaspberryPi4 profile
Executed, as the root user, in the directory containing this repository's `rockstor.kiwi` file.

```shell
kiwi-ng --profile=Leap16.0.RaspberryPi4 --type oem system build --description ./ --target-dir /home/kiwi-images/
```
### Tumbleweed.RaspberryPi5 profile
Executed, as the root user, in the directory containing this repository's `rockstor.kiwi` file.

```shell
kiwi-ng --profile=Tumbleweed.RaspberryPi5 --type oem system build --description ./ --target-dir /home/kiwi-images/
```

#### Docker build on Raspberry Pi 5 (`rockstor-worker:arm64`)

You can run the same `kiwi-ng` command inside the openSUSE Tumbleweed worker image
built from `.cursor/worker.Dockerfile`. This was validated on a Pi 5 host (July 2026).
Use a **target directory on a filesystem with at least ~15 GB free** (kiwi downloads
RPMs and writes a ~5 GB `.raw` plus a `build/` tree). If the root filesystem is
small, point output elsewhere, for example:

```shell
export ROCKSTOR_KIWI_TARGET=/mnt/bdata/kiwi-images
export ROCKSTOR_KIWI_LOG=/mnt/bdata/kiwi-build.log
# Optional: override zypper/kiwi RPM cache (default: /mnt/bdata/cache)
# export ROCKSTOR_KIWI_CACHE=/mnt/bdata/cache
# export ROCKSTOR_KIWI_CLEAR_CACHE=1   # wipe cache before the next build
```

**One-time:** build the worker image on the Pi (or `buildx --platform linux/arm64`):

```shell
docker build -f .cursor/worker.Dockerfile -t rockstor-worker:arm64 .cursor
```

**Each build:** from the repo root (requires `sudo` for Docker on most setups):

```shell
chmod +x .cursor/run-pi5-kiwi-build.sh
./.cursor/run-pi5-kiwi-build.sh
```

The helper script:

- loads `loop` with `max_part=8` on the host;
- removes any previous `$ROCKSTOR_KIWI_TARGET/build` tree (avoids `KiwiRootDirExists`);
- runs a **privileged** container with **`-v /dev:/dev`** and **`SYS_ADMIN`** so kiwi
  can create `/dev/loop0p1` while partitioning the disk image (without this, the build
  fails with `KiwiMappedDeviceError: Device /dev/loop0p1 does not exist`);
- bind-mounts the repo to `/workspace` and `$ROCKSTOR_KIWI_TARGET` to
  `/home/kiwi-images` (kiwi’s `--target-dir` inside the container);
- keeps a **shared zypper package cache** on the host (`$ROCKSTOR_KIWI_CACHE` or
  `/mnt/bdata/cache` unless overridden) via kiwi’s `--shared-cache-dir`,
  so a retry after `KiwiInstallPhaseFailed` can reuse downloaded RPMs (only
  `build/` and image artifacts are removed each run; set `ROCKSTOR_KIWI_CLEAR_CACHE=1`
  to refresh repository metadata).

Monitor progress:

```shell
tail -f "${ROCKSTOR_KIWI_LOG:-$HOME/kiwi-build.log}"
sudo docker ps -a --filter name=rockstor-pi5-build
```

On success the container exits `0` and the installer is
`$ROCKSTOR_KIWI_TARGET/Rockstor-NAS.aarch64-*.raw` (plus `.packages`, `.changes`,
`.verified`, and `kiwi.result`).

Since the rpi5 comes with a changed architecture and a new chip (BCM2712), it took quite some time to make it work for OpenSUSE.
Finally, at the end of 2025 openSUSE has started offering the first (Tumbleweed only) rpi5 images that can be written directly to the SD card using `rip imager` and boot them up.
The (wiki page)[https://en.opensuse.org/HCL:Raspberry_Pi5] is periodically updated with remaining issues and other news related to this porting effort.
In order to create a Rockstor Pi5 installer, it requires `kiwi-ng` to be run on actual pi5 hardware.
(So far, qemu/KVM based builds have been unsuccessful due to the boot section being markedly different from typical aarch64 builds).
After installing the OpenSUSE base image, and the above mentioned preparations (install packages on build host), a Rockstor `raw` image can be successfully built.
That image can then be written to the SD card using the graphical `rpi-imager` software (windows or linux).

Note: As of May 2026 there is no option to use Rockstor on the jeOS base image using the rpm installation method via zypper. The installation is successful,
but because the base images uses `ext4` as its file system and not btrfs, Rockstor will not allow for the setup to proceed.

### Tumbleweed.OdroidHC4 profile
Experimental installer for the [ODROID-HC4](https://wiki.odroid.com/odroid-hc4/start) (Amlogic S905X3). Unlike the Raspberry Pi profiles,
this uses an **MBR** partition table and **U-Boot** at sector 1 (not EFI/GPT). Kiwi is configured with `firmware="custom"`,
`force_mbr="true"`, a FAT **/boot** partition, and `editbootinstall_odroid_hc4.sh` to write U-Boot onto the raw disk.

The bootloader is **not** an openSUSE RPM: kiwi merges **`root/boot/u-boot.bin`** from the image description overlay.
Before each HC4 Docker build, **`scripts/fetch-uboot-odroid-hc4.sh`** downloads the latest Armbian
**`linux-u-boot-odroidhc4-current`** `.deb` (mainline **`odroid-hc4_defconfig`**, DT **`amlogic/meson-sm1-odroid-hc4.dtb`**)
from e.g. `https://fi.mirror.armbian.de/beta/pool/main/l/linux-u-boot-odroidhc4-current/`.
Pin a package with `ARMBIAN_UBOOT_DEB_URL=...`. Legacy openSUSE RPM fetch: `ROCKSTOR_UBOOT_SOURCE=opensuse`.
Host needs **`dpkg-deb`** to extract the Armbian package (Debian/Ubuntu: `dpkg`; openSUSE build host: install `dpkg`).
`editbootinstall_odroid_hc4.sh` writes the disk image using Armbian’s layout (442 bytes at LBA0 + payload at sector 1).

**Linux device tree on FAT /boot:** Armbian/U-Boot DT lists the SD slot as `amlogic,meson-sm1-mmc`, but openSUSE **`meson_gx_mmc`** does not bind that compatible (only gx/gxl/gxm/gxbb/axg). Without an explicit DTB, serial logs may show **Machine model: ODROID-C4**, no `mmcblk*`, and dracut waiting forever on the btrfs root UUID. **`scripts/build-hc4-linux-dtb.sh`** extracts the HC4 DT from the Armbian U-Boot image, retargets the MMC nodes to **`amlogic,meson-gxl-mmc`**, and installs **`root/boot/odroid-hc4.dtb`**. **`root/boot/extlinux/extlinux.conf`** loads it via **`fdt /odroid-hc4.dtb`**. Refresh an existing SD with **`sudo scripts/refresh-hc4-boot-partition.sh /dev/sdX`**.

**Btrfs / Snapper root subvolume:** Kiwi HC4 images use Snapper; the installed OS lives under **`@/.snapshots/1/snapshot`**, not the empty **`@`** subvolume. extlinux must use **`rootflags=subvol=@/.snapshots/1/snapshot`** (not `subvol=@`), or `switch_root` fails with *os-release file is missing* even when `mmcblk0p3` mounts. Do not set the btrfs default subvolume to bare `@` on migrated cards.

**DTB regulator / MMC deferral:** Patched **`odroid-hc4.dtb`** also drops SD **`vmmc-supply`/`vqmmc-supply`** (regulator GPIO chain can defer `ffe05000.mmc` indefinitely) and removes the GPIO line from **`regulator-vcc-5v`** (always-on 5V). Initrd includes a pre-mount retry hook for deferred MMC bind.

Set `ROCKSTOR_SKIP_UBOOT_FETCH=1` when invoking `.cursor/run-odroid-hc4-kiwi-build.sh` if `root/boot/u-boot.bin` is already present.
`scripts/build-uboot-odroid-hc4.sh` is a thin wrapper around the fetch script.

Build on **aarch64** openSUSE (or use the Docker helper on arm64 hardware with loop-partition support; see Pi5 Docker section).

```shell
kiwi-ng --profile=Tumbleweed.OdroidHC4 --type oem system build --description ./ --target-dir /home/kiwi-images/
```

Or from the repo root:

```shell
chmod +x .cursor/run-odroid-hc4-kiwi-build.sh
export ROCKSTOR_KIWI_TARGET=/path/with/15GB+free
./.cursor/run-odroid-hc4-kiwi-build.sh
```

The HC4 helper uses the same **zypper cache** behaviour as the Pi5 Docker script
(`ROCKSTOR_KIWI_CACHE`, `ROCKSTOR_KIWI_CLEAR_CACHE`; see Pi5 Docker section).

The resulting **`.raw`** image is written to the HC4 boot media (eMMC or microSD) with `dd` or similar. Verify boot on real HC4 hardware;
U-Boot is the Armbian pre-built **`linux-u-boot-odroidhc4-current`** package; partition layout follows Hardkernel/JeOS practice. This profile is not yet part of the upstream Rockstor download matrix.

#### HC4 boot loop: `BL33 CHK: 0xfffffff0` then `reset...`

The Amlogic mask ROM loads DDR firmware and BL33 (U-Boot) from the **boot medium** (microSD or eMMC). That message means BL33 failed verification and the board resets in a loop—Linux never starts.

1. **Boot medium** — Flash the `.raw` to **HC4 microSD** or **eMMC**, not a SATA disk. SATA drives are for data only. After `dd`, re-apply U-Boot on the card:
   ```shell
   chmod +x scripts/write-uboot-odroid-hc4-to-disk.sh
   sudo ./scripts/write-uboot-odroid-hc4-to-disk.sh /dev/mmcblk0   # or your SD device
   ```
2. **SPI flash** — If Petitboot or an old U-Boot is still in SPI, SD boot can fail or loop. Power off, insert only the SD card, hold the **recovery button** on the bottom while powering on to force SD boot. From a working Armbian/Ubuntu on HC4, erase SPI: `sudo flash_eraseall /dev/mtd0`, or install SPI U-Boot from the Armbian package (`u-boot-spi.bin` via `flashcp`, same as Armbian `nand-sata-install` → update bootloader on SPI).
3. **First boot** — Try **no SATA drives** attached until the installer boots once.
4. **Sanity check** — Confirm a current [Armbian HC4 image](https://www.armbian.com/odroid-hc4/) boots on the same board; if not, fix SPI/hardware before the Rockstor image.
5. **Pin U-Boot** — If a new Armbian `linux-u-boot-odroidhc4-current` package misbehaves, set `ARMBIAN_UBOOT_DEB_URL` to an older `.deb` when running `scripts/fetch-uboot-odroid-hc4.sh`, rebuild or re-run `write-uboot-odroid-hc4-to-disk.sh`.

Hardkernel’s layout reserves sectors **1–1919** for U-Boot; current Armbian `u-boot.bin` is larger and overlaps the FAT partition at LBA 2048—the post-`dd` U-Boot write must be the **last** step on the card (the kiwi image already does this once).

## Resulting Rockstor installers
With the above suggested `kiwi-ng` commands the resulting installers will be found in **/home/kiwi-images/** on the kiwi-ng host systems.

- For the x86_64 profiles the resulting installer is an ISO image intended for image transfer to an installer only device.
Use the file ending in ".iso".
- For the RaspberryPi 4 and 5 profiles the resulting installer is an uncompressed raw disk image intended for image transfer to the target system disk directly.
Use the file ending in ".raw".
- For **Tumbleweed.OdroidHC4** the installer is also a **`.raw`** disk image (MBR + U-Boot).

The resulting installs will grow on first boot to the size of their host devices.
All partitioning is fully automatic.

Please see [Rockstor’s “Built on openSUSE” installer](https://rockstor.com/docs/installer-howto/installer-howto.html) How-to for a user guide.

## Help or Assistance
Our [friendly forum](https://forum.rockstor.com/) is a good place to ask question regarding this How-to.
If you enable any of the above described enhancements i.e. backported kernel, LUKS, or add other options,
be sure to include those details when reporting any problems.
Please be patient as our support is community based and the above procedures are always in flux/development.

If you find an issue with these instructions, or the kiwi-ng config, please consider creating an issue and submitting a pull request with a proposed fix.

[The Rockstor Project](https://opencollective.com/the-rockstor-project) is an [Open Collective](https://opencollective.com/) Non-Profit/Non-Business Open Source community endeavour.
We are supported by our contributors, and fiscally hosted by [Open Source Europe (OSE)](https://opencollective.com/europe).
As such it depends on contributions for its sustainability.