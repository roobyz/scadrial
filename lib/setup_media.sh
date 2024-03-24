#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_host_name $cfg_scadrial_host_user $cfg_scadrial_host_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null

media_file() {
	if [ "$(lsblk | grep -c "${cfg_scadrial_device_name//\/dev\//}")" == 0 ]; then
		# Specify parent folder of the working folder
		lfile="$(dirname "$(pwd)")/${cfg_scadrial_device_loop_file}"
		echo "Setup sparse loop device file (${lfile})"

		touch "${lfile}"
		truncate --size "${cfg_scadrial_device_loop_size}" "${lfile}"
		losetup "${cfg_scadrial_device_name}" "${lfile}"
	fi
}

open_luks() {
	log "Ensure luks volume unlocked"
	# Setup loop sparse file is specified.
	if [ "$cfg_scadrial_device_loop" == "y" ]; then
		media_file
	fi

	if [ "$(cd /dev/mapper/ && find . -maxdepth 1 -name "${boot_mapper_name}" | wc -l)" == "0" ]; then
		# Open luks device with passphrase parameter
		if ! suds "echo -n ${1//$/\\$} | cryptsetup --key-file=- luksOpen ${2} ${3}"; then
			err "${3} Unlock Failed"
		else
			echo "${3} Unlocked"
		fi
	else
		echo "Confirmed: ${3} Unlocked"
	fi
}

media_part() {
	suds "partprobe ${cfg_scadrial_device_name}"
	# shellcheck disable=SC2001
	dname="$(echo "${cfg_scadrial_device_name}" | sed 's|/dev/||')"

	# quirk or bug?: give the drive some time to "wake-up" before actually checking partitions in the following step
	lsblk -ai > /dev/null && sleep 1

	# shellcheck disable=SC2086
	if [ "$(lsblk -aio KNAME | awk -v avar="${dname}" '$0 ~ avar { print $1 }' | sed "s/.*${dname}//" | grep -c p)" == "0" ]; then
		ppart=""
	else
		ppart="p"
	fi

	boot_cryptdevice="${cfg_scadrial_device_name}${ppart}3"
	boot_blkpartuuid=`sudo blkid -s PARTUUID -o value ${boot_cryptdevice}`
	boot_mapper_name=cryptroot-puuid-$boot_blkpartuuid
	boot_mapper_path=/dev/mapper/$boot_mapper_name

	boot_lukskeyfile=/etc/luks/boot_os.keyfile
	grub_dev="$(blkid -s UUID -o value ${cfg_scadrial_device_name}${ppart}1)"
	uefi_dev="$(blkid -s UUID -o value ${cfg_scadrial_device_name}${ppart}2)"
	boot_blkdev=`sudo blkid -s UUID -o value ${boot_cryptdevice}`

}

media_mount() {
	# Setup parition naming
	media_part

	# Decrypt the boot partition
	open_luks "${SCADRIAL_KEY}" ${boot_cryptdevice} ${boot_mapper_name}
	suds "rm -rf ${cfg_scadrial_host_path} && mkdir -p ${cfg_scadrial_host_path}"

	#----------------------------------------------------------------------------
	log "Mount partitions"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@      ${boot_mapper_path} ${cfg_scadrial_host_path}"
	suds "mount -o rw,noatime ${cfg_scadrial_device_name}${ppart}1 ${cfg_scadrial_host_path}/boot"
	suds "mount -o rw,noatime ${cfg_scadrial_device_name}${ppart}2 ${cfg_scadrial_host_path}/boot/efi"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@snaps ${boot_mapper_path} ${cfg_scadrial_host_path}/.snapshot"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@home  ${boot_mapper_path} ${cfg_scadrial_host_path}/home"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@opt   ${boot_mapper_path} ${cfg_scadrial_host_path}/opt"

}

media_reset() {
	# shellcheck disable=SC2154
	while read -r p; do
		# Check if droot path
		if [ "${p}" == "${cfg_scadrial_host_path}" ]; then
			# unmount binds
			for b in dev dev/pts proc sys; do
				# suds "mount --make-rslave $cfg_scadrial_host_path/$b"
				suds "umount -R $cfg_scadrial_host_path/$b"
			done

			# unmount droot partition
			suds "umount ${p}"

			# close encrypted device
			media_part
			suds "cryptsetup luksClose ${boot_mapper_path}"

			if [ "$cfg_scadrial_device_loop" == "y" ]; then
				losetup -d "${cfg_scadrial_device_name}"
			fi
			break
		fi

		# Unmount sub partitions
		suds "umount ${p}"
	done < <(df --output=target | grep "${cfg_scadrial_host_path}" | tac)
}

media_setup() {
	#----------------------------------------------------------------------------
	log "Setup storage media"
	#----------------------------------------------------------------------------
	# Unmount binds and media, close crypt, and then remount the media
	media_reset

	# Setup loop sparse file is specified.
	if [ "$cfg_scadrial_device_loop" == "y" ]; then
		media_file
	fi

	# partitions our media
	log "Generate Partitions"
	suds "sgdisk --zap-all ${cfg_scadrial_device_name}"
	suds "sgdisk ${cfg_scadrial_device_name} \
	--new=1::+1G    --typecode=1:EF02 --change-name=1:'BIOS boot partition' \
	--new=2::+512M  --typecode=2:EF00 --change-name=2:'EFI system partition' \
	--new=3::0      --typecode=3:8304 --change-name=3:'Linux root partition'"

	suds "sgdisk -p ${cfg_scadrial_device_name}"

	# Setup ppart attribute for parition naming
	media_part
	log "Boot Target: ${boot_mapper_name}"
	suds "wipefs -af ${cfg_scadrial_device_name}${ppart}1"
	suds "wipefs -af ${cfg_scadrial_device_name}${ppart}2"
	suds "wipefs -af ${cfg_scadrial_device_name}${ppart}3"

	#----------------------------------------------------------------------------
	log "Setup encryption"
	# Escape any dollar signs in the password
	suds "echo -n ${SCADRIAL_KEY//$/\\$} | cryptsetup -q -v --iter-time 5000 --type luks2 \
	    --hash sha512 --use-random --pbkdf pbkdf2 luksFormat ${boot_cryptdevice} -"
	
	# shellcheck disable=SC2086
	open_luks "${SCADRIAL_KEY}" ${boot_cryptdevice} ${boot_mapper_name}

	#----------------------------------------------------------------------------
	log "Setup filesystems"
	suds "mkfs.ext2 -L grub ${cfg_scadrial_device_name}${ppart}1"
	suds "mkfs.vfat -nBOOT -vF32 ${cfg_scadrial_device_name}${ppart}2"
	suds "mkfs.btrfs -f -L ${boot_cryptdevice} ${boot_mapper_path}"
	suds "rm -rf ${cfg_scadrial_device_pool} && mkdir -p ${cfg_scadrial_device_pool}"

	#----------------------------------------------------------------------------	
	log "Setup the top-level partitions"
	suds "mount -t btrfs -o ${cfg_scadrial_device_optn} ${boot_mapper_path} ${cfg_scadrial_device_pool}"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@opt"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@home"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@snaps"
	suds "umount ${cfg_scadrial_device_pool}"

	#----------------------------------------------------------------------------	
	log "Mount the top-level partitions"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@      ${boot_mapper_path} ${cfg_scadrial_host_path}"
	suds "mkdir -p ${cfg_scadrial_host_path}/{.snapshot,home,opt,boot}"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@snaps ${boot_mapper_path} ${cfg_scadrial_host_path}/.snapshot"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@home  ${boot_mapper_path} ${cfg_scadrial_host_path}/home"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@opt   ${boot_mapper_path} ${cfg_scadrial_host_path}/opt"
	suds "mount -o rw,noatime ${cfg_scadrial_device_name}${ppart}1 ${cfg_scadrial_host_path}/boot"
	suds "mkdir -p ${cfg_scadrial_host_path}/boot/efi"

	#----------------------------------------------------------------------------
	# These won't have a snapshot taken, since snapshots don't work resursively
	log "Setup the nested partitions"
	suds "btrfs subvolume create ${cfg_scadrial_host_path}/audit"
	suds "btrfs subvolume create ${cfg_scadrial_host_path}/log"
	suds "btrfs subvolume create ${cfg_scadrial_host_path}/tmp"
	suds "btrfs subvolume create ${cfg_scadrial_host_path}/var"
	suds "btrfs subvolume create ${cfg_scadrial_host_path}/var/swap"

	log "Unmount all partitions"
	suds "umount ${cfg_scadrial_host_path}/.snapshot"
	suds "umount ${cfg_scadrial_host_path}/boot"
	suds "umount ${cfg_scadrial_host_path}/home"
	suds "umount ${cfg_scadrial_host_path}/opt"
	suds "umount ${cfg_scadrial_host_path}"

	media_mount
	# exit 0
	
	#----------------------------------------------------------------------------
	log "Bootstrap the new system"
	#----------------------------------------------------------------------------
	# log "debootstrap --no-check-gpg --arch amd64 $cfg_scadrial_dist_name $cfg_scadrial_host_path"
	suds "debootstrap --no-check-gpg --arch amd64 $cfg_scadrial_dist_name $cfg_scadrial_host_path"
	# suds "debootstrap --no-check-gpg --arch amd64 $cfg_scadrial_dist_name $cfg_scadrial_host_path" http://archive.ubuntu.com/ubuntu
	for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_scadrial_host_path/$b"; done

}
