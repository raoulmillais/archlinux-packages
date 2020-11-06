#!/usr/bin/env bash
set -e

#
# START CONFIGURATION
#
CONF_FILE="arch-install.conf"
LOG_FILE="arch-install.log"

# system
DEVICE="/dev/nvme0n1" 
SWAP_SIZE=''
BIOS_TYPE="uefi"
DEVICE_NVME="true"
CPU_VENDOR="intel"

# network
WIFI_INTERFACE=""
WIFI_ESSID=""
WIFI_KEY=""
WIFI_HIDDEN=""
PING_HOSTNAME="mirrors.kernel.org"

PACMAN_MIRROR="https://mirrors.kernel.org/archlinux/\$repo/os/\$arch"

# config
TIMEZONE="/usr/share/zoneinfo/Europe/London"
LOCALES=("en_GB.UTF-8 UTF-8")
LOCALE_CONF=("LANG=en_GB.UTF-8" "LANGUAGE=en_GB:en")
KEYMAP="KEYMAP=uk"
KEYLAYOUT="gb"
FONT=""
FONT_MAP=""
HOSTNAME="raoul"

# user
USER_NAME="raoul"

DISPLAY_DRIVER="intel"

# packages (all multiple)
PACKAGES_PACMAN_INTERNET="firefox curl openssh transmission-gtk" 
PACKAGES_PACMAN_MULTIMEDIA="feh gimp inkscape vlc gstreamer gst-plugins-good gst-plugins-bad gst-plugins-ugly bluez bluez-utils"
PACKAGES_PACMAN_UTILITIES="dosfstools"
PACKAGES_PACMAN_DOCUMENTS_AND_TEXT="libreoffice-fresh neovim"
PACKAGES_PACMAN_SECURITY=""
PACKAGES_PACMAN_SCIENCE=""
PACKAGES_PACMAN_OTHERS="tmux"
PACKAGES_PACMAN_DEVELOPER="virtualbox docker vagrant"
PACKAGES_PACMAN_CUSTOM="alacritty rofi mate-power-manager alsa-utils exa zenith bat vifm ripgrep hub bind-tools coreutils dos2unixx fzf lsof"

AUR="yay"

PACKAGES_AUR="polybar rofi-dmenu nerdfonts-complete"

PACKAGES_PACMAN="$PACKAGES_PACMAN_INTERNET $PACKAGES_PACMAN_MULTIMEDIA $PACKAGES_PACMAN_UTILITIES $PACKAGES_PACMAN_DOCUMENTS_AND_TEXT $PACKAGES_PACMAN_SECURITY $PACKAGES_PACMAN_SCIENCE $PACKAGES_PACMAN_OTHERS $PACKAGES_PACMAN_DEVELOPER $PACKAGES_PACMAN_CUSTOM"

SYSTEMD_UNITS="docker.service bluetooth.service"
#
# END CONFIGURATION
#

RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHT_BLUE='\033[1;34m'
NC='\033[0m'

main() {
    warning
    init
    facts
    prepare
    partition
    install
    configuration
    mkinitcpio_configuration
    display_driver
    mkinitcpio
    network
    if [ "$VIRTUALBOX" == "true" ]; then
        virtualbox
    fi
    users
    bootloader
    setup_zsh
    desktop_environment
    packages
    systemd_units
    terminate
    end
}

function sanitize_variable() {
    VARIABLE=$1
    VARIABLE=$(echo $VARIABLE | sed "s/![^ ]*//g") # remove disabled
    VARIABLE=$(echo $VARIABLE | sed "s/ {2,}/ /g") # remove unnecessary white spaces
    VARIABLE=$(echo $VARIABLE | sed 's/^[[:space:]]*//') # trim leading
    VARIABLE=$(echo $VARIABLE | sed 's/[[:space:]]*$//') # trim trailing
    echo "$VARIABLE"
}

function pacman_install() {
    set +e
    IFS=' ' PACKAGES=($1)
    for VARIABLE in {1..5}
    do
        arch-chroot /mnt pacman -Syu --noconfirm --needed ${PACKAGES[@]}
        if [ $? == 0 ]; then
            break
        else
            sleep 10
        fi
    done
    set -e
}

function warning() {
    echo -e "${LIGHT_BLUE}Arch Linux Install${NC}"
    echo ""
    echo -e "${RED}Warning"'!'"${NC}"
    echo -e "${RED}This script deletes all partitions of the persistent${NC}"
    echo -e "${RED}storage all data will be lost.${NC}"
    echo ""
    read -p "Do you want to continue? [y/N] " yn
    case $yn in
        [Yy]* )
            ;;
        [Nn]* )
            exit
            ;;
        * )
            exit
            ;;
    esac
}

function facts() {
    print_step "facts()"

    DEVICE_NVME="true"
    CPU_VENDOR="intel"

    if [ -n "$(lspci | grep -i virtualbox)" ]; then
        VIRTUALBOX="true"
    fi
}

function prepare() {
    print_step "prepare()"

    timedatectl set-ntp true
    prepare_partition
    configure_network
    ask_passwords

    pacman -Sy
}

function prepare_partition() {
    if [ -d /mnt/boot ]; then
        umount /mnt/boot
        umount /mnt
    fi
    if [ -e "/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_LOGICAL" ]; then
        umount "/dev/mapper/$LVM_VOLUME_GROUP-$LVM_VOLUME_LOGICAL"
    fi
    if [ -e "/dev/mapper/$LUKS_DEVICE_NAME" ]; then
        cryptsetup close $LUKS_DEVICE_NAME
    fi
    partprobe $DEVICE
}

function configure_network() {
    if [ -n "$WIFI_INTERFACE" ]; then
        iwctl --passphrase "$WIFI_KEY" station $WIFI_INTERFACE connect $WIFI_ESSID
        sleep 10
    fi

    # only on ping -c 1, packer gets stuck if -c 5
    ping -c 1 -i 2 -W 5 -w 30 $PING_HOSTNAME
    if [ $? -ne 0 ]; then
        echo "Network ping check failed. Cannot continue."
        exit
    fi
}

function ask_passwords() {
    PASSWORD_TYPED="false"
    while [ "$PASSWORD_TYPED" != "true" ]; do
        read -sp 'Type LUKS password: ' LUKS_PASSWORD
        echo ""
        read -sp 'Retype LUKS password: ' LUKS_PASSWORD_RETYPE
        echo ""
        if [ "$LUKS_PASSWORD" == "$LUKS_PASSWORD_RETYPE" ]; then
            PASSWORD_TYPED="true"
        else
            echo "LUKS password don't match. Please, type again."
        fi
    done

    PASSWORD_TYPED="false"
    while [ "$PASSWORD_TYPED" != "true" ]; do
        read -sp 'Type root password: ' ROOT_PASSWORD
        echo ""
        read -sp 'Retype root password: ' ROOT_PASSWORD_RETYPE
        echo ""
        if [ "$ROOT_PASSWORD" == "$ROOT_PASSWORD_RETYPE" ]; then
            PASSWORD_TYPED="true"
        else
            echo "Root password don't match. Please, type again."
        fi
    done

    PASSWORD_TYPED="false"
    while [ "$PASSWORD_TYPED" != "true" ]; do
        read -sp 'Type user password: ' USER_PASSWORD
        echo ""
        read -sp 'Retype user password: ' USER_PASSWORD_RETYPE
        echo ""
        if [ "$USER_PASSWORD" == "$USER_PASSWORD_RETYPE" ]; then
            PASSWORD_TYPED="true"
        else
            echo "User password don't match. Please, type again."
        fi
    done
}

function partition() {
    print_step "partition()"

        PARTITION_PARTED_UEFI="mklabel gpt mkpart ESP fat32 1MiB 512MiB mkpart root $FILE_SYSTEM_TYPE 512MiB 100% set 1 esp on"
        PARTITION_PARTED_BIOS="mklabel msdos mkpart primary ext4 4MiB 512MiB mkpart primary $FILE_SYSTEM_TYPE 512MiB 100% set 1 boot on"

    if [ "$DEVICE_NVME" == "true" ]; then
        PARTITION_BOOT="${DEVICE}p1"
        PARTITION_ROOT="${DEVICE}p2"
        DEVICE_ROOT="${DEVICE}p2"
    fi

    if [ "$DEVICE_MMC" == "true" ]; then
        PARTITION_BOOT="${DEVICE}p1"
        PARTITION_ROOT="${DEVICE}p2"
        DEVICE_ROOT="${DEVICE}p2"
    fi

    PARTITION_BOOT_NUMBER="$PARTITION_BOOT"
    PARTITION_ROOT_NUMBER="$PARTITION_ROOT"
    PARTITION_BOOT_NUMBER="${PARTITION_BOOT_NUMBER//\/dev\/nvme0n1p/}"
    PARTITION_ROOT_NUMBER="${PARTITION_ROOT_NUMBER//\/dev\/nvme0n1p/}"

    sgdisk --zap-all $DEVICE
    wipefs -a $DEVICE

    parted -s $DEVICE $PARTITION_PARTED_UEFI
    sgdisk -t=$PARTITION_ROOT_NUMBER:8309 $DEVICE

    # luks
    echo -n "$LUKS_PASSWORD" | cryptsetup --key-size=512 --key-file=- luksFormat --type luks2 $PARTITION_ROOT
    echo -n "$LUKS_PASSWORD" | cryptsetup --key-file=- open $PARTITION_ROOT $LUKS_DEVICE_NAME
    sleep 5

    DEVICE_ROOT="/dev/mapper/$LUKS_DEVICE_NAME"

    # format
    wipefs -a $PARTITION_BOOT
    wipefs -a $DEVICE_ROOT
    mkfs.fat -n ESP -F32 $PARTITION_BOOT
    mkfs."$FILE_SYSTEM_TYPE" -L root $DEVICE_ROOT

    PARTITION_OPTIONS="defaults"
    PARTITION_OPTIONS="$PARTITION_OPTIONS,noatime,nodiscard"

    # mount
    mount -o "$PARTITION_OPTIONS" "$DEVICE_ROOT" /mnt
    btrfs subvolume create /mnt/root
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/var
    btrfs subvolume create /mnt/snapshots
    umount /mnt

    mount -o "subvol=root,$PARTITION_OPTIONS,compress=lzo" "$DEVICE_ROOT" /mnt

    mkdir /mnt/{boot,home,var,snapshots}
    mount -o "$PARTITION_OPTIONS" "$PARTITION_BOOT" /mnt/boot
    mount -o "subvol=home,$PARTITION_OPTIONS,compress=lzo" "$DEVICE_ROOT" /mnt/home
    mount -o "subvol=var,$PARTITION_OPTIONS,compress=lzo" "$DEVICE_ROOT" /mnt/var
    mount -o "subvol=snapshots,$PARTITION_OPTIONS,compress=lzo" "$DEVICE_ROOT" /mnt/snapshots

    # swap
    if [ -n "$SWAP_SIZE" ]; then
        truncate -s 0 /mnt$SWAPFILE
        chattr +C /mnt$SWAPFILE
        btrfs property set /mnt$SWAPFILE compression none

        dd if=/dev/zero of=/mnt$SWAPFILE bs=1M count=$SWAP_SIZE status=progress
        chmod 600 /mnt$SWAPFILE
        mkswap /mnt$SWAPFILE
    fi

    # set variables
    BOOT_DIRECTORY=/boot
    ESP_DIRECTORY=/boot
    UUID_BOOT=$(blkid -s UUID -o value $PARTITION_BOOT)
    UUID_ROOT=$(blkid -s UUID -o value $PARTITION_ROOT)
    PARTUUID_BOOT=$(blkid -s PARTUUID -o value $PARTITION_BOOT)
    PARTUUID_ROOT=$(blkid -s PARTUUID -o value $PARTITION_ROOT)
}

function install() {
    print_step "install()"

    echo "Server=$PACMAN_MIRROR" > /etc/pacman.d/mirrorlist

    sed -i 's/#Color/Color/' /etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /etc/pacman.conf

    pacstrap /mnt base base-devel linux linux-firmware

    sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf
}

function configuration() {
    print_step "configuration()"

    genfstab -U /mnt >> /mnt/etc/fstab

    if [ -n "$SWAP_SIZE" ]; then
        echo "# swap" >> /mnt/etc/fstab
        echo "$SWAPFILE none swap defaults 0 0" >> /mnt/etc/fstab
        echo "" >> /mnt/etc/fstab
    fi

    sed -i 's/relatime/noatime/' /mnt/etc/fstab
    arch-chroot /mnt systemctl enable fstrim.timer

    arch-chroot /mnt ln -s -f $TIMEZONE /etc/localtime
    arch-chroot /mnt hwclock --systohc
    for LOCALE in "${LOCALES[@]}"; do
        sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
        sed -i "s/#$LOCALE/$LOCALE/" /mnt/etc/locale.gen
    done
    for VARIABLE in "${LOCALE_CONF[@]}"; do
        #localectl set-locale "$VARIABLE"
        echo -e "$VARIABLE" >> /mnt/etc/locale.conf
    done
    locale-gen
    arch-chroot /mnt locale-gen
    echo -e "$KEYMAP\n$FONT\n$FONT_MAP" > /mnt/etc/vconsole.conf
    echo $HOSTNAME > /mnt/etc/hostname

    OPTIONS=""
    if [ -n "$KEYLAYOUT" ]; then
        OPTIONS="$OPTIONS"$'\n'"    Option \"XkbLayout\" \"$KEYLAYOUT\""
    fi

    arch-chroot /mnt mkdir -p "/etc/X11/xorg.conf.d/"
    cat <<EOT > /mnt/etc/X11/xorg.conf.d/00-keyboard.conf
# Written by systemd-localed(8), read by systemd-localed and Xorg. It's
# probably wise not to edit this file manually. Use localectl(1) to
# instruct systemd-localed to update it.
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    $OPTIONS
EndSection
EOT

    if [ -n "$SWAP_SIZE" ]; then
        echo "vm.swappiness=10" > /mnt/etc/sysctl.d/99-sysctl.conf
    fi

    printf "$ROOT_PASSWORD\n$ROOT_PASSWORD" | arch-chroot /mnt passwd
}

function mkinitcpio_configuration() {
    print_step "mkinitcpio_configuration()"

    MODULES=""
    case "$DISPLAY_DRIVER" in
        "intel" )
            MODULES="i915"
            ;;
        "nvidia")
            MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"
            ;;
    esac
    arch-chroot /mnt sed -i "s/^MODULES=()/MODULES=($MODULES)/" /etc/mkinitcpio.conf

    if [ "$DISPLAY_DRIVER" == "intel" ]; then
        OPTIONS=""
        if [ "$FASTBOOT" == "true" ]; then
            OPTIONS="$OPTIONS fastboot=1"
        fi
        if [ "$FRAMEBUFFER_COMPRESSION" == "true" ]; then
            OPTIONS="$OPTIONS enable_fbc=1"
        fi
        if [ -n "$OPTIONS"]; then
            echo "options i915 $OPTIONS" > /mnt/etc/modprobe.d/i915.conf
        fi
    fi

    if [ "$FILE_SYSTEM_TYPE" == "btrfs" ]; then
        pacman_install "btrfs-progs"
    fi

    HOOKS=$(echo $HOOKS | sed 's/!udev/udev/')
    HOOKS=$(echo $HOOKS | sed 's/!usr/usr/')
    HOOKS=$(echo $HOOKS | sed 's/!keymap/keymap/')
    HOOKS=$(echo $HOOKS | sed 's/!consolefont/consolefont/')
    HOOKS=$(echo $HOOKS | sed 's/!encrypt/encrypt/')
    HOOKS=$(sanitize_variable "$HOOKS")
    arch-chroot /mnt sed -i "s/^HOOKS=(.*)$/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf

    pacman_install "lz4"
}

function display_driver() {
    print_step "display_driver()"

    PACKAGES_DRIVER=""
    case "$DISPLAY_DRIVER" in
        "nvidia" )
            PACKAGES_DRIVER="nvidia"
            ;;
        "intel" )
            PACKAGES_DRIVER="xf86-video-intel"
            ;;
    esac
    pacman_install "mesa $PACKAGES_DRIVER"
}

function mkinitcpio() {
    print_step "mkinitcpio()"

    arch-chroot /mnt mkinitcpio -P
}

function network() {
    print_step "network()"

    pacman_install "networkmanager"
    arch-chroot /mnt systemctl enable NetworkManager.service
}

function virtualbox() {
    print_step "virtualbox()"

    pacman_install "virtualbox-guest-utils"
}

function users() {
    print_step "users()"

    create_user "$USER_NAME" "$USER_PASSWORD"

    arch-chroot /mnt sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

    pacman_install "xdg-user-dirs"
}

function create_user() {
    USER=$1
    PASSWORD=$2
    arch-chroot /mnt useradd -m -G wheel,storage,optical -s /bin/bash $USER
    printf "$PASSWORD\n$PASSWORD" | arch-chroot /mnt passwd $USER
}

function bootloader() {
    print_step "bootloader()"

    BOOTLOADER_ALLOW_DISCARDS=""

    if [ "$VIRTUALBOX" != "true" ]; then
        pacman_install "intel-ucode"
    fi

    if [ "$DEVICE_TRIM" == "true" ]; then
        BOOTLOADER_ALLOW_DISCARDS=":allow-discards"
    fi
    CMDLINE_LINUX="cryptdevice=PARTUUID=$PARTUUID_ROOT:$LUKS_DEVICE_NAME$BOOTLOADER_ALLOW_DISCARDS"

    CMDLINE_LINUX="$CMDLINE_LINUX rootflags=subvol=root"

    if [ "$KMS" == "true" ]; then
        case "$DISPLAY_DRIVER" in
            "nvidia" | "nvidia-390xx" | "nvidia-390xx-lts" )
                CMDLINE_LINUX="$CMDLINE_LINUX nvidia-drm.modeset=1"
                ;;
        esac
    fi

    if [ -n "$KERNELS_PARAMETERS" ]; then
        CMDLINE_LINUX="$CMDLINE_LINUX $KERNELS_PARAMETERS"
    fi

    bootloader_grub

    arch-chroot /mnt systemctl set-default multi-user.target
}

function bootloader_grub() {
    pacman_install "grub dosfstools"
    arch-chroot /mnt sed -i 's/GRUB_DEFAULT=0/GRUB_DEFAULT=saved/' /etc/default/grub
    arch-chroot /mnt sed -i 's/#GRUB_SAVEDEFAULT="true"/GRUB_SAVEDEFAULT="true"/' /etc/default/grub
    arch-chroot /mnt sed -i -E 's/GRUB_CMDLINE_LINUX_DEFAULT="(.*) quiet"/GRUB_CMDLINE_LINUX_DEFAULT="\1"/' /etc/default/grub
    arch-chroot /mnt sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="'"$CMDLINE_LINUX"'"/' /etc/default/grub
    echo "" >> /mnt/etc/default/grub
    echo "# alis" >> /mnt/etc/default/grub
    echo "GRUB_DISABLE_SUBMENU=y" >> /mnt/etc/default/grub

    pacman_install "efibootmgr"
    arch-chroot /mnt grub-install --target=x86_64-efi --bootloader-id=grub --efi-directory=$ESP_DIRECTORY --recheck

    arch-chroot /mnt grub-mkconfig -o "$BOOT_DIRECTORY/grub/grub.cfg"

    if [ "$VIRTUALBOX" == "true" ]; then
        echo -n "\EFI\grub\grubx64.efi" > "/mnt$ESP_DIRECTORY/startup.nsh"
    fi
}

function setup_zsh() {
    print_step "custom_shell()"

    pacman_install "zsh"
    CUSTOM_SHELL_PATH="/usr/bin/zsh"
    CUSTOM_SHELL_PATH=""
    arch-chroot /mnt chsh -s $CUSTOM_SHELL_PATH "root"
    arch-chroot /mnt chsh -s $CUSTOM_SHELL_PATH "$USER_NAME"

}

function desktop_environment() {
    print_step "desktop_environment()"

    pacman_install "i3-gaps i3blocks i3lock i3status rofi alacritty lightdm lightdm-gtk-greeter xorg-server"
    arch-chroot /mnt systemctl enable lightdm.service
    arch-chroot /mnt systemctl set-default graphical.target
}

function packages() {
    print_step "packages()"

    if [ -n "$PACKAGES_PACMAN" ]; then
        pacman_install "$PACKAGES_PACMAN"
    fi

    if [ -n "$AUR" -o -n "$PACKAGES_AUR" ]; then
        packages_aur
    fi
}

function packages_aur() {
    arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers

    if [ -n "$AUR" -o -n "$PACKAGES_AUR" ]; then
        pacman_install "git"

        case "$AUR" in
            "aurman" )
                arch-chroot /mnt bash -c "echo -e \"$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n\" | su $USER_NAME -c \"cd /home/$USER_NAME && git clone https://aur.archlinux.org/$AUR.git && gpg --recv-key 465022E743D71E39 && (cd $AUR && makepkg -si --noconfirm) && rm -rf $AUR\""
                ;;
            "yay" | *)
                arch-chroot /mnt bash -c "echo -e \"$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n$USER_PASSWORD\n\" | su $USER_NAME -c \"cd /home/$USER_NAME && git clone https://aur.archlinux.org/$AUR.git && (cd $AUR && makepkg -si --noconfirm) && rm -rf $AUR\""
                ;;
        esac
    fi

    if [ -n "$PACKAGES_AUR" ]; then
        aur_install "$PACKAGES_AUR"
    fi

    arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
}

function systemd_units() {
    IFS=' ' UNITS=($SYSTEMD_UNITS)
    for U in ${UNITS[@]}; do
        UNIT=${U}
        if [[ $UNIT == !* ]]; then
            ACTION="disable"
        else
            ACTION="enable"
        fi
        UNIT=$(echo $UNIT | sed "s/!//g")
        arch-chroot /mnt systemctl $ACTION $UNIT
    done
}

function terminate() {
    cp "$CONF_FILE" "/mnt/etc/$CONF_FILE"

    if [ "$LOG" == "true" ]; then
        mkdir -p /mnt/var/log
        cp "$LOG_FILE" "/mnt/var/log/$LOG_FILE"
    fi
}

function end() {
        echo ""
        echo -e "${GREEN}Arch Linux installed successfully"'!'"${NC}"
        echo ""

        REBOOT="true"
        set +e
        for (( i = 15; i >= 1; i-- )); do
            read -r -s -n 1 -t 1 -p "Rebooting in $i seconds... Press any key to abort."$'\n' KEY
            if [ $? -eq 0 ]; then
                echo ""
                echo "Restart aborted. You will must do a explicit reboot (./alis-reboot.sh)."
                echo ""
                REBOOT="false"
                break
            fi
        done
        set -e

        if [ "$REBOOT" == 'true' ]; then
            umount -R /mnt/boot
            umount -R /mnt
            reboot
        fi
}

function execute_step() {
    STEP="$1"

    eval $STEP
}

function print_step() {
    STEP="$1"
    echo ""
    echo -e "${LIGHT_BLUE}# ${STEP} step${NC}"
    echo ""
}


function init() {
    print_step "init()"

    init_log
    loadkeys $KEYS
}

function init_log() {
    exec > >(tee -a $LOG_FILE)
    exec 2> >(tee -a $LOG_FILE >&2)

    set -o xtrace
}

main $@
