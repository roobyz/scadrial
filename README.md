# Scadrial

A secure process for standing up our own easy-to-manage Mistborn environment as a virtual home-lab.
# What is Scadrial

While the term Mistborn is inspired by a series of epic fantasy novels written by American author Brandon Sanderson, Scadrial is inspired by the name of the planet on which the Mistborn trilogy is set. Rather than living on a cloud-based virtual server, Scadrial is a local home-lab server where Mistborn lives.

Scadrial started as a passion project for building a secure home lab environment that includes file hosting, synchronization, media sharing and an office suite of applications. The Mistborn project very nicely handles those needs and more... with the creation of a virtual cloud services. We wanted a quick, automated, and reproducible process for standing up Mistborn in our home lab server environment(s).

# How Does it Work?

To install Mistborn onto our specified media, our bash script (_scadrial-setup.sh_) reads our configuration file (_scadrial-config.yaml_) which contains our desired settings, loads our library scripts which contain our reproducible functions, and reads the parameters we pass to script. The script leverages [debootstrap][05] in a [chroot][04] environment to generate an up-to-date and clean debian-based bootable media as required for Mistborn. Finally, the setup script will generate additional scripts and clone itself onto our specified media, so that we can use our newly created bootable USB stick to:  
* finalize setup on our actual system and install Mistborn on the existing media (i.e. USB stick), _**or**_
* clone our Scadrial setup so that we can install Mistborn on the harddrive or SSD on our target system

For agile experimentation, after our script successfully completes the debootstrap step, additional scripts commands allow for iterative repair or change to our desired setup.

# Quickstart

## System

Tested Operating Systems (in order of thoroughness):

* Ubuntu 20.04 LTS
* none other yet ;)

Tested Browsers:
* Firefox
* Brave

The default tests are run on a GIGABYTE QBiX-Pro-AMDA1605H-A1: 32GB RAM, 1xCPU (4 cores, 8 threads), 3TB NVME ssd. This system includes 2xGigabit Ethernet adapters and one wireless network adapter.

Primary Scadrial use-case: homelab setup of a high resource Mistborn installation including + Jitsi, Nextcloud, Jellyfin, Rocket.Chat, Home Assistant, OnlyOffice

## Installation

First, we insert our new install media (e.g. a USB stick). Note that this script will completely wipe our media. Ensure that any partitions are not mounted, and then run:

``` bash
sudo ./scadrial-setup.sh install [password]
```

Note that the [password] is optional and if not provided the script will ask you to enter a password on execution.

## Internet Access

To access our Mistborn environment from the Internet, two things need to happen:
1. a public endpoint must be configured for our Mistborn Wireguard client(s)
2. port forwarding will need to be configured on the NAT settings for our modem and/or routers.

One option is to forward _all_ incoming UDP traffic on our Internet facing NIC to the private router IP address of our Mistborn server. While ensuring that our firewall does not drop any UDP packets, Wireguard will silently drop all _invalid_ incoming packets by default. Another option is to allow only a specified list of UDP ports, however we would need to update our NAT settings for each new Wireguard port on every user device that is added or changed in Mistborn.

UDP traffic on our internal ethernet and wireless adapters that is bound for our Mistborn public IP address, may also be forwarded to our Mistborn private IP address. The benefit of this is that each client device would only need to be confgured once for Wireguard access, and our device can be connected via Wireguard to Mistborn full-time. This would enable transparent movement between our private and most public networks without needing to connect and reconnect our Wireguard client. On our default test system, we can forward udp packets from the _wap_ and _lan_ interfaces to our scadrial server (IP address on our router) that contains Mistborn, as follows:

``` bash
# Capture all inbound UPD traffic from our internal network and route to our scadrial server (i.e. 10.10.10.12)
sudo iptables -t nat -A PREROUTING -i wap -p udp -j DNAT --to-destination 10.10.10.12
sudo iptables -t nat -A PREROUTING -i lan -p udp -j DNAT --to-destination 10.10.10.12
```

# Work In Progress...

Although this is still a work in progress, it functions in my specified use-case. Additional work pending to make it a more robust general solution.

Todo:
* _loopdevice_: installation into loop image for use in a virtual machine
* _backup_: save existing installation settings
* _restore_: restore settings after replacing an existing installation 
* _hardening_: once functioning as desired, apply some [hardening][01] settings

References:
* [BATS][02] Security Testing Framework
* [Wireguard][03] Introduction

[01]: https://github.com/konstruktoid/hardening "Ubuntu Hardening by konstruktoid"
[02]: https://github.com/sstephenson/bats "Bash Automated Testing System"
[03]: https://www.thomas-krenn.com/en/wiki/Wireguard_Basics " Wireguard Basics"
[04]: https://wiki.archlinux.org/index.php/Chroot "Chroot Jails"
[05]: https://wiki.debian.org/Debootstrap "Debian Debootstrap"