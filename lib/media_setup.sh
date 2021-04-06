#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_host_name $cfg_scadrial_host_user $cfg_scadrial_host_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null

media_part() {
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
}

media_mount() {
	get_pass
	open_luks "$passphrase"

	log "Mount the partitions"
	#----------------------------------------------------------------------------
	suds "rm -rf ${cfg_scadrial_host_path}"
	suds "mkdir -p ${cfg_scadrial_host_path}"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@      /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}"
	suds "mkdir -p ${cfg_scadrial_host_path}/boot"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@boot  /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/boot"
	suds "mkdir -p ${cfg_scadrial_host_path}/{boot/efi,home,opt/mistborn_volumes,var}"
	suds "mount ${cfg_scadrial_device_name}${ppart}1 ${cfg_scadrial_host_path}/boot/efi"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@home  /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/home"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@data  /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/opt/mistborn_volumes"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@var   /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/var"
	suds "mkdir -p ${cfg_scadrial_host_path}/{var/log,var/tmp}"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@log   /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/var/log"
	suds "mkdir -p ${cfg_scadrial_host_path}/var/log/audit"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@audit /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/var/log/audit"
	suds "mount -o ${cfg_scadrial_device_optn},subvol=@tmp   /dev/mapper/${luks_dev} ${cfg_scadrial_host_path}/var/tmp"
	echo "Done"
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
			luks_dev="crypt_root$(lsblk "${cfg_scadrial_device_name}${ppart}2" | awk '/crypt_root/ {print $1}' | sed 's/.*crypt_root//')"
			suds "cryptsetup luksClose ${luks_dev}"
			break
		fi

		# Unmount sub partitions
		suds "umount ${p}"
	done < <(df --output=target | grep "${cfg_scadrial_host_path}" | tac)
}

media_setup() {
	#----------------------------------------------------------------------------
	# Function configure the specified media per the config.yaml
	# Includes partitioning, encryption, mounting, etc.
	#----------------------------------------------------------------------------
	get_pass

	#----------------------------------------------------------------------------
	log "Setup storage media"
	#----------------------------------------------------------------------------

	media_reset

	suds "sgdisk -og ${cfg_scadrial_device_name} \
	--new=1::+260M  --typecode=1:EF00 --change-name=1:'EFI partition' \
	--new=2::0      --typecode=2:8304 --change-name=2:'Linux partition'"

	suds "sgdisk -p ${cfg_scadrial_device_name}"
	suds "partprobe ${cfg_scadrial_device_name}"

	media_part

	suds "wipefs -af ${cfg_scadrial_device_name}${ppart}1"
	suds "wipefs -af ${cfg_scadrial_device_name}${ppart}2"

	#----------------------------------------------------------------------------
	log "Setup encryption"
	# Escape any dollar signs in the password
	suds "echo -n ${passphrase//$/\\$} | cryptsetup -q -v --iter-time 5000 --type luks2 \
	    --hash sha512 --use-random luksFormat ${cfg_scadrial_device_name}${ppart}2 -"
	
	# shellcheck disable=SC2086
	open_luks "$passphrase"

	#----------------------------------------------------------------------------
	log "Create filesystems"
	suds "mkfs.vfat -vF32 ${cfg_scadrial_device_name}${ppart}1"
	suds "mkfs.btrfs -L ${luks_dev} /dev/mapper/${luks_dev}"

	suds "rm -rf ${cfg_scadrial_device_pool} && mkdir ${cfg_scadrial_device_pool}"
	suds "mount -t btrfs -o ${cfg_scadrial_device_optn} /dev/mapper/${luks_dev} ${cfg_scadrial_device_pool}"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@boot"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@home"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@data"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@var"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@log"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@audit"
	suds "btrfs subvolume create ${cfg_scadrial_device_pool}/@tmp"

	suds "umount ${cfg_scadrial_device_pool}"

	media_mount

	#----------------------------------------------------------------------------
	log "Bootstrap the new system"
	#----------------------------------------------------------------------------
	suds "debootstrap --arch amd64 $cfg_scadrial_dist_name $cfg_scadrial_host_path" http://archive.ubuntu.com/ubuntu
	for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_scadrial_host_path/$b"; done
}
