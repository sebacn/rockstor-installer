# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This is `rockstor-installer`: a [kiwi-ng](https://osinside.github.io/kiwi/) image
description (`rockstor.kiwi`) plus helper shell scripts used to build Rockstor
"Built on openSUSE" installer images. There is no long-running app/server; the
"application" is `kiwi-ng` consuming `rockstor.kiwi` (+ `config.sh`,
`pre_disk_sync.sh`, `editbootinstall_rpi.sh`) to produce installer ISOs/raw
images. See `README.md` for the full build matrix and profiles.

### Environment (openSUSE host)
The Cloud Agent environment is defined by `.cursor/environment.json` +
`.cursor/Dockerfile`, which is the source of truth. It is an **openSUSE Leap
15.6** image (the README-recommended native build host) with `kiwi-ng`
(`python311-kiwi`) and kiwi's build dependencies installed via `zypper`, matching
`vagrant_env/initial_prep.sh`. `kiwi-ng` is on `PATH`; run `kiwi-ng --version`.
The agent runs as the non-root `ubuntu` user with passwordless `sudo`.

- To change/refresh dependencies, edit `.cursor/Dockerfile` (not a snapshot).
- Because the base image is openSUSE (not Debian/Ubuntu), Cursor **Computer Use
  (desktop/browser GUI testing) is not available** here; use terminal-driven
  workflows. This is a documented Cursor constraint for non-Ubuntu images.

### Architecture caveat (arm64 is NOT available on managed Cloud Agents)
Several profiles are aarch64 (`*.RaspberryPi4/5`, `Tumbleweed.OdroidHC4`, `*.ARM64EFI`). kiwi will refuse
them on an x86_64 host, e.g.:
`KiwiProfileNotFound: profile Leap16.0.ARM64EFI not found for host arch x86_64`.
Managed Cursor Cloud Agents do not expose a way to select CPU architecture (no
field in `environment.json`; the fleet is x86_64). To build/validate the aarch64
profiles you need an **arm64 host** (a Self-Hosted Pool worker on arm64
hardware, e.g. a Raspberry Pi 5) — see below.

### arm64 builds via a Self-Hosted Pool worker (e.g. Raspberry Pi 5)
Self-Hosted Pool workers do NOT require Kubernetes — a single Docker host (or a
bare `agent` process under `systemd`/`tmux`) is a supported footprint, so a Pi 5
can run one. `.cursor/worker.Dockerfile` builds such a worker image: openSUSE
Tumbleweed (aarch64) + `python3-kiwi` + kiwi build deps + the Cursor `agent` CLI
(its installer supports arm64). On a real arm64 host kiwi can select and build
the aarch64 profiles that are impossible on the managed x86_64 fleet.

Prerequisites (from Cursor docs): a Cursor **Enterprise** plan, a **service
account API key**, and admin-enabled self-hosted settings. Pool selection is via
dashboard settings + labels + trigger hints (e.g. GitHub `@cursoragent
pool=<name>`), NOT via `.cursor/environment.json`.

Build + run on the Pi 5 (or cross-build with `buildx --platform linux/arm64`):
```
docker build -f .cursor/worker.Dockerfile -t rockstor-worker:arm64 .cursor
git clone <your-fork>/rockstor-installer.git ~/repo
agent worker --pool --pool-name rockstor-arm64 --worker-dir ~/repo start
```

Pi 5 caveats: 4 cores / 4–8 GB RAM and SD/USB storage are enough to run the
`agent` process and validate configs, but a *full* `kiwi-ng system build` is
disk- and CPU-heavy (15 GB+), needs root + loop devices (and boxbuild needs
`/dev/kvm`), so use fast SSD/NVMe storage and expect long build times.

**Pi5 installer build in Docker on the Pi host:** use `.cursor/run-pi5-kiwi-build.sh`
after `docker build -f .cursor/worker.Dockerfile -t rockstor-worker:arm64 .cursor`.
The script runs a privileged container with `-v /dev:/dev` and `loop max_part=8`
so kiwi can create `/dev/loop0p1` (otherwise `KiwiMappedDeviceError`). It also
removes `$ROCKSTOR_KIWI_TARGET/build` before each run (`KiwiRootDirExists`). Set
`ROCKSTOR_KIWI_TARGET` to a filesystem with 15 GB+ free. Details: README
Tumbleweed.RaspberryPi5 → Docker on Raspberry Pi 5.

### Fast config validation (use this to iterate on `rockstor.kiwi`)
`kiwi-ng` schema-validates the description when it loads it. To validate + model
the recipe without a full build (use an x86_64 profile on the x86_64 host):
```
python3.11 -c "from kiwi.xml_description import XMLDescription; from kiwi.xml_state import XMLState; x=XMLDescription('rockstor.kiwi').load(); print('schema OK', x.get_name()); print('profiles', sum(len(g.get_profile()) for g in x.get_profiles())); print('pkgs', len(XMLState(x,['Leap16.0.x86_64'],'oem').get_system_packages()))"
```

### Lint
- Shell scripts: `shellcheck *.sh .cursor/run-pi5-kiwi-build.sh vagrant_env/*.sh` and `bash -n <script>`
  (ShellCheck is in the image). Current scripts only emit info/style/warning
  items (e.g. `kiwi_iname`/`kiwi_*` are injected by kiwi at build time,
  `.kconfig`/`.profile` are sourced inside the image) — no real errors.
- XML: `xmllint --noout rockstor.kiwi _multibuild _constraints` (libxml2-tools).

### Important caveat: a full image build may not run in the managed container
`kiwi-ng ... system boxbuild` needs KVM (`/dev/kvm`), which is not present. A
native `kiwi-ng ... system build` needs root plus loop devices, which a managed
(non-privileged) container may not provide, and it downloads multiple GB of
openSUSE RPMs. Do real installer builds on a dedicated openSUSE/KVM host (or the
`vagrant_env/` flow) per `README.md`. In the cloud VM, rely on the schema
validation + lint steps above to check changes to the recipe and scripts.
