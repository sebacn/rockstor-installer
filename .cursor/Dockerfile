# Rockstor installer dev environment: an openSUSE host with kiwi-ng.
#
# This mirrors the README "dedicated openSUSE installation" build host and the
# vagrant_env/initial_prep.sh recipe, so kiwi-ng runs natively with zypper.
#
# NOTE ON ARCHITECTURE: Cursor Cloud Agents do not expose a way to pick the host
# CPU architecture, so this image is built for whatever the managed fleet
# provides (currently x86_64/amd64). It is arch-agnostic (no hardcoded arch), so
# on an arm64/aarch64 host it would build the aarch64 toolchain. To actually run
# on arm64 hardware you need a Self-Hosted arm64 pool or Cursor support (see
# AGENTS.md). openSUSE base images are outside Cursor's documented Computer Use
# support (Debian/Ubuntu only), so desktop/browser (GUI) testing is unavailable
# here; terminal-driven workflows work normally.
FROM opensuse/leap:15.6

# Base tooling the Cloud Agent expects, plus lint/validation helpers.
RUN zypper --non-interactive --gpg-auto-import-keys refresh \
    && zypper --non-interactive install --no-recommends \
        bash \
        ca-certificates \
        curl \
        gawk \
        git \
        gzip \
        libxml2-tools \
        openssh \
        python311 \
        python311-pip \
        ShellCheck \
        shadow \
        sudo \
        tar \
        which \
        xz \
    && zypper clean --all

# kiwi-ng and its build dependencies from the Appliances:Builder repo,
# matching vagrant_env/initial_prep.sh (Leap 15.6 host -> python311-kiwi).
RUN zypper --non-interactive addrepo --refresh \
        https://download.opensuse.org/repositories/Virtualization:/Appliances:/Builder/openSUSE_Leap_15.6/ \
        appliance-builder \
    && zypper --non-interactive --gpg-auto-import-keys refresh \
    && zypper --non-interactive install --no-recommends \
        python311-kiwi \
        btrfsprogs \
        gfxboot \
        qemu-tools \
        gptfdisk \
        e2fsprogs \
        squashfs \
        xorriso \
        dosfstools \
        binutils \
    && zypper clean --all

# Cursor Cloud Agent convention: a non-root "ubuntu" user with passwordless sudo.
RUN (id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu) \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu
