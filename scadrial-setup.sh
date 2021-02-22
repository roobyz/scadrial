#!/bin/bash
#############################################################################
# Prepare the Install Media
#----------------------------------------------------------------------------
# Load the source functions
#----------------------------------------------------------------------------
# shellcheck disable=SC1091
source "lib/functions.sh"

# Exit if no parameters are specified
if test $# -lt 1; then
    shelp
    err "Please specify a flag"
fi

eval "$(parse_yaml scadrial-config.yaml "cfg_")"
# Uncommend the following lines to debug YAML variables
# parse_yaml scadrial-config.yaml "cfg_"
# exit

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
		# shellcheck disable=SC2154
		if [ "$(df --output=target | grep -c "${cfg_droot_path}")" == "4" ]; then
			shelp
			log "The media is already configured. Please use 'force' or 'repair' parameter."
			exit 0
		fi
    	# Setup storage media/environment
		media_setup
        ;;
    force)
    	# Setup storage media/environment
		media_setup
        ;;
    unmount)
		media_reset
		exit 0
        ;;
    debug)
		media_reset
        media_mount
		for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_droot_path/$b"; done
		log "To enter the new system for debugging, type the following:"
		echo "sudo chroot $cfg_droot_path /bin/bash"
		exit 0
        ;;
    repair)
		media_reset
        media_mount
		for b in dev dev/pts proc sys; do suds "mount -B /$b $cfg_droot_path/$b"; done
        ;;
    *)
        shelp
        err "unknown argument '${1}'"
        ;;
    esac
    shift
done

#----------------------------------------------------------------------------
log "To enter and setup the new system, type the following:"
#----------------------------------------------------------------------------
echo "sudo chroot $cfg_droot_path /bin/bash"
echo "cd /root/scadrial/"
echo "./system_setup.sh"

system_setup