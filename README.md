# Scadrial

A secure process for standing up your own easy to manage Mistborn environment as a virtual home-lab.
# What is Scadrial

While the term Mistborn is inspired by a series of epic fantasy novels written by American author Brandon Sanderson, Scadrial is inspired by the name of the planet on which the Mistborn trilogy is set. Rather than living on a cloud-based virtual server, Scadrial is a local home-lab server where Mistborn lives.

Scadrial started as a passion project for building a secure home lab environment that includes file hosting, synchronization, media sharing and an office suite of applications. The Mistborn project very nicely handles those needs and more... with the creation of a virtual cloud services. We wanted a quick, automated, and reproducible process for standing up Mistborn in our home lab server environment(s).

# Work In Progress...

Port Forwarding:
* Needs to be set up on modem NAT and router NAT
* One option is to forward all incoming UDP traffic on your internet facing NIC to your Mistborn IP address.
* Forward udp packets from wap and lan interfaces to scadrial server:

> iptables -t nat -A PREROUTING -i wap -p udp -j DNAT --to-destination 172.26.75.12  
iptables -t nat -A PREROUTING -i lan -p udp -j DNAT --to-destination 172.26.75.12

Hardening:
* https://github.com/konstruktoid/hardening
* https://github.com/sstephenson/bats
* https://www.thomas-krenn.com/en/wiki/WireGuard_Basics

