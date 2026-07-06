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
Several profiles are aarch64 (`*.RaspberryPi4/5`, `*.ARM64EFI`). kiwi will refuse
them on an x86_64 host, e.g.:
`KiwiProfileNotFound: profile Leap16.0.ARM64EFI not found for host arch x86_64`.
Managed Cursor Cloud Agents do not expose a way to select CPU architecture (no
field in `environment.json`; the fleet is x86_64). To build/validate the aarch64
profiles you need an **arm64 host**, which on Cursor means a Self-Hosted arm64
pool or contacting Cursor support. The committed Dockerfile is arch-agnostic, so
on an arm64 host it would produce the aarch64 toolchain automatically.

### Fast config validation (use this to iterate on `rockstor.kiwi`)
`kiwi-ng` schema-validates the description when it loads it. To validate + model
the recipe without a full build (use an x86_64 profile on the x86_64 host):
```
python3.11 -c "from kiwi.xml_description import XMLDescription; from kiwi.xml_state import XMLState; x=XMLDescription('rockstor.kiwi').load(); print('schema OK', x.get_name()); print('profiles', sum(len(g.get_profile()) for g in x.get_profiles())); print('pkgs', len(XMLState(x,['Leap16.0.x86_64'],'oem').get_system_packages()))"
```

### Lint
- Shell scripts: `shellcheck *.sh vagrant_env/*.sh` and `bash -n <script>`
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
