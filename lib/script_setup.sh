#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_host_name $cfg_scadrial_host_user $cfg_scadrial_host_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null


script_setup() {
	echo "Setup Scripts folder"
	suds "mkdir -p  $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial"
	suds "cp -r ./* $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial/"
	suds "cp $cfg_scadrial_host_path/etc/skel/.* $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/ 2> /dev/null"

	echo "Setup Chroot finalize script"
	cat <<- 'SEOF' > scadrial-finalize.sh
	#!/bin/bash

	#----------------------------------------------------------------------------
	# Load the source functions
	#----------------------------------------------------------------------------
	# shellcheck disable=SC1091
	source "lib/functions.sh"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	# Set passphrase if provided
	if [ -n "${1:-}" ]; then
		# Strip any newline from assigned variable
		passphrase="${1//$'\n'/}"
	fi

	get_pass
	
	#----------------------------------------------------------------------------
	log "Setup environment, user and access"
	#----------------------------------------------------------------------------
	useradd -M -s /bin/bash "$cfg_scadrial_host_user"
	echo "${cfg_scadrial_host_user}:${passphrase}" | chpasswd
	set_sudoer "$cfg_scadrial_host_user"

	# Set correct ownership to home
	suds "chown -R $cfg_scadrial_host_user:$cfg_scadrial_host_user /home/$cfg_scadrial_host_user"
	
	# Check whether nouveau driver should be blocked from loading
	if [ "$cfg_scadrial_host_nblk" == "y" ]; then
		sudo bash -c "echo blacklist nouveau > /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
		sudo bash -c "echo options nouveau modeset=0 >> /etc/modprobe.d/blacklist-nvidia-nouveau.conf"
	fi

	echo "$cfg_scadrial_host_name" > /etc/hostname
	echo LANG=en_US.UTF-8 > /etc/locale.conf
	ln -sf /usr/share/zoneinfo/${cfg_scadrial_host_tzne} /etc/localtime
	locale-gen en_US.UTF-8

	#----------------------------------------------------------------------------
	log "Configure partitions"
	#----------------------------------------------------------------------------
	media_part
	luks_dev="crypt_root$(lsblk ${cfg_scadrial_device_name}${ppart}2 | awk '/crypt_root/ {print $1}' | sed 's/.*crypt_root//')"
	pluks="$(blkid -s PARTUUID -o value ${cfg_scadrial_device_name}${ppart}2)"

	# Setup the device UUID that contains our luks volume
	echo "# <target name>	<source device>		<key file>	<options>" > /etc/crypttab
	echo "$luks_dev PARTUUID=$pluks none luks,discard" >> /etc/crypttab

	# Setup the partitions
	eboot="$(blkid -s UUID -o value ${cfg_scadrial_device_name}${ppart}1)"
	croot="$(blkid -s UUID -o value /dev/mapper/$luks_dev)"

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
	isc-dhcp-server ca-certificates curl figlet dosfstools

	echo 'HOOKS="amd64_microcode base keyboard udev autodetect modconf block keymap encrypt btrfs filesystems"' > /etc/mkinitcpio.conf
	sed -i "s|#KEYFILE_PATTERN=|KEYFILE_PATTERN=/etc/luks/*.keyfile|g" /etc/cryptsetup-initramfs/conf-hook
	sed -i "/UMASK=0077/d" /etc/initramfs-tools/initramfs.conf
	echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf

	mkdir -p /home/${cfg_scadrial_host_user}/.ssh && touch /home/${cfg_scadrial_host_user}/.ssh/authorized_keys
	chmod 700 /home/${cfg_scadrial_host_user}/.ssh && chmod 600 /home/${cfg_scadrial_host_user}/.ssh/authorized_keys

	#----------------------------------------------------------------------------
	figlet "Scadrial: Setup systemd-boot"
	#----------------------------------------------------------------------------
	# Set default boot menu
	mkdir -p /boot/efi/{ubuntu,loader/entries}
	cat <<- EOF > /boot/efi/loader/loader.conf
	default Ubuntu
	timeout 3
	editor 0
	EOF

	# Set console login parameters if specified in the config file
	if [ -z "${cfg_scadrial_host_cons_stty:-}" ]; then
		stty=""
	else
		# Enable virtual console and serial console
		if [ "${cfg_scadrial_host_cons_vtty}" == "y" ]; then
			vtty="console=tty1 "
		else
			vtty=""
			systemctl disable getty@tty1.service
		fi
		stty="${vtty}console=${cfg_scadrial_host_cons_stty}"
		systemctl enable serial-getty@${cfg_scadrial_host_cons_stty%%,*}.service
	fi

	# Define boot menu parameters
	cat <<- EOF > /boot/efi/loader/entries/ubuntu.conf
	title   Ubuntu
	linux   /ubuntu/vmlinuz
	initrd  /ubuntu/initrd.img
	options cryptdevice=PARTUUID=${pluks}:${luks_dev}:allow-discards root=/dev/mapper/${luks_dev} rootflags=subvol=@ rd.luks.options=discard ro ${stty}
	EOF

	# Copy updated kernel files to boot partition
	update-initramfs -u -k all
	LATEST="$(cd /boot/ && ls -1t vmlinuz-* | head -n 1 | sed s/vmlinuz-//)"
	for FILE in config initrd.img System.map vmlinuz; do
		cp "/boot/${FILE}-${LATEST}" "/boot/efi/ubuntu/${FILE}"
	done

	# Install systemd-boot to our efi partition
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

	# Set correct ownership to new home folders
	suds "chown -R $cfg_scadrial_host_user:$cfg_scadrial_host_user /home/$cfg_scadrial_host_user"

	log "The initial media configuration complete. Pending steps to complete on the host."
	echo "Exit chroot and umount our media, as follows:"
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

	echo "Setup Networking script"
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

	echo "Setup Mistborn install script"
	cat <<- 'SEOF' > system_02_mistborn.sh
	#!/bin/bash
	source "lib/functions.sh"
	eval "$(parse_yaml scadrial-config.yaml "cfg_")"
	
	export MISTBORN_DEFAULT_PASSWORD="${passphrase//$/\\$}"
	export MISTBORN_INSTALL_COCKPIT="${cfg_scadrial_host_cpit}"

	#----------------------------------------------------------------------------
	log "Install Mistborn..."
	#----------------------------------------------------------------------------
	sudo -E bash ./mistborn/scripts/install.sh

	log "Watch the installation happens with:"
	echo "sudo journalctl -xfu Mistborn-base"

	log "Type the following to get the admin Wireguard profile:"
	echo "sudo mistborn-cli getconf"
	SEOF

	echo "Setup Hardening script"
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
	suds "mv scadrial-finalize.sh system_*.sh $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial"
}