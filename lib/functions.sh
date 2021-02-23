#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_media_device $cfg_media_pool $cfg_media_optn $cfg_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_droot_host $cfg_droot_addr $cfg_droot_user $cfg_droot_path $cfg_dist_name $cfg_device_vers" > /dev/null

shelp() {
    echo "
    scadrial-setup.sh

    - configures storage media for booting Ubuntu with encrypted btrfs
    - applies security enhancements
    - installs mistborn personal virtual private cloud platform

    optional flags:
        install                     Complete setup on unformatted media
        force                       Force complete setup on formatted media
        unmount	                    Unmount media
        debug                       Mount successfully formatted media
        repair                      Mount successfully formatted media and continue with setup
        h, help                     Print this help text
    "
}

log() {
    RST='\033[0m'
    YLW='\033[0;33m'
    echo
    echo -e "${YLW}• ${*}${RST}"
}

err() {
    log "error:" "$@"
    exit 1
}

cmd_exists() {
    command -v "${1}" >/dev/null 2>&1
}

cmd_check() {
    local cmd="${1}"

    if ! cmd_exists "${cmd}"; then
        err "You need ${cmd} to use this script, please install."
    fi
}

suds() {
  # sudo script runner
  sudo bash -c "${1}"
}

# shellcheck disable=SC1003
# Based on https://gist.github.com/pkuczynski/8665367
parse_yaml() {
    local yaml_file=$1
    local prefix=$2
    local s
    local w
    local fs

    s='[[:space:]]*'
    w='[a-zA-Z0-9_.-]*'
    fs="$(echo @|tr @ '\034')"

    (
        sed -e '/- [^\“]'"[^\']"'.*: /s|\([ ]*\)- \([[:space:]]*\)|\1-\'$'\n''  \1\2|g' |

        sed -ne '/^--/s|--||g; s|\"|\\\"|g; s/[[:space:]]*$//g;' \
            -e "/#.*[\"\']/!s| #.*||g; /^#/s|#.*||g;" \
            -e "s|^\($s\)\($w\)$s:$s\"\(.*\)\"$s\$|\1$fs\2$fs\3|p" \
            -e "s|^\($s\)\($w\)${s}[:-]$s\(.*\)$s\$|\1$fs\2$fs\3|p" |

        awk -F"$fs" '{
            indent = length($1)/2;
            if (length($2) == 0) { conj[indent]="+";} else {conj[indent]="";}
            vname[indent] = $2;
            for (i in vname) {if (i > indent) {delete vname[i]}}
                if (length($3) > 0) {
                    vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
                    printf("%s%s%s%s=(\"%s\")\n", "'"$prefix"'",vn, $2, conj[indent-1],$3);
                }
            }' |

        sed -e 's/_=/+=/g' |

        awk 'BEGIN {
                FS="=";
                OFS="="
            }
            /(-|\.).*=/ {
                gsub("-|\\.", "_", $1)
            }
            { print }'
    ) < "$yaml_file"
}

media_reset() {
  # shellcheck disable=SC2154
  while read -r p; do
    # Check if droot path
    if [ "${p}" == "${cfg_droot_path}" ]; then
      # unmount binds
      for b in dev dev/pts proc sys; do
        # suds "mount --make-rslave $cfg_droot_path/$b"
        suds "umount -R $cfg_droot_path/$b"
      done

      # unmount droot partition
      suds "umount ${p}"

      # close encrypted device
      suds "cryptsetup luksClose ${cfg_device_luks}"
      break
    fi

    # Unmount sub partitions
    suds "umount ${p}"
  done < <(df --output=target | grep "${cfg_droot_path}" | tac)
}

open_luks() {
	log "Ensure luks volume unlocked"
	if [ "$(sudo blkid | grep -c /dev/mapper/crypt_root)" == 0 ]; then
		echo "Luks Unlocked"
		suds "echo -n ${1} | cryptsetup --key-file=- \
			luksOpen ${cfg_media_device}2 ${cfg_device_luks}"
	fi
}

media_mount() {
	if [ -z "${passphrase:-}" ]; then
		log "Enter passphrase:"
		read -rs passphrase
		# passphrase=123456
	fi
	open_luks "$passphrase"

    log "Mount the partitions"
    #----------------------------------------------------------------------------
    suds "rm -rf ${cfg_droot_path}"
    suds "mkdir -p ${cfg_droot_path}"
    suds "mount -o ${cfg_media_optn},subvol=@      /dev/mapper/crypt_root ${cfg_droot_path}"
    suds "mkdir -p ${cfg_droot_path}/boot"
    suds "mount -o ${cfg_media_optn},subvol=@boot  /dev/mapper/crypt_root ${cfg_droot_path}/boot"
    suds "mkdir -p ${cfg_droot_path}/{boot/efi,home,opt/mistborn_volumes,var}"
    suds "mount ${cfg_media_device}1 ${cfg_droot_path}/boot/efi"
    suds "mount -o ${cfg_media_optn},subvol=@home  /dev/mapper/crypt_root ${cfg_droot_path}/home"
    suds "mount -o ${cfg_media_optn},subvol=@data  /dev/mapper/crypt_root ${cfg_droot_path}/opt/mistborn_volumes"
    suds "mount -o ${cfg_media_optn},subvol=@var   /dev/mapper/crypt_root ${cfg_droot_path}/var"
    suds "mkdir -p ${cfg_droot_path}/{var/log,var/tmp}"
    suds "mount -o ${cfg_media_optn},subvol=@log   /dev/mapper/crypt_root ${cfg_droot_path}/var/log"
    suds "mkdir -p ${cfg_droot_path}/var/log/audit"
    suds "mount -o ${cfg_media_optn},subvol=@audit /dev/mapper/crypt_root ${cfg_droot_path}/var/log/audit"
    suds "mount -o ${cfg_media_optn},subvol=@tmp   /dev/mapper/crypt_root ${cfg_droot_path}/var/tmp"
}

media_setup() {
    #----------------------------------------------------------------------------
	# Function configure the specified media per the config.yaml
	# Includes partitioning, encryption, mounting, etc.
    #----------------------------------------------------------------------------

	log "Enter passphrase:"
	# read -rs passphrase
	passphrase=123456

    #----------------------------------------------------------------------------
    log "Generate ssh key pair on the client (i.e. laptop)"
    #----------------------------------------------------------------------------
    echo -n "$passphrase" | ssh-keygen -o -a 256 -t ed25519 \
        -f "$HOME/.ssh/id_ed25519_${cfg_droot_host}" \
        -C "${cfg_droot_user}@${cfg_droot_host}-$(date -I)"
    eval "$(ssh-agent -s)"
    ssh-add "$HOME/.ssh/id_ed25519_${cfg_droot_host}"

    chmod 700 ~/.ssh 
    touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
    chmod 400 "$HOME/.ssh/id_ed25519_${cfg_droot_host}"

    cat <<- EOF | tee ~/.ssh/config
	Host $cfg_droot_host
	HostName $cfg_droot_addr
	User $cfg_droot_user
	IdentityFile $HOME/.ssh/id_ed25519_${cfg_droot_host}
	IdentitiesOnly yes
	EOF

    #----------------------------------------------------------------------------
    log "Setup storage media"
    #----------------------------------------------------------------------------

	media_reset

    suds "sgdisk -og ${cfg_media_device} \
    --new=1::+260M  --typecode=1:EF00 --change-name=1:'EFI partition' \
    --new=2::0      --typecode=2:8304 --change-name=2:'Linux partition'"

    suds "sgdisk -p ${cfg_media_device}"
    suds "partprobe ${cfg_media_device}"

    suds "wipefs -af ${cfg_media_device}1"
    suds "wipefs -af ${cfg_media_device}2"

    log "Setup encryption"
    #----------------------------------------------------------------------------
    suds "echo -n $passphrase | cryptsetup -v --iter-time 5000 --type luks2 \
        --hash sha512 --use-random luksFormat --key-file=- ${cfg_media_device}2"
    open_luks $passphrase

    log "Create filesystems"
    #----------------------------------------------------------------------------
    suds "mkfs.vfat -vF32 ${cfg_media_device}1"
    suds "mkfs.btrfs -L crypt_root /dev/mapper/${cfg_device_luks}"

    suds "rm -rf ${cfg_media_pool} && mkdir ${cfg_media_pool}"
    suds "mount -t btrfs -o ${cfg_media_optn} /dev/mapper/crypt_root ${cfg_media_pool}"
    suds "btrfs subvolume create ${cfg_media_pool}/@"
    suds "btrfs subvolume create ${cfg_media_pool}/@boot"
    suds "btrfs subvolume create ${cfg_media_pool}/@home"
    suds "btrfs subvolume create ${cfg_media_pool}/@data"
    suds "btrfs subvolume create ${cfg_media_pool}/@var"
    suds "btrfs subvolume create ${cfg_media_pool}/@log"
    suds "btrfs subvolume create ${cfg_media_pool}/@audit"
    suds "btrfs subvolume create ${cfg_media_pool}/@tmp"

    suds "umount ${cfg_media_pool}"

	media_mount

    #----------------------------------------------------------------------------
    log "Bootstrap the new system"
    #----------------------------------------------------------------------------
    suds "debootstrap --arch amd64 $cfg_dist_name $cfg_droot_path" http://archive.ubuntu.com/ubuntu
    for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_droot_path/$b"; done

}

system_setup() {
	#----------------------------------------------------------------------------
    log "Generate final system script."
	#----------------------------------------------------------------------------
	suds "mkdir -p  $cfg_droot_path/home"
	suds "cp -r     $cfg_droot_path/etc/skel $cfg_droot_path/home/$cfg_droot_user"
	suds "cp -r ./* $cfg_droot_path/home/$cfg_droot_user/scadrial/"

	cat <<- 'SEOF' > system_01_finalize.sh
	#!/bin/bash

	#----------------------------------------------------------------------------
	# Load the source functions
	#----------------------------------------------------------------------------
	# shellcheck disable=SC1091
	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	log "Setup environment, user and access"
	#----------------------------------------------------------------------------
	useradd -M -s /bin/bash "$cfg_droot_user"
	passwd "$cfg_droot_user"
	usermod -a -G sudo "$cfg_droot_user"

	suds "chown -R $cfg_droot_user:$cfg_droot_user /home/scadrial"

	sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	echo "$cfg_droot_host" > /etc/hostname
	echo LANG=en_US.UTF-8 > /etc/locale.conf
	ln -sf /usr/share/zoneinfo/${cfg_dist_tzne} /etc/localtime
	locale-gen en_US.UTF-8

	cat <<- EOF > /etc/netplan/01-netcfg.yaml
	# This file describes the network interfaces available on your system
	# For more information, see netplan(5).
	network:
	  version: 2
	  renderer: networkd
	  ethernets:
	    ${cfg_droot_ndev}:
	      dhcp4: yes
	EOF

	sudo netplan generate
	sudo netplan apply
	
	#----------------------------------------------------------------------------
	log "Configure partion files"
	#----------------------------------------------------------------------------
	pluks="$(blkid -s PARTUUID -o value ${cfg_media_device}2)"
	# Setup the device UUID that contains our luks volume
	echo "# <target name>	<source device>		<key file>	<options>" > /etc/crypttab
	echo "$cfg_device_luks PARTUUID=$pluks none luks,discard" >> /etc/crypttab

	# Setup the partitions
	eboot="$(blkid -s UUID -o value ${cfg_media_device}1)"
	croot="$(blkid -s UUID -o value /dev/mapper/$cfg_device_luks)"

	cat <<- EOF | tee /etc/fstab
	UUID=$croot  /                     btrfs   rw,${cfg_media_optn},subvol=@                           0 0
	UUID=$croot  /boot                 btrfs   rw,${cfg_media_optn},subvol=@boot                       0 0
	UUID=$eboot                                   /boot/efi       vfat    rw,umask=0077                                           0 1
	UUID=$croot  /home                 btrfs   rw,${cfg_media_optn},subvol=@home,nosuid,nodev          0 0
	UUID=$croot  /opt/mistborn_volumes btrfs   rw,${cfg_media_optn},subvol=@data,nosuid,nodev,noexec   0 0
	UUID=$croot  /var                  btrfs   rw,${cfg_media_optn},subvol=@var                        0 0
	UUID=$croot  /var/log              btrfs   rw,${cfg_media_optn},subvol=@log,nosuid,nodev,noexec    0 0
	UUID=$croot  /var/log/audit        btrfs   rw,${cfg_media_optn},subvol=@audit,nosuid,nodev,noexec  0 0
	UUID=$croot  /var/tmp              btrfs   rw,${cfg_media_optn},subvol=@tmp,nosuid,nodev,noexec    0 0
	tmpfs                                           /tmp            tmpfs   rw,nosuid,nodev,noexec
	# Swap in zram (adjust for your needs)
	# /dev/zram0        none    swap    defaults      0 0
	EOF

	#----------------------------------------------------------------------------
	log "Install applications and kernel"
	#----------------------------------------------------------------------------
	echo "deb http://archive.ubuntu.com/ubuntu focal main universe" > /etc/apt/sources.list
	echo "deb http://archive.ubuntu.com/ubuntu focal-updates main universe" >> /etc/apt/sources.list
	echo "deb http://archive.ubuntu.com/ubuntu focal-backports main universe" >> /etc/apt/sources.list
	apt-get update && apt-get -y upgrade
	# kernel=$(apt-cache search linux-image-${cfg_device_vers} | grep generic | tail -n 1 | awk -F' - ' '{print $1}')
	# modules=$(apt-cache search linux-modules-extra-${cfg_device_vers} | grep generic | tail -n 1 | awk -F' - ' '{print $1}')

	kernel="linux-image-generic-hwe-${cfg_device_vers}"

	apt-get install -y "$kernel" linux-firmware cryptsetup initramfs-tools cryptsetup-initramfs git ssh pciutils \
	gdisk btrfs-progs debootstrap parted net-tools ca-certificates iproute2 fwupd iptables --no-install-recommends

	echo 'HOOKS="amd64_microcode base keyboard udev autodetect modconf block keymap encrypt btrfs filesystems"' > /etc/mkinitcpio.conf
	sed -i "s|#KEYFILE_PATTERN=|KEYFILE_PATTERN=/etc/luks/*.keyfile|g" /etc/cryptsetup-initramfs/conf-hook
	sed -i "/UMASK=0077/d" /etc/initramfs-tools/initramfs.conf
	echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

	mkdir -p /home/${cfg_droot_user}/.ssh && touch /home/${cfg_droot_user}/.ssh/authorized_keys
	chmod 700 /home/${cfg_droot_user}/.ssh && chmod 600 /home/${cfg_droot_user}/.ssh/authorized_keys
	chown -R $cfg_droot_user:$cfg_droot_user /home/${cfg_droot_user}/.ssh/

	#----------------------------------------------------------------------------
	log "Setup systemd-boot files"
	#----------------------------------------------------------------------------
	mkdir -p /boot/efi/{ubuntu,loader/entries}
	cat <<- EOF > /boot/efi/loader/loader.conf
	default Ubuntu
	timeout 5
	editor 0
	EOF

	cat <<- EOF > /boot/efi/loader/entries/ubuntu.conf
	title   Ubuntu
	linux   /ubuntu/vmlinuz
	initrd  /ubuntu/initrd.img
	options cryptdevice=PARTUUID=${pluks}:${cfg_device_luks}:allow-discards root=/dev/mapper/${cfg_device_luks} rootflags=subvol=@ rd.luks.options=discard rw
	EOF

	LATEST="$(cd /boot/ && ls -1t vmlinuz-* | head -n 1 | sed s/vmlinuz-//)"
	for FILE in config initrd.img System.map vmlinuz; do
		cp "/boot/${FILE}-${LATEST}" "/boot/efi/ubuntu/${FILE}"
	done

	update-initramfs -u -k all
	bootctl install --path=/boot/efi

	#----------------------------------------------------------------------------
	log "Clone git repos"
	#----------------------------------------------------------------------------
	git clone https://github.com/sstephenson/bats.git
	git clone https://github.com/konstruktoid/hardening.git
	git clone https://gitlab.com/cyber5k/mistborn.git
	sed -i "s|cp ./config/tmp.mount|#cp ./config/tmp.mount|g" ./hardening/scripts/08_fstab

	#----------------------------------------------------------------------------
	log "The initial media configuration complete. Pending steps to complete on the host."
	echo "Exit chroot and umount our media, as follows:"
	#----------------------------------------------------------------------------
	echo "exit"
	echo "./scadrial-setup.sh unmount"

	#----------------------------------------------------------------------------
	log "After booting into our new host, login as 'mistborn' user and run the following:"
	#----------------------------------------------------------------------------
	echo "cd scadrial"
	echo "sudo ./system_02_harden.sh"
	echo "sudo ./system_03_mistborn.sh"
	SEOF

	cat <<- 'SEOF' > system_02_harden.sh
	#!/bin/bash
	# shellcheck disable=SC1091
	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	log "Hardening setup"
	#----------------------------------------------------------------------------
	(cd bats && ./install.sh /usr/local)

	# Update our hardening configuration file
	export vpn_net=10.$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -tu1 | sed -e 's/^ *//' -e 's/  */./g')
	export vpn_prt=$(echo $(od -An -N2 -i < /dev/urandom)  | xargs)
	(cd hardening && \
	sed -i "s/FW_ADMIN='127.0.0.1'/FW_ADMIN='${vpn_net}.0\/24'/g" ubuntu.cfg && \
	sed -i "s/CHANGEME=''/CHANGEME='N'/g" ubuntu.cfg)
	# replace all instances of Mistborn 10.2.3.1 with ${vpn_net}.1
	sed -i "s/10.2.3.1/${vpn_net}.1/g" ./mistborn/scripts/install.sh

	# Run security initial assessment
	(cd hardening/tests/ && sudo bats . > ../bats-results1.log)

	# Harden the host
	(cd hardening && sudo -E bash ubuntu.sh)
	
	# Run security initial assessment
	(cd hardening/tests/ && sudo bats . > ../bats-results2.log)
	apt-get install -y git
	SEOF

	cat <<- 'SEOF' > system_03_mistborn.sh
	#!/bin/bash
	# shellcheck disable=SC1091
	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	log "Mistborn installation"
	#----------------------------------------------------------------------------
	sudo -E bash ./mistborn/scripts/install.sh
	log "Watch the installation happens with:"
	echo "sudo journalctl -xfu Mistborn-base"
	log "Type the following to get the admin Wireguard profile:"
	echo "sudo mistborn-cli getconf"
	SEOF

	# Move the second step script to our media device
	sudo chmod +x system_01_finalize.sh system_02_harden.sh system_03_mistborn.sh
	suds "mv system_01_finalize.sh system_02_harden.sh system_03_mistborn.sh $cfg_droot_path/home/$cfg_droot_user/scadrial"
}