# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This is `rockstor-installer`: a [kiwi-ng](https://osinside.github.io/kiwi/) image
description (`rockstor.kiwi`) plus helper shell scripts used to build Rockstor
"Built on openSUSE" installer images. There is no long-running app/server; the
"application" is `kiwi-ng` consuming `rockstor.kiwi` (+ `config.sh`,
`pre_disk_sync.sh`, `editbootinstall_rpi.sh`) to produce installer ISOs/raw
images. See `README.md` for the full build matrix and profiles.

### Environment
The update script creates a Python venv at `kiwi-env/` (gitignored) with
`kiwi-ng` installed. Invoke it directly, e.g. `./kiwi-env/bin/kiwi-ng --version`.
Python 3.9+ is required; the VM ships 3.12.

### Fast config validation (use this to iterate on `rockstor.kiwi`)
`kiwi-ng` schema-validates the description when it loads it. To validate + model
the recipe without an actual build:
```
./kiwi-env/bin/python -c "from kiwi.xml_description import XMLDescription; from kiwi.xml_state import XMLState; d=XMLDescription('rockstor.kiwi'); x=d.load(); print('schema OK', x.get_name()); print('profiles', sum(len(g.get_profile()) for g in x.get_profiles())); print('pkgs', len(XMLState(x,['Leap16.0.x86_64'],'oem').get_system_packages()))"
```

### Lint
- Shell scripts: `shellcheck *.sh vagrant_env/*.sh` (install once with
  `sudo apt-get install -y shellcheck`) and `bash -n <script>`. Current scripts
  only emit info/style/warning items (e.g. `kiwi_iname`/`kiwi_*` are injected by
  kiwi at build time, `.kconfig`/`.profile` are sourced inside the image) — no
  real errors.
- XML: `xmllint --noout rockstor.kiwi _multibuild _constraints` (libxml2-utils is
  preinstalled).

### Important caveat: a full image build cannot run in this cloud VM
Do NOT expect `kiwi-ng ... system build` or `system boxbuild` to succeed here:
- `boxbuild` needs KVM, but there is no `/dev/kvm` in the VM.
- A native `system build` needs the target distro's package manager (`zypper`)
  on the host plus root and loop devices; the VM is Ubuntu without `zypper`, and
  a build also downloads multiple GB of openSUSE RPMs.
Do actual installer builds on an openSUSE host or a KVM-enabled machine as
described in `README.md` / `vagrant_env/README.md`. In the cloud VM, rely on the
schema validation + lint steps above to check changes to the recipe and scripts.
