#!/bin/sh

# Override here if auto detect doesn't work
BOOT_DEV=""
ROOTA_DEV=""
ROOTB_DEV=""

# Default image name strings (no spaces please)
LABEL_IMAGEA="A"
LABEL_IMAGEB="B"

# Arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 kernel rootfs"
    exit 1
fi

if [ -z $1 ]; then
    echo "Argument 1 must be the kernel!"
    exit 1
fi

if [ -z $2 ]; then
    echo "Argument 2 must be the rootfs!"
    exit 1
fi

KERNEL=$1
ROOTFS=$2

# Make sure files exist
if [ ! -f $KERNEL ]; then
    echo "$KERNEL does not exist!"
    exit 1
fi
if [ ! -f $ROOTFS ]; then
    echo "ROOTFS does not exist!"
    exit 1
fi

# rootfs needs to be gzipped tarball
if ! gzip -t $ROOTFS; then
    echo "rootfs is not a gzipped file! Abort!"
    exit 1
fi


# Require stat
if ! which stat &>/dev/null; then
    echo "stat is required: opkg install coreutils-stat"
    exit 1
fi

# Require mkfs.ext4
if ! which mkfs.ext4 &>/dev/null; then
    echo "mkfs.ext4 is required: opkg install e2fsprogs"
    exit 1
fi

# Require blkid
if ! which blkid &>/dev/null; then
    echo "blkid is required: opkg install blkid"
    exit 1
fi

# If this exists, we probably have an incomplete upgrade
if [ -d /mnt/sysupgrade ]; then
    echo "/mnt/sysupgrade exists! Unexpected, aborting!"
    exit 1
fi

# Detect the partitions in use by filesystem labels (not partition labels)
if [ -z "${BOOT_DEV}" ]; then
    BOOT_DEV=$(blkid -t LABEL=kernel -o device) # openwrt full disk image uses this name
fi
if [ -z "${ROOTA_DEV}" ]; then
    ROOTA_DEV=$(blkid -t LABEL=rootfs_a -o device) #the name we use
fi
if [ -z "${ROOTB_DEV}" ]; then
    ROOTB_DEV=$(blkid -t LABEL=rootfs_b -o device)
fi
# That should find everything with the names we use, if we're still blank, try the openwrt
# default for rootfs_a, increment by 1 for rootfs_b and alert the user.
if [ -z "${ROOTA_DEV}" ]; then
    ROOTA_DEV=$(blkid -t LABEL=rootfs -o device) # openwrt full disk image uses this name
    if [ ! -z "${ROOTA_DEV}" ] && [ -z "${ROOTB_DEV}" ]; then
        # that worked, lets increment for B (for simplicity we assume single digit partition numbers)
        ROOTB_DEV=${ROOTA_DEV%?} # remove the last character
        ROOTA_PART_NUM=${ROOTA_DEV#"${ROOTB_DEV}"} # ROOTA_DEV with the first bit removed
        ROOTB_DEV=${ROOTB_DEV}$(( ${ROOTA_PART_NUM} + 1 ))
        echo "WARNING: rootfs_a found with OpenWRT name on ${ROOTA_DEV} (this is normal for first use)"
        echo "Assuming rootfs_b should be placed on ${ROOTB_DEV}. Proceed with caution."
        MIGRATION=yes
    #elif [ ! -z "${ROOTA_DEV}" ] && [ ! -z "${ROOTB_DEV}" ]; then
        # this would be when we're running from B and this will be the first time recreating
        # A. So this is ok for the second use of this upgrade on a system.
    fi
fi

if [ -z "${BOOT_DEV}" ] || [ -z "${ROOTA_DEV}" ] || [ -z "${ROOTB_DEV}" ]; then
    echo "unable to autodetect all three partitions. Update this script's variables or label the filesystems."
    exit 1
fi

# Check if specified boot volume exists and is mounted on /boot
if [ -b $BOOT_DEV ]; then
    bootIdByBlock=$(stat -c "%02t%02T" $BOOT_DEV)
    bootIdByPath=$(stat -c %04D /boot)
    if [ $bootIdByBlock != $bootIdByPath ]; then
        echo "/boot is not mounted on $BOOT_DEV! Abort!"
        exit 1
    fi
else
    echo "boot device, $BOOT_DEV, does not exist! Abort!"
    exit 1
fi

# Get Root Volume
#ROOT_DEV=$(findmnt -n -o SOURCE /)

# Major Minor
rootIdByDev=$(stat -c %04D /)
rootOneIdByBlock=$(stat -c "%02t%02T" $ROOTA_DEV)
rootTwoIdByBlock=$(stat -c "%02t%02T" $ROOTB_DEV)

if [ $rootIdByDev = $rootOneIdByBlock ]; then
    ROOT_DEV=$ROOTA_DEV
    TARGET_DEV=$ROOTB_DEV
    TARGET_FS_LABEL="rootfs_b"
    ROOT_LABEL=${LABEL_IMAGEA}
    TARGET_LABEL=${LABEL_IMAGEB}
elif [ $rootIdByDev = $rootTwoIdByBlock ]; then
    ROOT_DEV=$ROOTB_DEV
    TARGET_DEV=$ROOTA_DEV
    TARGET_FS_LABEL="rootfs_a"
    ROOT_LABEL=${LABEL_IMAGEB}
    TARGET_LABEL=${LABEL_IMAGEA}
else
    echo "rootfs is not mounted on $ROOTA_DEV or $ROOTB_DEV! Abort!"
    exit 1
fi

# Exit if target device is mounted
if mount $TARGET_DEV &>/dev/null; then
    echo "Target device, $TARGET_DEV, is mounted! Abort!"
    exit 1
fi

# Print some information
echo "Current Root FS: $ROOT_DEV"
echo "Target Root FS: $TARGET_DEV"
echo "Kernel: $KERNEL"
echo "Rootfs: $ROOTFS"

# Time to be destructive
echo -n "Continue? (y/n) "
read answer

if ! ([ $answer == Y ] || [ $answer == y ]); then
    echo "Aborting!"
    exit 1
fi

# Do a backup
sysupgrade -b openwrt-backup.tar.gz
if [ $? != 0 ]; then
    echo "sysupgrade backup failed! Abort!"
    exit 1
fi


echo "Formatting $TARGET_DEV..."
mkfs.ext4 -q -L ${TARGET_FS_LABEL} -b 4096 -m 0 ${TARGET_DEV}

echo "Mounting $TARGET_DEV to /mnt/sysupgrade..."
mkdir /mnt/sysupgrade
mount $TARGET_DEV /mnt/sysupgrade || exit 1

echo "Extracting rootfs..."
zcat $ROOTFS | tar x -C /mnt/sysupgrade || exit 1

echo "Restoring backup..."
zcat openwrt-backup.tar.gz | tar x -C /mnt/sysupgrade || exit 1

echo "Generating grub.cfg..."
cp /boot/grub/grub.cfg /boot/grub/grub.cfg.bak

release=$(grep OPENWRT_RELEASE /mnt/sysupgrade/etc/os-release | cut -d'"' -f2)
#partuuid=$(blkid -s PARTUUID -o value $TARGET_DEV)
partid=${TARGET_LABEL} #$(echo $TARGET_DEV | egrep -o '[0-9]+')
partdev=$TARGET_DEV
a_release=$(grep OPENWRT_RELEASE /etc/os-release | cut -d'"' -f2)
#a_partuuid=$(blkid -s PARTUUID -o value $ROOT_DEV)
a_partid=${ROOT_LABEL} #$(echo $ROOT_DEV | egrep -o '[0-9]+')
a_partdev=$ROOT_DEV

echo "Copying kernel..."
cp $KERNEL /boot/vmlinuz-$partid || exit 1
touch /mnt/sysupgrade/.image-${partid}

if [ "${MIGRATION}" == "yes" ] && [ ! -f "/boot/vmlinuz-${a_partid}" ] && [ -f "/boot/vmlinuz" ] ; then
    # Migrate from openwrt named kernel to rootfs_a kernel
    mv /boot/vmlinuz /boot/vmlinuz-${a_partid} || exit 1
fi

cat <<EOF > /boot/grub/grub.cfg
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1 --rtscts=off
terminal_input console serial; terminal_output console serial

set default="0"
set timeout="5"
search -l kernel -s root

menuentry "$release $partid" {
	linux /boot/vmlinuz-$partid root=$partdev rootwait  console=tty0 console=ttyS0,115200n8 noinitrd
}
menuentry "$release $partid (failsafe)" {
	linux /boot/vmlinuz-$partid failsafe=true root=$partdev rootwait  console=tty0 console=ttyS0,115200n8 noinitrd
}
menuentry "$a_release $a_partid" {
	linux /boot/vmlinuz-$a_partid root=$a_partdev rootwait  console=tty0 console=ttyS0,115200n8 noinitrd
}
menuentry "$a_release $a_partid (failsafe)" {
	linux /boot/vmlinuz-$a_partid failsafe=true root=$a_partdev rootwait  console=tty0 console=ttyS0,115200n8 noinitrd
}
EOF

umount /mnt/sysupgrade
