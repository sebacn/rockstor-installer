
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

**extlinux `root=`:** The overlay template uses **`root=LABEL=ROOT`** (kiwi’s btrfs label). During **`editbootinstall_odroid_hc4.sh`**, **`scripts/patch-hc4-extlinux-root.sh`** rewrites `root=` from the actual ROOT partition on the built disk so dracut does not wait forever on a stale hard-coded UUID. Post-build **`scripts/validate-hc4-extlinux-root.sh`** checks the FAT `/boot` copy matches partition 3.

**`/etc/fstab` (swap, /boot):** Swap is **not** on the kernel cmdline (no dracut wait like `root=`). Kiwi still writes **`devicepersistency=by-uuid`** fstab lines; HC4 **`pre_disk_sync.sh`** rewrites **`/boot`**, **swap**, and **`/`** to **`LABEL=BOOT`**, **`LABEL=SWAP`**, and **`LABEL=ROOT`** so **`mkfs.vfat`** / **`mkswap -L SWAP`** in repair/migrate do not leave stale UUIDs. **`scripts/patch-hc4-fstab-labels.sh`** is used by **`repair-hc4-boot-fat.sh`** and **`migrate-hc4-disk-armbian-layout.sh`**.

**DTB regulator / MMC deferral:** Patched **`odroid-hc4.dtb`** drops the GPIO line from always-on **`regulator-vcc-5v`** and **`vin-supply`** on **`gpio-regulator-tf-io`** so a failed 5V GPIO probe does not defer **`ffe05000.mmc`** (do not remove MMC **`vmmc-supply`/`vqmmc-supply`** — that breaks SD voltage negotiation). Initrd includes a pre-mount retry hook for deferred MMC bind.

**DTB LAN (`end0`):** The external RTL8211 PHY sits on the G12A MDIO mux; **`reset-gpios`** / **`regulator-p12v-*` GPIO** can fail with **`-EPERM`** so **`g12a-mdio_mux`** never registers and **`end0`** logs *cannot attach to PHY*. The patched DTB removes those GPIO hooks, disables unused internal **`mdio@1`**, and drops duplicate **`snps,reset-*`** on **`ethernet@ff3f0000`**.

**Blue status LED:** Load **`ledtrig-heartbeat`** (`modprobe ledtrig-heartbeat`) so **`heartbeat`** appears in `/sys/class/leds/blue:status/trigger`; initrd and a **oneshot** systemd unit set the kernel **heartbeat** trigger only (no fast userspace blink fallback). Use `echo heartbeat | sudo tee …/trigger` on the running system to test.

Set `ROCKSTOR_SKIP_UBOOT_FETCH=1` when starting a Docker build if `root/boot/u-boot.bin` is already present and
`root/boot/.uboot-install-style` is `armbian`. `scripts/build-uboot-odroid-hc4.sh` is a thin wrapper around the fetch script.

#### Building on another aarch64 host

You can produce a new HC4 installer on **any machine** that meets the profile constraints. Nothing in the recipe is tied to a specific board; only **default paths** in the helper scripts may need overriding.

**Hard requirements**

| Requirement | Why |
|-------------|-----|
| **aarch64 CPU** | `Tumbleweed.OdroidHC4` is an `aarch64` kiwi profile. **x86_64 hosts cannot build it** (schema/lint only). Use arm64 hardware, a self-hosted pool worker (`.cursor/worker.Dockerfile`), or native openSUSE on aarch64. |
| **~15 GB+ free** on target and cache filesystems | RPM downloads, kiwi `build/` tree, and the `.raw` image. |
| **Network** | openSUSE/Rockstor repos plus Armbian `linux-u-boot-odroidhc4-current` `.deb`. |
| **Privileged build** | Native `kiwi-ng system build` needs loop devices; the Docker helper needs a **privileged** container, `-v /dev:/dev`, and `loop max_part=8` on the host (see Pi5 Docker section). |
| **`dpkg-deb` on the host** (Docker path) | `scripts/fetch-uboot-odroid-hc4.sh` runs **on the host before** the container starts to extract the Armbian package (Debian/Ubuntu: `dpkg`; openSUSE: install the `dpkg` package). |

**What is in git vs generated locally**

| Path | In repository? |
|------|----------------|
| `root/boot/extlinux/extlinux.conf` | yes |
| `root/boot/odroid-hc4.dtb` | yes (patched Linux-facing DTB) |
| `root/boot/u-boot.bin` | **no** (gitignored; run `scripts/fetch-uboot-odroid-hc4.sh` on each fresh clone) |
| `.build/uboot-odroid-hc4-fetch/` | **no** (gitignored; Armbian `.deb` extract cache) |

**Option A — Docker on arm64** (same `rockstor-worker:arm64` image as Pi5; validated on ODROID-HC4 / Pi 5 class hosts):

Use **system Docker** (`unix:///run/docker.sock`). **Rootless Docker** (`DOCKER_HOST` under `/run/user/...`) cannot run `kiwi-ng system build` (chroot `/proc` mount fails). The worker container must be **privileged**, with **`-v /dev:/dev`**, **`--pid=host`**, and host **`loop max_part=8`** so kiwi can map partitions (`kpartx` / `/dev/mapper/loop0p1`). Inside the container, **`scripts/hc4-kiwi-build-inner.sh`** applies the HC4 kiwi workarounds (msdos `disk_start_sector` patch, `part_mapper: kpartx`) before `kiwi-ng`.

**One-time:** clone, checkout the HC4 branch, build the worker image:

```shell
git clone https://github.com/rockstor/rockstor-installer.git
cd rockstor-installer
git checkout odroid-hc4   # or your feature branch

docker build -f .cursor/worker.Dockerfile -t rockstor-worker:arm64 .cursor
```

**Paths** (override if `/mnt/bdata` is not available; helpers default to `$HOME/...` when `/mnt/bdata` is missing):

```shell
export ROCKSTOR_KIWI_TARGET="$HOME/kiwi-images-hc4"
export ROCKSTOR_KIWI_CACHE="$HOME/kiwi-cache"
export ROCKSTOR_KIWI_VAR_TMP="$HOME/kiwi-var-tmp"
# Optional: export ROCKSTOR_KIWI_LOG="$HOME/kiwi-build-odroid-hc4.log"
export ROCKSTOR_UBOOT_SOURCE=armbian   # default; Armbian linux-u-boot-odroidhc4-current
```

**Recommended — full build via system Docker** (starts `docker` if needed, runs prepare/validate as your user, cleans stale `build/` + `.raw`, launches detached container `rockstor-odroid-hc4-build`):

```shell
sudo -E bash scripts/run-hc4-system-docker-build.sh
```

Optional: `ROCKSTOR_SKIP_WORKER_BUILD=1` if the image already exists; `ROCKSTOR_BUILD_USER=youruser` when `SUDO_USER` is unset.

**Alternative — same container without the sudo wrapper** (user must reach the system daemon, e.g. `docker` group + `DOCKER_HOST=unix:///run/docker.sock`):

```shell
chmod +x .cursor/run-odroid-hc4-kiwi-build.sh
# If you use rootless Docker by default, force system socket for this build:
export DOCKER_HOST=unix:///run/docker.sock
./.cursor/run-odroid-hc4-kiwi-build.sh
# Or: sg docker -c 'DOCKER_HOST=unix:///run/docker.sock ./.cursor/run-odroid-hc4-kiwi-build.sh'
```

Both entry points run **`scripts/prepare-hc4-build-host.sh --docker`** then **`scripts/validate-hc4-build-host.sh --docker`**, remove previous **`$ROCKSTOR_KIWI_TARGET/build`** and partial image artifacts, and start **`bash /workspace/scripts/hc4-kiwi-build-inner.sh build`** in the worker. Prepare creates output directories, installs **`curl`** / **`dpkg`** when possible, **re-fetches** Armbian **`root/boot/u-boot.bin`** (unless `ROCKSTOR_SKIP_UBOOT_FETCH=1`), **builds** `rockstor-worker:arm64` when missing, and can rebuild **`odroid-hc4.dtb`**. Debug pre-flight manually:

```shell
export ROCKSTOR_KIWI_TARGET="$HOME/kiwi-images-hc4"
export ROCKSTOR_KIWI_CACHE="$HOME/kiwi-cache"
export ROCKSTOR_KIWI_VAR_TMP="$HOME/kiwi-var-tmp"
export DOCKER_HOST=unix:///run/docker.sock
scripts/prepare-hc4-build-host.sh --docker
scripts/validate-hc4-build-host.sh --docker   # or --native before sudo kiwi-ng
```

| Variable | Default | Meaning |
|----------|---------|---------|
| `ROCKSTOR_KIWI_CONTAINER` | `rockstor-odroid-hc4-build` | Detached build container name |
| `ROCKSTOR_HC4_AUTO_PREPARE` | `1` | Run prepare step (set `0` to skip) |
| `ROCKSTOR_HC4_AUTO_BUILD_WORKER` | `1` | `docker build` worker image when missing |
| `ROCKSTOR_HC4_AUTO_INSTALL_HOST_DEPS` | `1` | `zypper`/`apt` install `curl`, `dpkg`, etc. |
| `ROCKSTOR_HC4_AUTO_BUILD_DTB` | `1` | Run `build-hc4-linux-dtb.sh` if DTB missing |
| `ROCKSTOR_SKIP_HC4_VALIDATE` | `0` | Skip validation only |
| `ROCKSTOR_SKIP_WORKER_BUILD` | `0` | Skip worker image build (`run-hc4-system-docker-build.sh` only) |

Set `ROCKSTOR_SKIP_HC4_VALIDATE=1` to bypass validation. Minimum free space defaults: **15 GB** target, **10 GB** cache, **5 GB** `ROCKSTOR_KIWI_VAR_TMP` (override with `ROCKSTOR_HC4_MIN_FREE_*_GB`).

**Monitor:**

```shell
docker logs -f rockstor-odroid-hc4-build
tail -f "${ROCKSTOR_KIWI_TARGET}/build/image-root.log"
docker inspect -f '{{.State.Status}} exit={{.State.ExitCode}}' rockstor-odroid-hc4-build
```

**Success:** container exit code **0**; **`$ROCKSTOR_KIWI_TARGET/Rockstor-NAS.aarch64-*.raw`** with multi‑GB actual size (`du -h`), plus **`.packages`**, **`.changes`**, **`.verified`**, **`kiwi.result`**. The inner build script runs **`scripts/validate-hc4-raw-uboot.sh`** on each `.raw` (Armbian bytes @ LBA0 + sector 1). Zypper cache behaviour matches the Pi5 Docker section (`ROCKSTOR_KIWI_CLEAR_CACHE`, `ROCKSTOR_KIWI_REFRESH_REPOS`).

#### Flashing the installer to microSD / USB (interactive helper)

**`scripts/flash-rockstor-image-to-disk.sh`** writes a kiwi **`.raw`** or **`.raw.xz`** image to a removable block device (USB SD reader → `/dev/sda`, `/dev/sdb`, …). It:

- lists images in a directory (default **`$HOME/kiwi-images-hc4`**, or **`ROCKSTOR_IMAGE_DIR`** / **`ROCKSTOR_KIWI_TARGET`**);
- decompresses **`.xz`** / **`.txz`** on the fly (`xz`; uses **`pv`** for decompression progress when installed);
- lists whole disks with size/model/transport, **excluding the host root disk**;
- unmounts target partitions, then runs **`dd`** with **`status=progress`**;
- asks you to type **`YES`** before erasing the card (skip with **`-y`**).

Requires **`dd`**, **`lsblk`**, **`findmnt`** (and **`xz`** for compressed images). If a command is missing, the script lists the **zypper** / **apt** packages and asks whether to install them (`ROCKSTOR_FLASH_AUTO_INSTALL_DEPS=1` or **`-y`** skips that prompt). Optional **`pv`** improves progress display for `.xz` flashes.

**Interactive** (from repo root, SD card attached via USB):

```shell
chmod +x scripts/flash-rockstor-image-to-disk.sh
sudo scripts/flash-rockstor-image-to-disk.sh
```

Pick the image number, then the destination disk, then confirm with **`YES`**.

**Non-interactive** example (same paths as the Docker build):

```shell
export ROCKSTOR_KIWI_TARGET="$HOME/kiwi-images-hc4"
sudo scripts/flash-rockstor-image-to-disk.sh \
  --image-dir "$ROCKSTOR_KIWI_TARGET" \
  --image "$ROCKSTOR_KIWI_TARGET/Rockstor-NAS.aarch64-5.5.3-0.raw" \
  --device /dev/sda \
  -y
```

**Compressed image:**

```shell
sudo scripts/flash-rockstor-image-to-disk.sh \
  --image-dir "$HOME/kiwi-images-hc4" \
  --image "$HOME/kiwi-images-hc4/Rockstor-NAS.aarch64-5.5.3-0.raw.xz" \
  --device /dev/sdb
```

Always verify the destination with **`lsblk`** before confirming—**`dd` overwrites the entire device**. Flash **HC4 boot media** (microSD or eMMC), not a SATA data disk.

New kiwi builds run **`scripts/validate-hc4-raw-uboot.sh`** on the `.raw` after build. The flash helper can verify U-Boot on the card after **`dd`** and offer **`scripts/apply-uboot-odroid-hc4-to-image.sh`** if an older image lacks it (`ROCKSTOR_FLASH_VALIDATE_UBOOT=0` to skip).

The kiwi post-install step writes U-Boot into the **`.raw` file** (not only the transient loop device); re-run **`scripts/write-uboot-odroid-hc4-to-disk.sh`** or **`scripts/apply-uboot-odroid-hc4-to-image.sh`** if you repaired a card without that step.

**Clean restart** (if a kiwi Docker run failed mid-way): both helpers already delete `build/` and partial outputs before starting; to wipe manually:

```shell
docker rm -f rockstor-odroid-hc4-build
docker run --rm --user 0:0 -v "$ROCKSTOR_KIWI_TARGET:/home/kiwi-images" rockstor-worker:arm64 \
  rm -rf /home/kiwi-images/build /home/kiwi-images/*.raw /home/kiwi-images/kiwi.result*
```

**Option B — Native openSUSE aarch64** (Leap 15.6 / Tumbleweed with `python3-kiwi` and build dependencies per `vagrant_env/` / README):

```shell
export ROCKSTOR_KIWI_TARGET=/path/with/15GB+free
scripts/prepare-hc4-build-host.sh --native
scripts/validate-hc4-build-host.sh --native
# Optional: refresh DTB from the same Armbian U-Boot package (needs device-tree-compiler / fdtput)
scripts/build-hc4-linux-dtb.sh

sudo kiwi-ng --profile=Tumbleweed.OdroidHC4 --type oem system build \
  --description ./ --target-dir "$ROCKSTOR_KIWI_TARGET"
```

**Notes**

- Committed **`odroid-hc4.dtb`** is enough for a successful build. Run **`scripts/build-hc4-linux-dtb.sh`** after **`fetch-uboot-odroid-hc4.sh`** if you want the DTB patches applied to the **same** Armbian U-Boot version you just fetched.
- Flash the **`.raw`** to HC4 **microSD or eMMC** (not a SATA disk). Prefer **`scripts/flash-rockstor-image-to-disk.sh`** (see above). The kiwi post-install step already writes U-Boot; re-run **`scripts/write-uboot-odroid-hc4-to-disk.sh`** only if you repaired the card without that step.
- **Cursor managed x86_64 cloud agents** cannot run this profile; use arm64 hardware or a self-hosted worker.

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