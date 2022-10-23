#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_host_name $cfg_scadrial_host_user $cfg_scadrial_host_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null

setup_chroot_environment() {
	echo "Setup Scripts folder"
	suds "mkdir -p  $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial"
	suds "cp -r ./* $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial/"
	suds "cp -r ./.env $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial/"
	suds "cp $cfg_scadrial_host_path/etc/skel/.* $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/ 2> /dev/null"

	echo "Setup Chroot finalize script"
	cat <<- 'SEOF' > scadrial-finalize.sh
	#!/bin/bash

	#----------------------------------------------------------------------------
	# Load the source functions
	#----------------------------------------------------------------------------
	# shellcheck disable=SC1091
	source "lib/functions.sh"
	# shellcheck disable=SC1091
	source "lib/setup_media.sh"
	# shellcheck disable=SC1091
	source "lib/setup_scripts.sh"
	source ".env"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"
	
	#----------------------------------------------------------------------------
	log "Setup environment, user and access"
	#----------------------------------------------------------------------------
	export PATH=/usr/sbin:$PATH
	useradd -M -s /bin/bash "$cfg_scadrial_host_user"
	echo "${cfg_scadrial_host_user}:${SCADRIAL_KEY}" | chpasswd
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
	echo "deb http://archive.ubuntu.com/ubuntu ${cfg_scadrial_dist_name} main universe" > /etc/apt/sources.list
	echo "deb http://archive.ubuntu.com/ubuntu ${cfg_scadrial_dist_name}-updates main universe" >> /etc/apt/sources.list
	echo "deb http://archive.ubuntu.com/ubuntu ${cfg_scadrial_dist_name}-backports main universe" >> /etc/apt/sources.list
	apt-get update && apt-get -y upgrade --no-install-recommends

	# header="linux-headers-${cfg_scadrial_dist_vers}"

	log "Install Additional Applications"
	apt-get install -y --no-install-recommends linux-image-generic linux-firmware cryptsetup initramfs-tools cryptsetup-initramfs git ssh pciutils lvm2 iw gdisk btrfs-progs debootstrap parted fwupd net-tools procps bridge-utils iproute2 iptables hostapd isc-dhcp-server ca-certificates curl figlet dosfstools

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

	# Setup Realtek 8812AU driver respsitory
	# if [ -d r8812au ]; then
	# 	(cd r8812au && git pull --rebase)
	# else
	# 	git clone https://github.com/aircrack-ng/rtl8812au.git r8812au
	# 	# git clone https://github.com/morrownr/8812au-20210629.git r8812au
	# fi

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
	    ${cfg_scadrial_network_wan0_iface}:
	      dhcp4: yes
	EOF
	
	netplan apply

	# Set correct ownership to new home folders
	suds "chown -R $cfg_scadrial_host_user:$cfg_scadrial_host_user /home/$cfg_scadrial_host_user"

	log "The initial media configuration complete. Pending steps to complete on the host."
	echo "chroot exited... Umount the media, as follows:"
	echo "sudo ./scadrial-setup.sh unmount"

	#----------------------------------------------------------------------------
	log "After booting into our new host, login as 'mistborn' user and run the following:"
	#----------------------------------------------------------------------------
	echo "cd scadrial"
	echo "sudo systemctl restart systemd-networkd"
	echo "sudo ./host_01_networking.sh"
	echo "sudo ./host_02_mistborn.sh"
	echo "Still work in progress..."
	echo "sudo ./host_03_hardening.sh"
	SEOF

	# Move the script to our media device
	sudo chmod +x scadrial-finalize.sh
	suds "mv scadrial-finalize.sh $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial"

	#----------------------------------------------------------------------------
	log "Entering the new host chroot system and finalizing our setup..."
	#----------------------------------------------------------------------------
	HOST_USER=${cfg_scadrial_host_user} sudo -E chroot $cfg_scadrial_host_path /bin/bash -c \
	    'cd /home/${HOST_USER}/scadrial; ./scadrial-finalize.sh ${SCADRIAL_KEY}; exit'
	rm ${cfg_scadrial_host_path}/home/${cfg_scadrial_host_user}/scadrial/scadrial-finalize.sh
}

stage_host_scripts() {
	echo "Setup Networking script"
	cat <<- 'SEOF' > host_01_networking.sh
	#!/bin/bash

	# shellcheck disable=SC1091
	source "lib/functions.sh"
	# shellcheck disable=SC1091
	source "lib/setup_media.sh"
	# shellcheck disable=SC1091
	source "lib/setup_scripts.sh"
	source ".env"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"

	#----------------------------------------------------------------------------
	figlet "Scadrial: Setup networking..."
	#----------------------------------------------------------------------------
	setIface() {
	  parse_yaml scadrial-config.yaml "cfg_" | while IFS= read -r line; do
	    name=${line%%=*}
	    value=${line#*=}

	    if [[ $name == "cfg_scadrial_network"* ]]; then
	      IFS='_' read -ra my_array <<< "$name"

	      if [ ${my_array[4]} == "enabled" ]; then
	        if [[ $value == *"true"* ]]; then
	          DEV=${my_array[3]}
	        else
	          DEV="None"
	        fi
	      fi

	      if [[ $DEV != "None" ]]; then
	        # Get the interface
	        if [[ ${my_array[4]} == "iface" ]]; then
	          if [[ $DEV == "wan0" ]]; then
	            echo "$DEV=$(echo $value | tr -d '(")')"
	          else 
	            iface=$(echo $value | tr -d '(")')
	          fi
	        fi

	        # Get any addresses
	        if [[ ${my_array[4]} == "addrs" ]]; then
	          echo "$DEV=${iface},$(echo $value | tr -d '(")')"
	        fi
	      fi
	    fi
	  done
	}

	ifaceArray=($(setIface))

	#----------------------------------------------------------------------------
	echo "Setup networking interfaces"
	#----------------------------------------------------------------------------
	# Get the real address for the public interface (wan)
	riface=$(networkctl -a status | awk '/DHCP4/ {print $1 $2}' | sed 's/Address://' | sed 's/(DHCP4)//' | head -n 1)

	# Indentify interface hw addresses
	for p in "${ifaceArray[@]}"; do
	  IFS='=' read -ra iface <<< "$p"
		
	  if [[ ${iface[0]} == "wan0" ]]; then
	    MAC=$((networkctl status ${iface[1]} 2>/dev/null || networkctl status ${iface[0]} 2>/dev/null) | \
	      grep "HW Address" | sed "s/.*HW Address: //" | awk '{print $1}')
		
			cat <<- EOF > /etc/netplan/01-netcfg.yaml
			# This file describes the network interfaces available on your system
			# For more information, see netplan(5).
			network:
			  version: 2
			  renderer: networkd
			  ethernets:
			    wan0:
			      dhcp4: yes
			      match:
			        macaddress: ${MAC}
			      set-name: wan0
			EOF

			cat <<- EOF > /etc/dhcp/dhcpd.conf
			default-lease-time 600;
			max-lease-time 7200;
			EOF

	  else
	    IFS=',' read -ra device <<< "${iface[1]}"
	    MAC=$((networkctl status ${device[0]} 2>/dev/null || networkctl status ${iface[0]} 2>/dev/null) | \
	      grep "HW Address" | sed "s/.*HW Address: //" | awk '{print $1}')
		
			cat <<- EOF >> /etc/netplan/01-netcfg.yaml
			    ${iface[0]}:
			      dhcp4: no
			      dhcp6: no
			      match:
			        macaddress: ${MAC}
			      set-name: ${iface[0]}
			      # Prevent waiting for interface
			      optional: yes
			      addresses: [${device[1]}]
			      nameservers:
			        addresses: [${riface}]
			EOF

	    cat <<- EOF >> /etc/dhcp/dhcpd.conf

			subnet ${device[1]%.*}.0 netmask 255.255.255.0 {
			  range ${device[1]%.*}.10 ${device[1]%.*}.25;
			  option routers ${riface};
			  option domain-name-servers ${riface};
			}
			EOF
	  fi
	done

	netplan apply

	# NOTE: local networks should be up even if there is no carrier (aka: no client connected). This will
	# enable the DHCP server to always be running and serve IP addresses the moment you connect a client. 
	for p in "${ifaceArray[@]}"; do
	  IFS='=' read -ra iface <<< "$p"
		
	  if [[ ${iface[0]} != "wan"* ]]; then
	    cp "/run/systemd/network/10-netplan-${iface[0]}.network" "/etc/systemd/network/10-netplan-${iface[0]}.network"
	    echo "ConfigureWithoutCarrier=yes" >> "/etc/systemd/network/10-netplan-${iface[0]}.network"
	    sed -i "s/LinkLocalAddressing=ipv6/LinkLocalAddressing=ipv4/" "/etc/systemd/network/10-netplan-${iface[0]}.network"
	    devNames+="${iface[0]} "
	  fi
	done

	#----------------------------------------------------------------------------
	echo "Setup dhcp for local interfaces"
	#----------------------------------------------------------------------------
	# Configure the dhcp server settings for local connections.
	sed -i "s/.*INTERFACESv4.*/INTERFACESv4=\"$(echo ${devNames} | xargs)\"/" /etc/default/isc-dhcp-server
	sed -i "s/.*INTERFACESv6.*/#INTERFACESv6=/" /etc/default/isc-dhcp-server
	systemctl disable isc-dhcp-server6
	
	#----------------------------------------------------------------------------
	echo "Setup wireless access point"
	#----------------------------------------------------------------------------
	# Update service file
	sed -i 's/.*Restart=.*/Restart=always/' /lib/systemd/system/hostapd.service
	sed -i 's/.*RestartSec=.*/RestartSec=5/' /lib/systemd/system/hostapd.service

	for d in wap0 wap1; do
	  # Check whether device is enabled
	  venabl=cfg_scadrial_network_${d}_enabled
	  if [[ ${!venabl} == "true" ]]; then
	    devcfg=/etc/hostapd/${d}.conf
	    cp ./hostapd/hostapd.conf ${devcfg}
	
	    vssid=cfg_scadrial_network_${d}_ssid
	    vcntry=cfg_scadrial_network_${d}_cntry
	    vchanl=cfg_scadrial_network_${d}_channel
	    vhtcap=cfg_scadrial_network_${d}_ht_capab
	    vpmode=cfg_scadrial_network_${d}_mode
	    vvthcp=cfg_scadrial_network_${d}_vht_capab
	    vwidth=cfg_scadrial_network_${d}_width
	    vctri0=cfg_scadrial_network_${d}_vht_center_idx0
	    vctri1=cfg_scadrial_network_${d}_vht_center_idx1
	    vkmgmt=cfg_scadrial_network_${d}_key_mgmt
	    vwpass=${d}_pass

	    sed -i "s/^ssid=.*/ssid=${!vssid}/" ${devcfg}
	    sed -i "s/^interface=.*/interface=${d}/" ${devcfg}
	    sed -i "s/^country_code=.*/country_code=${!vcntry}/" ${devcfg}
	    sed -i "s/^channel=.*/channel=${!vchanl}/" ${devcfg}
	    sed -i "s/^ht_capab=.*/ht_capab=${!vhtcap}/" ${devcfg}

	    if [[ ${!vpmode} == 'vht' ]]; then
	      sed -i "s/^hw_mode=.*/hw_mode=a/" ${devcfg}
	      sed -i "s/^ieee80211ac=.*/ieee80211ac=1/" ${devcfg}
	      sed -i "s/^require_vht=.*/require_vht=1/" ${devcfg}
	    else
	      sed -i "s/^hw_mode=.*/hw_mode=g/" ${devcfg}
	      sed -i "s/^ieee80211ac=.*/ieee80211ac=0/" ${devcfg}
	      sed -i "s/^require_vht=.*/require_vht=0/" ${devcfg}
	    fi

	    sed -i "s/^vht_capab=.*/vht_capab=${!vvthcp}/" ${devcfg}

	    if [[ ${!vchanl} == '0' ]]; then
	      sed -i "s/^vht_oper_chwidth=.*/#vht_oper_chwidth=${!vwidth}/" ${devcfg}
	      sed -i "s/^vht_oper_centr_freq_seg0_idx=.*/#vht_oper_centr_freq_seg0_idx=${!vctri0}/" ${devcfg}
	      sed -i "s/^vht_oper_centr_freq_seg1_idx=.*/#vht_oper_centr_freq_seg1_idx=${!vctri1}/" ${devcfg}
	    else
	      sed -i "s/^vht_oper_chwidth=.*/vht_oper_chwidth=${!vwidth}/" ${devcfg}
	      sed -i "s/^vht_oper_centr_freq_seg0_idx=.*/vht_oper_centr_freq_seg0_idx=${!vctri0}/" ${devcfg}
	      sed -i "s/^vht_oper_centr_freq_seg1_idx=.*/vht_oper_centr_freq_seg1_idx=${!vctri1}/" ${devcfg}
	    fi

	    sed -i "s/^wpa_key_mgmt=.*/wpa_key_mgmt=${!vkmgmt}/" ${devcfg}
	    sed -i "s/^wpa_passphrase=.*/wpa_passphrase=${!vwpass}/" ${devcfg}
	  fi

	  systemctl enable hostapd@${d}
	done

	systemctl disable hostapd
	systemctl enable systemd-networkd

	#----------------------------------------------------------------------------
	echo "Setup networkd-dispatcher"
	#----------------------------------------------------------------------------
	# Create folders for the systemd-networkd operational states:
	# https://www.freedesktop.org/software/systemd/man/networkctl.html

	sudo mkdir -p /etc/networkd-dispatcher/{routable,dormant,no-carrier,off,carrier,degraded,configuring,configured}.d

	cat <<- EOF | tee /etc/networkd-dispatcher/routable.d/isc-dhcp-server && sudo chmod +x /etc/networkd-dispatcher/routable.d/isc-dhcp-server
	#!/bin/sh
	# After wireless interfaces come up (routable), trigger dhcp server restart to
	# activate dynamic IPv4 assignment after a few seconds.

	if [ "\$IFACE" = "wap0" ]; then
		sleep 5
		echo "DHCP Restarting for WAP... \$IFACE"
		systemctl restart isc-dhcp-server.service
	fi

	EOF

	#----------------------------------------------------------------------------
	echo "Setup port forwarding"
	#----------------------------------------------------------------------------
	rtrsvc=/etc/systemd/system/scadrial-router.service

	cat <<- EOF > ${rtrsvc}
	[Unit]
	Description=Scadrial Router Service
	After=multi-user.target

	[Service]
	Type=oneshot
	RemainAfterExit=true

	# Pre start: port forward udp packets from interfaces to router
	# Post stop: clean up the udp port forwarding to router
	ExecStart=/sbin/iptables -t nat -A PREROUTING -i lan0 -p udp -j DNAT --to-destination ${riface}
	ExecStop=/sbin/iptables -t nat -D PREROUTING -i lan1 -p udp -j DNAT --to-destination ${riface}

	EOF

	for d in wap0 wap1; do
	  # Check whether device is enabled
	  venabl=cfg_scadrial_network_${d}_enabled
	  if [[ ${!venabl} == "true" ]]; then
	    cat <<- EOF >> ${rtrsvc}
	    ExecStart=/sbin/iptables -t nat -A PREROUTING -i ${d} -p udp -j DNAT --to-destination ${riface}
	    ExecStop=/sbin/iptables -t nat -D PREROUTING -i ${d} -p udp -j DNAT --to-destination ${riface}
	    
	    EOF
	  fi
	done

	cat <<- EOF >> ${rtrsvc}
	[Install]
	WantedBy=graphical.target	    
	EOF

	systemctl enable scadrial-router

	log "Reboot to ensure DHCP is set on local interfaces."
	SEOF

	echo "Setup Mistborn install script"
	cat <<- 'SEOF' > host_02_mistborn.sh
	#!/bin/bash
	
	# shellcheck disable=SC1091
	source "lib/functions.sh"
	# shellcheck disable=SC1091
	source "lib/setup_media.sh"
	# shellcheck disable=SC1091
	source "lib/setup_scripts.sh"
	source ".env"

	eval "$(parse_yaml scadrial-config.yaml "cfg_")"
	
	export MISTBORN_DEFAULT_PASSWORD="${SCADRIAL_KEY//$/\\$}"
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
	cat <<- 'SEOF' > host_03_hardening.sh
	#!/bin/bash

	# shellcheck disable=SC1091
	source "lib/functions.sh"
	# shellcheck disable=SC1091
	source "lib/setup_media.sh"
	# shellcheck disable=SC1091
	source "lib/setup_scripts.sh"
	source ".env"

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

	# Move the scripts to our media device
	sudo chmod +x host_*.sh
	suds "mv host_*.sh $cfg_scadrial_host_path/home/$cfg_scadrial_host_user/scadrial"
}
