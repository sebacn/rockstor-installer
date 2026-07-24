# Self-Hosted Pool WORKER image for building the aarch64 Rockstor profiles.
#
# This is NOT the managed Cloud Agent environment (see .cursor/Dockerfile +
# environment.json for that). It builds a Cursor Self-Hosted Pool *worker* image
# that runs on your own arm64 hardware (e.g. a Raspberry Pi 5) so kiwi-ng can
# build the aarch64 profiles (Tumbleweed.RaspberryPi5, Tumbleweed.OdroidHC4, *.RaspberryPi4,
# *.ARM64EFI) that cannot run on Cursor's managed x86_64 fleet.
#
# Build ON arm64 hardware (or cross-build with buildx --platform linux/arm64):
#   docker build -f .cursor/worker.Dockerfile -t rockstor-worker:arm64 .cursor
#
# Pi5 installer build inside that image (privileged, host /dev for loop partitions):
#   ./.cursor/run-pi5-kiwi-build.sh
# See README.md "Tumbleweed.RaspberryPi5 profile" → Docker on Raspberry Pi 5.
#
# Run as a Self-Hosted Pool worker (requires a Cursor Enterprise plan, a service
# account API key, and admin-enabled self-hosted settings). Route work to it
# from GitHub with:  @cursoragent pool=rockstor-arm64 <task>
#
# openSUSE Tumbleweed (aarch64) matches the README's Pi5/Tumbleweed build host.
FROM opensuse/tumbleweed

# Base tooling + kiwi-ng + kiwi build deps (native aarch64 via zypper), plus the
# git/curl/tar the Cursor worker + repo clone need.
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
        python3-kiwi \
        ShellCheck \
        shadow \
        sudo \
        tar \
        which \
        xz \
        btrfsprogs \
        qemu-tools \
        gptfdisk \
        e2fsprogs \
        squashfs \
        xorriso \
        dosfstools \
        binutils \
        device-mapper \
        kpartx \
        parted \
        systemd \
        util-linux \
        util-linux-systemd \
        pam_pwquality \
    && zypper clean --all

# Non-root worker user with passwordless sudo (Cursor convention).
RUN (id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu) \
    && echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu \
    && chmod 0440 /etc/sudoers.d/ubuntu

USER ubuntu
ENV PATH="/home/ubuntu/.local/bin:${PATH}"

# Cursor agent CLI, installed as the worker user so the `agent`/`cursor-agent`
# symlinks land in /home/ubuntu/.local/bin (the install script supports arm64).
RUN curl -fsS https://cursor.com/install | bash

# The worker must be started from a pre-cloned repo working dir, e.g.:
#   git clone https://github.com/<you>/rockstor-installer.git /home/ubuntu/repo
#   agent worker --pool --pool-name rockstor-arm64 --worker-dir /home/ubuntu/repo start
