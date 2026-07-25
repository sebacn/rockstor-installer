#!/bin/bash

# https://osinside.github.io/kiwi/concept_and_workflow/shell_scripts.html
# "The pre_disk_sync.sh can be used to change content of the root tree
# as a last action before the sync to the disk image is performed."

#======================================
# SELinux config - if installed
#--------------------------------------
# `enforcing=0` for permissive (default), 1 for enforcing
selinuxcmdline=('security=selinux' 'selinux=1')
# SELinux kernel options added to rockstor.kiwi image.preferences.type kernelcmdline= entries.
if [[ -e /etc/selinux/config ]]; then
    # SELinux config
    sed -i -e 's|^SELINUX=.*|SELINUX=permissive|g' \
           -e 's|^SELINUXTYPE=.*|SELINUXTYPE=targeted|g' \
           "/etc/selinux/config"
    echo "-- /etc/selinux/config updated -----"
    # Grub kernel cmdline additions
    if [[ -e /etc/default/grub ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"|&${selinuxcmdline[*]} |" /etc/default/grub
        echo "-- /etc/default/grub updated -------"
    fi
    # Sysconfig bootloader cmdline additions (installer boot)
    if [[ -e /etc/sysconfig/bootloader ]]; then
        sed -i "s|^DEFAULT_APPEND=\"|&${selinuxcmdline[*]} |" /etc/sysconfig/bootloader
        sed -i "s|^FAILSAFE_APPEND=\"|&${selinuxcmdline[*]} |" /etc/sysconfig/bootloader
        echo "-- /etc/sysconfig/bootloader updated"
    fi
    # Update kiwi-ng's bootoptions config file used by dracut
    if [[ -e /config.bootoptions ]]; then
        sed -i "1 s|.|${selinuxcmdline[*]} &|" /config.bootoptions
        echo "-- /config.bootoptions updated -----"
    fi
fi

#======================================
# Symlinks -> regular files before kiwi disk sync (Docker rsync EPERM)
# Skip directory targets — copying them balloons the chroot and fills /var/tmp during sync.
#--------------------------------------
materialize_symlink() {
    local link=$1
    [[ -n "$link" && -L "$link" ]] || return 0
    local target
    target=$(readlink -f "$link" 2>/dev/null || true)
    if [[ -z "$target" || ! -f "$target" ]]; then
        return 0
    fi
    rm -f "$link"
    cp -a "$target" "$link"
    echo "-- materialized symlink: $link"
}

for search_root in /boot /usr/lib/modules; do
    [[ -d "$search_root" ]] || continue
    find "$search_root" -type l 2>/dev/null | while IFS= read -r link; do
        materialize_symlink "$link"
    done
done
