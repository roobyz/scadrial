#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_chroot_host $cfg_scadrial_chroot_user $cfg_scadrial_chroot_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null

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

set_sudoer() {
	case $(sudo grep -e "^${1}.*" /etc/sudoers >/dev/null; echo $?) in
	0)
		echo "${1} already in sudoers"
		;;
	1)
		echo "Adding ${1} to sudoers"
		sudo bash -c "echo '${1}  ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers"
		;;
	*)
		echo "There was a problem checking sudoers"
		;;
	esac
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

get_pass() {
	if [ -z "${passphrase:-}" ]; then
		log "Passphrase/password Setup"
		# shellcheck disable=SC2162
		read -p "Specify the default password: " -s passphrase
		# passphrase=123456
		echo
	fi
}

open_luks() {
	log "Unlock luks volume"
	if [ "$(sudo blkid | grep -c /dev/mapper/crypt_root)" == 0 ]; then
		if ! suds "echo -n ${1//$/\\$} | cryptsetup --key-file=- luksOpen ${cfg_scadrial_device_name}2 ${cfg_scadrial_device_luks}"; then
			err "Luks Unlock Failed"
		else
			echo "Luks Unlocked"
		fi
	fi 
}

media_mount() {
	get_pass
	open_luks "$passphrase"

    log "Mount the partitions"
    #----------------------------------------------------------------------------
    suds "rm -rf ${cfg_scadrial_chroot_path}"
    suds "mkdir -p ${cfg_scadrial_chroot_path}"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@      /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}"
    suds "mkdir -p ${cfg_scadrial_chroot_path}/boot"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@boot  /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/boot"
    suds "mkdir -p ${cfg_scadrial_chroot_path}/{boot/efi,home,opt/mistborn_volumes,var}"
    suds "mount ${cfg_scadrial_device_name}1 ${cfg_scadrial_chroot_path}/boot/efi"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@home  /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/home"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@data  /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/opt/mistborn_volumes"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@var   /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/var"
    suds "mkdir -p ${cfg_scadrial_chroot_path}/{var/log,var/tmp}"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@log   /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/var/log"
    suds "mkdir -p ${cfg_scadrial_chroot_path}/var/log/audit"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@audit /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/var/log/audit"
    suds "mount -o ${cfg_scadrial_device_optn},subvol=@tmp   /dev/mapper/crypt_root ${cfg_scadrial_chroot_path}/var/tmp"
}

media_reset() {
  # shellcheck disable=SC2154
  while read -r p; do
    # Check if droot path
    if [ "${p}" == "${cfg_scadrial_chroot_path}" ]; then
      # unmount binds
      for b in dev dev/pts proc sys; do
        # suds "mount --make-rslave $cfg_scadrial_chroot_path/$b"
        suds "umount -R $cfg_scadrial_chroot_path/$b"
      done

      # unmount droot partition
      suds "umount ${p}"

      # close encrypted device
      suds "cryptsetup luksClose ${cfg_scadrial_device_luks}"
      break
    fi

    # Unmount sub partitions
    suds "umount ${p}"
  done < <(df --output=target | grep "${cfg_scadrial_chroot_path}" | tac)
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

    suds "wipefs -af ${cfg_scadrial_device_name}1"
    suds "wipefs -af ${cfg_scadrial_device_name}2"

    #----------------------------------------------------------------------------
    log "Setup encryption"
	# Escape any dollar signs in the password
    suds "echo -n ${passphrase//$/\\$} | cryptsetup -q -v --iter-time 5000 --type luks2 \
        --hash sha512 --use-random luksFormat ${cfg_scadrial_device_name}2 -"
	
	# shellcheck disable=SC2086
    open_luks $passphrase

    #----------------------------------------------------------------------------
    log "Create filesystems"
    suds "mkfs.vfat -vF32 ${cfg_scadrial_device_name}1"
    suds "mkfs.btrfs -L crypt_root /dev/mapper/${cfg_scadrial_device_luks}"

    suds "rm -rf ${cfg_scadrial_device_pool} && mkdir ${cfg_scadrial_device_pool}"
    suds "mount -t btrfs -o ${cfg_scadrial_device_optn} /dev/mapper/crypt_root ${cfg_scadrial_device_pool}"
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
    suds "debootstrap --arch amd64 $cfg_scadrial_dist_name $cfg_scadrial_chroot_path" http://archive.ubuntu.com/ubuntu
    for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_scadrial_chroot_path/$b"; done
}

script_setup() {
	#----------------------------------------------------------------------------
	log "Generate final system scripts."
	#----------------------------------------------------------------------------
	suds "mkdir -p  $cfg_scadrial_chroot_path/home/$cfg_scadrial_chroot_user/scadrial"
	suds "cp -r ./* $cfg_scadrial_chroot_path/home/$cfg_scadrial_chroot_user/scadrial/"
	suds "cp $cfg_scadrial_chroot_path/etc/skel/.* $cfg_scadrial_chroot_path/home/$cfg_scadrial_chroot_user/ 2> /dev/null"

	cat <<- 'SEOF' > scadrial-finalize.sh
	#!/bin/bash

	#----------------------------------------------------------------------------
	# Load the source functions
	#----------------------------------------------------------------------------
	# shellcheck disable=SC1091
	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	get_pass
	
	#----------------------------------------------------------------------------
	log "Setup environment, user and access"
	#----------------------------------------------------------------------------
	useradd -M -s /bin/bash "$cfg_scadrial_chroot_user"
	echo "${cfg_scadrial_chroot_user}:${passphrase}" | chpasswd
	set_sudoer "$cfg_scadrial_chroot_user"
	suds "chown -R $cfg_scadrial_chroot_user:$cfg_scadrial_chroot_user /home/$cfg_scadrial_chroot_user"
	
	sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	echo "$cfg_scadrial_chroot_host" > /etc/hostname
	echo LANG=en_US.UTF-8 > /etc/locale.conf
	ln -sf /usr/share/zoneinfo/${cfg_scadrial_chroot_tzne} /etc/localtime
	locale-gen en_US.UTF-8

	#----------------------------------------------------------------------------
	log "Configure partitions"
	#----------------------------------------------------------------------------
	pluks="$(blkid -s PARTUUID -o value ${cfg_scadrial_device_name}2)"

	# Setup the device UUID that contains our luks volume
	echo "# <target name>	<source device>		<key file>	<options>" > /etc/crypttab
	echo "$cfg_scadrial_device_luks PARTUUID=$pluks none luks,discard" >> /etc/crypttab

	# Setup the partitions
	eboot="$(blkid -s UUID -o value ${cfg_scadrial_device_name}1)"
	croot="$(blkid -s UUID -o value /dev/mapper/$cfg_scadrial_device_luks)"

	cat <<- EOF | tee /etc/fstab
	UUID=$croot  /                     btrfs   rw,${cfg_scadrial_device_optn},subvol=@                           0 0
	UUID=$croot  /boot                 btrfs   rw,${cfg_scadrial_device_optn},subvol=@boot,nosuid,nodev          0 0
	UUID=$eboot                             /boot/efi             vfat    rw,umask=0077                                           0 1
	UUID=$croot  /home                 btrfs   rw,${cfg_scadrial_device_optn},subvol=@home,nosuid,nodev          0 0
	UUID=$croot  /opt/mistborn_volumes btrfs   rw,${cfg_scadrial_device_optn},subvol=@data,nosuid,nodev,noexec   0 0
	UUID=$croot  /var                  btrfs   rw,${cfg_scadrial_device_optn},subvol=@var                        0 0
	UUID=$croot  /var/log              btrfs   rw,${cfg_scadrial_device_optn},subvol=@log,nosuid,nodev,noexec    0 0
	UUID=$croot  /var/log/audit        btrfs   rw,${cfg_scadrial_device_optn},subvol=@audit,nosuid,nodev,noexec  0 0
	UUID=$croot  /var/tmp              btrfs   rw,${cfg_scadrial_device_optn},subvol=@tmp,nosuid,nodev,noexec    0 0
	tmpfs                                      /tmp                  tmpfs   rw,noexec,nosuid,nodev                     0 0
	none                                       /run/shm              tmpfs   rw,noexec,nosuid,nodev                     0 0
	none                                       /dev/shm              tmpfs   rw,noexec,nosuid,nodev                     0 0
	none                                       /proc                 proc    rw,nosuid,nodev,noexec,relatime,hidepid=2  0 0

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

	kernel="linux-image-generic-hwe-${cfg_scadrial_dist_vers}"

	apt-get install -y --no-install-recommends "$kernel" linux-firmware cryptsetup initramfs-tools cryptsetup-initramfs \
	git ssh pciutils lvm2 iw hostapd gdisk btrfs-progs debootstrap parted fwupd net-tools bridge-utils iproute2 iptables \
	isc-dhcp-server ca-certificates figlet

	echo 'HOOKS="amd64_microcode base keyboard udev autodetect modconf block keymap encrypt btrfs filesystems"' > /etc/mkinitcpio.conf
	sed -i "s|#KEYFILE_PATTERN=|KEYFILE_PATTERN=/etc/luks/*.keyfile|g" /etc/cryptsetup-initramfs/conf-hook
	sed -i "/UMASK=0077/d" /etc/initramfs-tools/initramfs.conf
	echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

	mkdir -p /home/${cfg_scadrial_chroot_user}/.ssh && touch /home/${cfg_scadrial_chroot_user}/.ssh/authorized_keys
	chmod 700 /home/${cfg_scadrial_chroot_user}/.ssh && chmod 600 /home/${cfg_scadrial_chroot_user}/.ssh/authorized_keys

	#----------------------------------------------------------------------------
	figlet "Scadrial: Setup systemd-boot"
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
	options cryptdevice=PARTUUID=${pluks}:${cfg_scadrial_device_luks}:allow-discards root=/dev/mapper/${cfg_scadrial_device_luks} rootflags=subvol=@ rd.luks.options=discard rw
	EOF

	LATEST="$(cd /boot/ && ls -1t vmlinuz-* | head -n 1 | sed s/vmlinuz-//)"
	for FILE in config initrd.img System.map vmlinuz; do
		cp "/boot/${FILE}-${LATEST}" "/boot/efi/ubuntu/${FILE}"
	done

	update-initramfs -u -k all
	bootctl install --path=/boot/efi --no-variables

	#----------------------------------------------------------------------------
	figlet "Scadrial: Git repo setup"
	#----------------------------------------------------------------------------
	# Setup mistborn repository
	if [ -d mistborn ]; then
		(cd mistborn && git pull --rebase)
	else
		git clone https://gitlab.com/cyber5k/mistborn.git
	fi

	# Setup bats testing respsitory
	if [ -d bats ]; then
		(cd bats && git pull --rebase)
	else
		git clone https://github.com/sstephenson/bats.git
	fi

	# Setup hardening scripts repository
	if [ -d hardening ]; then
		(cd hardening && git reset --hard > /dev/null && git pull --rebase)
	else
		git clone https://github.com/konstruktoid/hardening.git
	fi
	# Update hardending scripts for scadrial
	sed -i "s|cp ./config/tmp.mount|#cp ./config/tmp.mount|g" ./hardening/scripts/08_fstab

	#----------------------------------------------------------------------------
	figlet "Scadrial: Wrap-up"
	log "The initial media configuration complete. Pending steps to complete on the host."
	echo "Exit chroot and umount our media, as follows:"
	#----------------------------------------------------------------------------
	
	# Enable wan interface to identify IP address
	cat <<- EOF > /etc/netplan/01-netcfg.yaml
	# This file describes the network interfaces available on your system
	# For more information, see netplan(5).
	network:
	  version: 2
	  renderer: networkd
	  ethernets:
	    ${cfg_scadrial_network_wan_iface}:
	      dhcp4: yes
	EOF
	
	netplan apply
	echo "exit"
	echo "sudo ./scadrial-setup.sh unmount"

	#----------------------------------------------------------------------------
	log "After booting into our new host, login as 'mistborn' user and run the following:"
	#----------------------------------------------------------------------------
	echo "cd scadrial"
	echo "sudo ./system_01_networking.sh"
	echo "sudo ./system_02_mistborn.sh"
	echo "Still work in progress..."
	echo "sudo ./system_03_hardening.sh"
	SEOF

	cat <<- 'SEOF' > system_01_networking.sh
	#!/bin/bash

	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	figlet "Scadrial: Setup networking..."
	#----------------------------------------------------------------------------

	#----------------------------------------------------------------------------
	echo "Setup networking interfaces"
	#----------------------------------------------------------------------------
	# Indentify interface hw addresses
	WAN_MAC=$((networkctl status ${cfg_scadrial_network_wan_iface} 2>/dev/null || networkctl status wan 2>/dev/null) | \
	  grep "HW Address" | sed "s/.*HW Address: //" | awk '{print $1}')
	LAN_MAC=$((networkctl status ${cfg_scadrial_network_lan_iface} 2>/dev/null || networkctl status lan 2>/dev/null) | \
	  grep "HW Address" | sed "s/.*HW Address: //" | awk '{print $1}')
	WAP_MAC=$((networkctl status ${cfg_scadrial_network_wap_iface} 2>/dev/null || networkctl status wap 2>/dev/null) | \
	  grep "HW Address" | sed "s/.*HW Address: //" | awk '{print $1}')
	
	# Get the real address for the public interface (wan)
	riface=$(networkctl -a status | awk '/DHCP4/ {print $1 $2}' | sed 's/Address://' | sed 's/(DHCP4)//')

	# Configure interfaces
	cat <<- EOF > /etc/netplan/01-netcfg.yaml
	# This file describes the network interfaces available on your system
	# For more information, see netplan(5).
	network:
	  version: 2
	  renderer: networkd
	  ethernets:
	    wan:
	      dhcp4: yes
	      match:
	        macaddress: ${WAN_MAC}
	      set-name: wan
	    lan:
	      dhcp4: no
	      dhcp6: no
	      match:
	        macaddress: ${LAN_MAC}
	      set-name: lan
	      # Prevent waiting for interface
	      optional: yes
	      addresses: [${cfg_scadrial_network_lan_addrs}]
	      nameservers:
	        addresses: [${riface}]
	    wap:
	      dhcp4: no
	      dhcp6: no
	      match:
	        macaddress: ${WAP_MAC}
	      set-name: wap
	      # Prevent waiting for interface
	      optional: yes
	      addresses: [${cfg_scadrial_network_wap_addrs}]
	      nameservers:
	        addresses: [${riface}]
	EOF

	netplan apply

	# NOTE: local networks should be up even if there is no carrier (aka: no client connected). This will
	# enable the DHCP server to always be running and serve IP addresses the moment you connect a client. 
	for FILE in lan wap; do
	  cp "/run/systemd/network/10-netplan-${FILE}.network" "/etc/systemd/network/10-netplan-${FILE}.network"
	  echo "ConfigureWithoutCarrier=yes" >> "/etc/systemd/network/10-netplan-${FILE}.network"
	done

	#----------------------------------------------------------------------------
	echo "Setup dhcp for local interfaces"
	#----------------------------------------------------------------------------
	# Configure the dhcp server settings for local connections.
	sed -i "s/.*INTERFACESv4.*/INTERFACESv4=\"lan wap\"/" /etc/default/isc-dhcp-server
	sed -i "s/.*INTERFACESv6.*/#INTERFACESv6=/" /etc/default/isc-dhcp-server
	systemctl disable isc-dhcp-server6
	
	cat <<- EOF > /etc/dhcp/dhcpd.conf
	default-lease-time 600;
	max-lease-time 7200;

	subnet ${cfg_scadrial_network_lan_addrs%.*}.0 netmask 255.255.255.0 {
	  range ${cfg_scadrial_network_lan_addrs%.*}.10 ${cfg_scadrial_network_lan_addrs%.*}.25;
	  option routers ${riface};
	  option domain-name-servers ${riface};
	}

	subnet ${cfg_scadrial_network_wap_addrs%.*}.0 netmask 255.255.255.0 {
	  range ${cfg_scadrial_network_wap_addrs%.*}.10 ${cfg_scadrial_network_wap_addrs%.*}.25;
	  option routers ${riface};
	  option domain-name-servers ${riface};
	}
	EOF

	#----------------------------------------------------------------------------
	echo "Setup wireless access point"
	#----------------------------------------------------------------------------
	cp hostapd.conf /etc/hostapd/hostapd.conf

	# Update configuration file
	sed -i "s/ssid=.*/ssid=${cfg_scadrial_network_wap_ssid}/" /etc/hostapd/hostapd.conf
	sed -i "s/wpa_passphrase=.*/wpa_passphrase=${cfg_scadrial_network_wap_pass}/" /etc/hostapd/hostapd.conf

	# Update service file
	sed -i 's/.*Restart.*/Restart=always/' /lib/systemd/system/hostapd.service
	sed -i 's/.*RestartSec.*/RestartSec=5/' /lib/systemd/system/hostapd.service

	systemctl enable hostapd
	systemctl enable systemd-networkd

	log "Reboot to ensure DHCP is set on local interfaces."
	SEOF

	cat <<- 'SEOF' > system_02_mistborn.sh
	#!/bin/bash
	source "lib/functions.sh"
	eval "$(parse_yaml scadrial-config.yaml "cfg_")"
	
	export MISTBORN_INSTALL_COCKPIT="${cfg_scadrial_chroot_cpit}"

	#----------------------------------------------------------------------------
	log "Install Mistborn..."
	#----------------------------------------------------------------------------
	sudo -E bash ./mistborn/scripts/install.sh

	log "Watch the installation happens with:"
	echo "sudo journalctl -xfu Mistborn-base"

	log "Type the following to get the admin Wireguard profile:"
	echo "sudo mistborn-cli getconf"
	SEOF

	cat <<- 'SEOF' > system_03_hardening.sh
	#!/bin/bash
	source "lib/functions.sh"
	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	log "Hardening setup"
	#----------------------------------------------------------------------------
	(cd bats && ./install.sh /usr/local)

	# Update our hardening configuration file
	export vpn_net=10.$(dd if=/dev/urandom bs=2 count=1 2>/dev/null | od -An -tu1 | sed -e 's|^ *||' -e 's|  *|.|g')
	export vpn_prt=$(echo $(od -An -N2 -i < /dev/urandom)  | xargs)
	(cd hardening && \
	sed -i "s|FW_ADMIN='127.0.0.1'|FW_ADMIN='${vpn_net}.0/24'|g" ubuntu.cfg && \
	sed -i "s|CHANGEME=''|CHANGEME='N'|g" ubuntu.cfg)
	# replace all instances of Mistborn 10.2.3.1 with ${vpn_net}.1
	sed -i "s|10.2.3.1|${vpn_net}.1|g" ./mistborn/scripts/install.sh

	# Run security initial assessment
	(cd hardening/tests/ && sudo bats . > ../bats-results1.log)

	# Harden the host
	(cd hardening && sudo -E bash ubuntu.sh)
	
	# Run security initial assessment
	(cd hardening/tests/ && sudo bats . > ../bats-results2.log)
	apt-get install -y git
	SEOF

	# Move the second step script to our media device
	sudo chmod +x scadrial-finalize.sh system_*.sh
	suds "mv scadrial-finalize.sh system_*.sh $cfg_scadrial_chroot_path/home/$cfg_scadrial_chroot_user/scadrial"
}