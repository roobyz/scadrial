#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

#############################################################################
# Prepare the Install Media
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

# Exit if no parameters are specified
if test $# -lt 1; then
    shelp
    err "Please specify a flag"
fi

eval "$(parse_yaml scadrial-config.yaml "cfg_")"
# Uncommend the following lines to debug YAML variables
# parse_yaml scadrial-config.yaml "cfg_"
# exit

# shellcheck disable=SC2154
echo "$cfg_scadrial_host_user $cfg_scadrial_host_path" > /dev/null

declare -a pre_reqs=("sudo" "cryptsetup" "ssh-keygen" "sgdisk" "partprobe" "debootstrap" "wipefs")
for i in "${pre_reqs[@]}"; do
	cmd_check "$i"
done

# Process the specified parameters
while test $# -gt 0; do
    case "${1}" in
    h|help)
      shelp
      exit 0
      ;;
    install)
		# Check if meadia already configured.
		if [ ! "$(df --output=target | grep -c "${cfg_scadrial_host_path}")" == "0" ]; then
			log "The media is already mounted."
			read -p "Would you like to force install? (y/n): " -r schk
			if [ ! "$schk" == "y" ]; then
				echo "Exiting..."
				exit 0
			fi
		fi
		# Setup storage media/environment (partitioning/deboostrap)
		media_setup
		shift
      ;;
    unmount)
		media_reset
		exit 0
      ;;
    debug)
		media_reset
		media_mount
		for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_scadrial_host_path/$b"; done
		log "To enter the new system for debugging, type the following:"
		echo "sudo chroot $cfg_scadrial_host_path /bin/bash" && echo
		exit 0
      ;;
    repair)
		# This skips the repartition/deboostrap steps as completed on install
		media_reset
		media_mount
		for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_scadrial_host_path/$b"; done
		shift
      ;;
    scripts)
		# This step only reconfigures the host scripts
		# Check if meadia already configured.
		if [[ ! "$(df --output=target | grep -c "${cfg_scadrial_host_path}")" != "0" ]]; then
			log "The media is not mounted. First run the debug setup."
			exit 1
		fi
		stage_host_scripts
		exit 0
      ;;
    *)
		shelp
		err "unknown argument '${1}'"
      ;;
    esac
    shift
done

#----------------------------------------------------------------------------
log "Generate final system scripts."
#----------------------------------------------------------------------------
setup_chroot_environment
stage_host_scripts
