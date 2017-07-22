#!/bin/bash -e

#Showing Hard Drive names
lsblk --output NAME

#Insert Hard Drive name
echo "Insert Hard Drive name where to instal Arch Linux (example: sda, sdb) [Enter]:"
read HARD_DRIVE


# Definitions
BOOT_DEVICE=${HARD_DRIVE}1
SWAP_DEVICE=${HARD_DRIVE}2
ROOT_DEVICE=${HARD_DRIVE}3

# Reset partition table and create new DOS table
dd if=/dev/zero of=${HARD_DRIVE} bs=2M count=1 status=progress

# 256mb boot, 5gb swap and left for rootfs
fdisk ${HARD_DRIVE} <<EOF
o
n
p
1

+256M
n
p
2

+5G
n
p
3


a
1
w
EOF

# Format
mkfs.vfat ${BOOT_DEVICE}
mkfs.btrfs -f ${ROOT_DEVICE}
mkswap ${SWAP_DEVICE}
swapon ${SWAP_DEVICE}

btrfs rescue zero-log ${ROOT_DEVICE}

# Create subvolumes
mount ${ROOT_DEVICE} /mnt
pushd /mnt
for k in home var root; do
    btrfs subvolume create "@${k}"
done
popd
umount /mnt

# Mount everything into correct place
mount -o subvol=@root ${ROOT_DEVICE} /mnt
mkdir -p /mnt/{boot,var,home}
mount -o subvol=@var ${ROOT_DEVICE} /mnt/var
mount -o subvol=@home ${ROOT_DEVICE} /mnt/home
mount ${BOOT_DEVICE} /mnt/boot

# Install base system
pacstrap /mnt base base-devel

arch-chroot /mnt /bin/bash <<EOF
echo "Now running inside arch-chroot $(pwd)"

sed -i '/et_EE.UTF-8 UTF-8/s/^#//g' /etc/locale.gen
echo LANG=et_EE.UTF-8 > /etc/locale.conf

echo "ALAI" > /etc/hostname

locale-gen
ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime
mkdir -p /run/systemd/resolve; touch /run/systemd/resolve/resolv.conf
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

passwd root <<EOD
root
root
EOD

useradd -m -G wheel -s /bin/bash alai
passwd alai <<EOD
alai
alai
EOD

systemctl enable systemd-networkd
systemctl enable systemd-resolved

pacman --noconfirm --needed -S syslinux gptfdisk

syslinux-install_update -i -a -m

cat > /etc/pacman.conf <<EOD
# /etc/pacman.conf

[options]

HoldPkg     = pacman glibc
Architecture = auto

CheckSpace

SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[community]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOD
pacman -Syu

pacman --noconfirm --needed -S gnome gnome-extra dialog xorg gdm iw wpa_supplicant networkmanager

systemctl enable gdm
systemctl enable NetworkManager
EOF

# Set up bootloader
cat > /mnt/boot/syslinux/syslinux.cfg <<EOF
DEFAULT archlinux
TIMEOUT 1

LABEL archlinux
    LINUX ../vmlinuz-linux
    APPEND root=${ROOT_DEVICE} rw
    INITRD ../initramfs-linux.img
EOF

mkinitcpio -p linux

exit

genfstab -U /mnt >> /mnt/etc/fstab

umoumt -R

reboot
