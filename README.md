# OpenWrt A/B Upgrades
## Overview
A/B upgrades allow for safer OpenWrt upgrades. If the upgrade does not go as
planned, you can easily boot into your previous image.

The A/B upgrade approach functions by having two root parititons. When
executing an upgrade the new image will be written to the non-active root
partition. The grub config is updated to allow booting into either image.

At boot, you'll be able to select between either image. The most recently
installed/upgraded image will be the default.
* OpenWrt SNAPSHOT r15199-5d2b577a53
* OpenWrt SNAPSHOT r15129-d346beb08c

### Partition Layout
* /dev/sda1 = /boot with label kernel
* /dev/sda2 = / with label rootfs_a
* /dev/sda3 = / with label rootfs_b

Filesystem labels are used to auto-detect partitions for the upgrade. If the
system was deployed from the combined-ext4 image the setup is largely handled
automatically and only needs you to create the new root partition.

Both root images have their kernels on the same boot partition. They are named
with the A/B label as a suffix. The layout above would have
`/boot/vmlinuz-A` and `/boot/vmlinuz-B` for the two rootfs's kernels.

### High Level Process
1. Detect all required partitions
1. Identify the non-active root partition
2. Create sysupgrade backup
3. Format target partition
4. Mount target partition to /mnt/sysupgrade
5. Extract rootfs to /mnt/sysupgrade
6. Copy kernel to /boot/vmlinuz-ID
7. Extract openwrt-backup to /mnt/sysupgrade
8. Backup grub.cfg
9. Generate new grub.cfg
10. Reboot

## Setup for GPT partition layout
1. Install Packages: `opkg install parted coreutils-stat blkid e2fsprogs`
2. If required, resize the initial root partition (2)
   ```
   root@OpenWrt:~# parted --fix --script /dev/sda resizepart 2 1041MiB name 2 root_a
   root@OpenWrt:~# parted /dev/sda unit MiB print
    Model: ATA VBOX HARDDISK (scsi)
    Disk /dev/sda: 4096MiB
    Sector size (logical/physical): 512B/512B
    Partition Table: gpt
    Disk Flags:

    Number  Start    End      Size     File system  Name    Flags
    128     0.02MiB  0.25MiB  0.23MiB                       bios_grub
     1      0.25MiB  16.2MiB  16.0MiB  fat16                legacy_boot
     2      16.3MiB  1041MiB  1025MiB  ext4         root_a
   ```
2. Create partiton for second rootfs (3)
   ```
   root@OpenWrt:~# parted /dev/sda mkpart root_b ext4 1041MiB 2064MiB name 3 root_b
   root@OpenWrt:~# parted /dev/sda unit MiB print
   Model: ATA VBOX HARDDISK (scsi)
   Disk /dev/sda: 4096MiB
   Sector size (logical/physical): 512B/512B
   Partition Table: gpt
   Disk Flags:

   Number  Start    End      Size     File system  Name    Flags
   128     0.02MiB  0.25MiB  0.23MiB                       bios_grub
    1      0.25MiB  16.2MiB  16.0MiB  fat16                legacy_boot
    2      16.3MiB  1041MiB  1025MiB  ext4         root_a
    3      1041MiB  2064MiB  1025MiB               root_b
   ```

## Setup for MBR partition layout
1. Install Packages: `opkg install parted coreutils-stat blkid e2fsprogs`
2. If required, resize the initial root partition (2)
   ```
   root@OpenWrt:~# parted --fix --script /dev/sda resizepart 2 1041MiB
   root@OpenWrt:~# parted /dev/sda unit MiB print
   Model: ATA VBOX HARDDISK (scsi)
   Disk /dev/sda: 4096MiB
   Sector size (logical/physical): 512B/512B
   Partition Table: msdos
   Disk Flags:

   Number  Start    End      Size     Type     File system  Flags
    1      0.25MiB  16.2MiB  16.0MiB  primary  ext2         boot
    2      16.3MiB  1041MiB  1025MiB  primary  ext4
   ```
2. Create partiton for second rootfs (3)
   ```
   root@OpenWrt:~# parted /dev/sda mkpart primary ext4 1041MiB 2064MiB
   root@OpenWrt:~# parted /dev/sda unit MiB print
   Model: ATA VBOX HARDDISK (scsi)
   Disk /dev/sda: 4096MiB
   Sector size (logical/physical): 512B/512B
   Partition Table: msdos
   Disk Flags:

   Number  Start    End      Size     Type     File system  Flags
    1      0.25MiB  16.2MiB  16.0MiB  primary  ext2         boot
    2      16.3MiB  1041MiB  1025MiB  primary  ext4
    3      1041MiB  2064MiB  1025MiB  primary
   ```

## Upgrading
1. Optional: Modify upgrade.sh to update default grub options
2. Install Packages: `opkg install coreutils-stat blkid`
3. Download rootfs and kernel to /root
   ```
   cd /root
   wget https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-x86-64-generic-kernel.bin
   wget https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-x86-64-rootfs.tar.gz
   ```
3. Upgrade: `./upgrade.sh openwrt-x86-64-generic-kernel.bin openwrt-x86-64-rootfs.tar.gz`
4. Reboot

### Example outputs

First upgrade, from a system built with the combined-ext4 image and the setup
instructions above. Note the warning that is presented, and the script is
guessing rootfs_b's location.
```
root@OpenWrt:~# ./upgrade.sh openwrt—23.05.5-x86-64-generic-kernel.bin openwrt—23.05.5-x86-64-generic-rootfs.tar.gz
WARNING: rootfs_a found with OpenWRT name on /dev/sda2 (this is normal for first use)
Assuming rootfs_b should be placed on /dev/sda3. Proceed with caution.
Current Root FS: /dev/sda2
Target Root FS: /dev/sda3
Kernel: openwrt-23.05.5-x86-64-generic-kernel.bin
Rootfs: openwrt-23.05.5-x86-64-generic-rootfs.tar.gz
Continue? (y/n) y
upgrade: Saving config files...
Formatting /dev/sda3...
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 261888 4k blocks and 65536 inodes
Filesystem UID: 76eca9aa-5959-45fb-adca-78a5b5e66f69
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376

Allocating group tables: done
Writing inode tables: done
Creating journal (4096 blocks): done
Writing superblocks and filesystem accounting information: done

Mounting /dev/sda3 to /mmt/sysupgrade...
Extracting rootfs.
Restoring backup...
Generating grub.cfg...
Copying kernel...
root@OpenWrt:~#
```

Sample output from the same system, but now it's running from image B, so it
will write to image A's partition.
```
root@OpenWrt:~# ./upgrade.sh openwrt—23.05.5-x86-64-generic-kernel.bin openwrt—23.05.5-x86-64-generic-rootfs.tar.gz
Current Root FS: /dev/sda3
Target Root FS: /dev/sda2
Kernel: openwrt-23.05.5-x86-64-generic-kernel.bin
Rootfs: openwrt-23.05.5-x86-64-generic-rootfs.tar.gz
Continue? (y/n) y
upgrade: Saving config files...
Formatting /dev/sda2...
mke2fs 1.47.0 (5-Feb-2023)
/dev/sda2 contains a ext4 file system labelled 'rootfs'
last mounted on / on Sat Oct 12 11:26:16 2024
Proceed anyway? (y,N) y
Creating filesystem with 262144 4k blocks and 65664 inodes
Filesystem UID: 439f55ff-af93-4a69-a5d9-27952b640184
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376

Allocating group tables: done
Writing inode tables: done
Creating journal (8192 blocks): done
Writing superblocks and filesystem accounting information: done

Mounting /dev/sda2 to /mmt/sysupgrade...
Extracting rootfs.
Restoring backup
Generating grub.cfg
Copying kernel
root@OpenWrt:~#
```

## FAQ / Notes

* Q: Why do you use not use `root=PARTUUID=<uuid>` in grub.cfg anymore?

  A: For some reason OpenWRT uses truncated PARTUUID's that match between
  partitions and devices. For MBR this is probably expected, but with GPT
  it causes us a limitation. The truncation is the last 2 hex values of
  the UUID are modified as follows:
  * 02 (root partition PARTUUID)
  * 01 (boot partition PARTUUID)
  * 00 (device partition table id PTUUID)

  And the result is, if the running root PARTUUID truncated to 00 on the end
  is not found, /boot won't get mounted. This exhibited itself as Image A
  was mounting /boot, and Image B was not. So we use the device name instead
  which works around the issue. There is no practical way to have the same
  PARTUUID on multiple partitions, so we have to work around the issue.

  The function that is doing this is
  [export_bootdevice()](https://github.com/openwrt/openwrt/blob/fa6bd065ddad1a3e5d507a4eb9b5fd1fd4b4055a/package/base-files/files/lib/upgrade/common.sh#L186)
  in `/lib/upgrade/common.sh`. Switching to device names follows a different
  codepath avoiding the issue entirely.
  [Related issue here](https://github.com/openwrt/openwrt/issues/6206).
