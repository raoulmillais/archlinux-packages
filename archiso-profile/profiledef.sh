#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="raoul-archlinux"
iso_label="RAOUL_ARCH_$(date +%Y%m)"
iso_publisher="Raoul's Arch Linux <https://raoulmillais.com"
iso_application="Raoul's Arch Linux Installer"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
