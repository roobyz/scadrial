# Scadrial

A secure process for standing up our own easy-to-manage debian-based environment with Mistborn as a home-lab service.
# What is Scadrial

While the term Mistborn is inspired by a series of epic fantasy novels written by American author Brandon Sanderson, Scadrial is inspired by the name of the planet on which the Mistborn trilogy is set. Rather than living on a cloud-based virtual server, Scadrial is a local home-lab server where Mistborn lives.

Scadrial started as a passion project for building a secure home lab environment that includes file hosting, synchronization, media sharing and an office suite of applications. The Mistborn project very nicely handles those needs and more... with the creation of a virtual cloud services. We wanted a quick, automated, and reproducible process for standing up Mistborn in our home lab server environment(s).

# How Does it Work?

To install Mistborn onto our specified media, our bash script (_scadrial-setup.sh_) reads our configuration file (_scadrial-config.yaml_) which contains our desired settings, loads our library scripts which contain our reproducible functions, and reads the parameters we pass to script. The script leverages [debootstrap][05] in a [chroot][04] environment to generate an up-to-date and clean debian-based bootable media as required for Mistborn. Finally, the setup script will generate additional scripts and clone itself onto our specified media, so that we can use our newly created bootable media to:  
* finalize setup on our actual system and install Mistborn on the existing media (i.e. USB stick, IMG file), _**or**_
* clone our Scadrial setup so that we can install Mistborn on the harddrive or SSD on our target system

For agile experimentation, after our script successfully completes the debootstrap step, additional scripts commands allow for iterative repair or change to our desired setup. This way we don't need to restart from the beginning every time we want to make adjustments.

# Quickstart

## System

Tested Operating Systems (in order of thoroughness):

* Ubuntu 20.04 LTS
* none other yet ;)

Tested Browsers:
* Firefox
* Brave

The default tests are run on:
* a x86-64 KVM virtual machine:
  - using IMG file as boot media or installation media
  - with UEFI firmware
* a GIGABYTE QBiX-Pro-AMDA1605H-A1 server: 
  - 32GB RAM, 1xCPU (4 cores, 8 threads), 3TB NVME ssd
  - includes 2xGigabit Ethernet adapters and one wireless network adapter

Primary Scadrial use-case: 
* homelab setup on a virtual machine, personal computer, or server
* for high resource Mistborn installation including + Jitsi, Nextcloud, Jellyfin, Rocket.Chat, Home Assistant, OnlyOffice

## Installation

### Part One: Configuration

All the key configuration settings can be updated on our yaml file (_scadrial-config.yaml_). It is important to update this for our specific use case before proceeding to the next step. The script will read the yaml and create variables that will be used for each of the following steps. Variables that are not applicable should be left blank. The following table illustrates how the variables might be updated for three use-cases:

variable | USB or Disk with Serial Console | USB or Disk with Monitor | Image File for Virtual Machine
----- | ----- | ----- | -----
[cfg_scadrial_dist_name](a "Debian-based Distribiton Name") | focal | focal | focal 
[cfg_scadrial_dist_vers](a "Distribution Version Number") | 20.04 | 20.04 | 20.04
[cfg_scadrial_device_loop](a "Loop Device Desired. A file that acts as a block-based device. (i.e. ISO or IMG file)") | n | n | **`y`**
[cfg_scadrial_device_loop_file](a "Loop File Name") | | | **`scadrial.img`**
[cfg_scadrial_device_loop_size](a "Loop File Size") | | | **`8G`**
[cfg_scadrial_device_name](a "Device Name") | /dev/sda | /dev/sda | **`/dev/loop0`**
[cfg_scadrial_device_pool](a "Mount path for btrfs pool setup") | /mnt/btrfs_pool | /mnt/btrfs_pool | /mnt/btrfs_pool
[cfg_scadrial_device_optn](a "fstab parameters for btrfs filesystem") | compress=zstd | compress=zstd | compress=zstd
[cfg_scadrial_device_luks](a "Name of luks crypt device. Sequence number will be added to avoid duplicate values") | crypt_root | crypt_root | crypt_root
[cfg_scadrial_host_name](a "Hostname for the 'machine'") | scadrial | scadrial | scadrial
[cfg_scadrial_host_user](a "user for our machine. Note mistborn requires a user name 'mistborn'") | mistborn | mistborn | mistborn
[cfg_scadrial_host_path](a "Mount path for our chroot jail") | /mnt/debootpath | /mnt/debootpath | /mnt/debootpath
[cfg_scadrial_host_tzne](a "Our local time zone") | America/Los_Angeles | America/Los_Angeles | America/Los_Angeles
[cfg_scadrial_host_cons_vtty](a "Virtual Console desired. Getty console access with monitor and keyboard.") | **`n`** | y | y
[cfg_scadrial_host_cons_stty](a "Serial Console settings. Serial console will not be configured if left blank.") | **`ttyS0,115200n8`** | |
[cfg_scadrial_host_cpit](a "Mistborn Cockpit installation desired") | y | y | y
[cfg_scadrial_host_nblk](a "nouveau driver should be blocked") | y | y | y
[cfg_scadrial_network_wan0_iface](a "Interface name for WAN device (i.e internet access). Must use the name from our machine.") | eno1 | eno1 | eno1
[cfg_scadrial_network_lan0_iface](a "Interface name for LAN device (i.e. local access). Must use the name from our machine") | enp4s0 | enp4s0 | enp4s0
[cfg_scadrial_network_lan0_addrs](a "DHCPv4 address range for our LAN") | 10.16.35.1/24 | 10.16.35.1/24 | 10.16.35.1/24
[cfg_scadrial_network_wlan0_iface](a "Interface name for our Wireless Access Point. Must use the name from our machine") | wlp2s0 | wlp2s0 | wlp2s0
[cfg_scadrial_network_wlan0_addrs](a "DHCPv4 address range for our WAP") | 10.16.45.1/24 | 10.16.45.1/24 | 10.16.45.1/24
[cfg_scadrial_network_wlan0_pass](a "WAP passphrase") | mypass_1234 | mypass_1234 | mypass_1234
[cfg_scadrial_network_wlan0_ssid](a "WAP SSID Name") | my_wifi_spot | my_wifi_spot | my_wifi_spot

### Part Two: Setup Scadrial Boot Media

First, we insert our new media device (e.g. USB stick) into our machine, or configure our loop device file (e.g IMG file) for our virtual machine. Then we run:

``` bash
sudo ./scadrial-setup.sh install [password]
```

Scadrial will completely wipe and partition our media, and then install our Debian-based Linux distribution. The [password] is an optional command line parameter, however if not provided you will be asked to enter one when appropriate.

Our Linux distribution will be installed using `deboostrap` with some finalization scripts to finish our setup. Afterward, we will `chroot` into our system and finalize our setup, by running the following steps:

``` bash
sudo chroot /mnt/debootpath /bin/bash
cd /home/mistborn/scadrial
./scadrial-finalize.sh  [password]
```

This will install additional required software, configure the environment and mistborn user, and make the media bootable. Also, Mistborn will be staged for installation using our yaml configuration file. Upon completion, we can exit the chroot environment and then boot into our new media.

### Part Three: Install Scadrial on Our "Machine"

Once we have booted into our media, we can install Mistborn on our machine. If we would like to install on a virtual machine, then the boot media created in step one should be a disk image created with a loop device, and the virtual machine should be configured for UEFI boot.

After booting Scadrial on our new host machine, login as the 'mistborn' user.

If networking is not running then restart it as follows:

``` bash
sudo systemctl restart systemd-networkd
```

With the network running, install system updates and then reboot the system:

``` bash
sudo apt-get update && sudo apt-get -y dist-upgrade
```

Finally, run the following to install/setup Mistborn on our desired media (i.e USB stick, SSD, NVMe, or IMG file):

``` bash
cd scadrial
sudo ./system_01_networking.sh
sudo ./system_02_mistborn.sh
```

### Cloning Install: An Example

After booting into our media, rather than completing the steps from Part Three, we can clone Scadrial onto a new disk drive (i.e. ssd, virtual disk, etc.). After which we can update the cloned version of our yaml file and run cloned versions of the scripts on the new disk drive.

For example, say we want to install Scadrial onto a _virtual machine_:
1. Initially, we update our yaml file to make a bootable image file (i.e. the example from the 3rd column above).
2. Then we complete the Part Two step to build the bootable loop file (i.e. IMG file).
3. Then we mount the IMG file onto a virtual machine as a disk.
4. After booting the virtual machine, we can update our cloned yaml file for installing onto a disk rather than a loop file (i.e. either example from the 1st or 2nd column above).
5. Then we can repeat the steps from Part 2 and Part 3 to finalize setup onto the machine's disk (e.g. /dev/vda).

The benefit of the cloning approach on a virtual machine is that the standard virtual machine drive format might be faster or more space efficient. The benefit of using the cloning approach on an actual physcial machine is that an NVMe or SSD drive might have significantly more storage or performance when compared to a USB drive. 

## Internet Access

To access our Mistborn environment from the Internet, three things need to happen:
1. Wireguard must be setup with a public endpoint on Mistborn and our client machine (i.e. phone, laptop, etc.)
2. port forwarding will need to be configured on the NAT settings for our modem and/or routers.
    - One option is to forward _all_ incoming UDP traffic on our Internet facing NIC to the private router IP address of our Mistborn server. While ensuring that our firewall does not drop any UDP packets, Wireguard will silently drop all _invalid_ incoming packets by default. Another option is to allow only a specified list of UDP ports, however we would need to update our NAT settings for each new Wireguard port on every user device that is added or changed in Mistborn.
    - UDP traffic on our internal ethernet and wireless adapters that is bound for our Mistborn public IP address, may also be forwarded to our Mistborn private IP address. The benefit of this is that each client device would only need to be confgured once for Wireguard access, and our device can be connected via Wireguard to Mistborn full-time. This would enable transparent movement between our private and most public networks without needing to connect and reconnect our Wireguard client. On our default test system, we can forward udp packets from the _wlan0_ and _lan0_ interfaces to our scadrial server (IP address on our router) that contains Mistborn, as follows:

``` bash
# Capture all inbound UPD traffic from our internal network and route to our scadrial server (i.e. 10.10.10.12)
sudo iptables -t nat -A PREROUTING -i wlan0 -p udp -j DNAT --to-destination 10.10.10.12
sudo iptables -t nat -A PREROUTING -i lan0 -p udp -j DNAT --to-destination 10.10.10.12
```

# Work In Progress...

Although this is still a work in progress, it functions in my specified use-case. Additional work pending to make it a more robust general solution.

### Todo:
* ~~_loopdevice_: Update scripts to setup and control loop devices images for use on virtual machines~~ **_done_**
* _backup_: save existing installation settings
* _restore_: restore settings after replacing an existing installation
  * cp /etc/wireguard/*.conf
  * cp /etc/systemd/system/multi-user.target.wants/wg-quick*.service
* _hardening_: once functioning as desired, apply some [hardening][01] settings

### References:
* [BATS][02] Security Testing Framework
* [Wireguard][03] Introduction

[01]: https://github.com/konstruktoid/hardening "Ubuntu Hardening by konstruktoid"
[02]: https://github.com/sstephenson/bats "Bash Automated Testing System"
[03]: https://www.thomas-krenn.com/en/wiki/Wireguard_Basics " Wireguard Basics"
[04]: https://wiki.archlinux.org/index.php/Chroot "Chroot Jails"
[05]: https://wiki.debian.org/Debootstrap "Debian Debootstrap"
