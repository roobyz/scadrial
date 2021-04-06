#!/bin/bash

# Config values for the media setup
# shellcheck disable=SC2154
echo "$cfg_scadrial_device_name $cfg_scadrial_device_pool $cfg_scadrial_device_optn $cfg_scadrial_device_luks" > /dev/null

# Config values for the new environment
# shellcheck disable=SC2154
echo "$cfg_scadrial_host_name $cfg_scadrial_host_user $cfg_scadrial_host_path $cfg_scadrial_dist_name $cfg_scadrial_dist_vers" > /dev/null

shelp() {
    echo "
    Usage:
      sudo ./scadrial-setup.sh COMMAND [OPTION]

    Notes:
      - using chroot, configures storage media for booting Ubuntu with encrypted btrfs
      - generates scripts to:
      - install mistborn personal virtual private cloud platform
      - apply additional security enhancements

    Commands:
        install                     Complete setup on unformatted media
        unmount	                    Unmount media
        debug                       Mount successfully formatted media
        repair                      Mount successfully formatted media and continue with setup
        h, help                     Print this help text
    
    Optional value:                 Password/Passphrase as desired
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
	media_part

	# Check whether the same base-name is used
	if [ "$(cd /dev/mapper/ && find . -maxdepth 1 -name 'crypt_root*' | wc -l)" == "0" ]; then
		# Name our new device
		luks_dev="${cfg_scadrial_device_luks}0"

		# Open luks device with passphrase parameter
		if ! suds "echo -n ${1//$/\\$} | cryptsetup --key-file=- luksOpen ${cfg_scadrial_device_name}${ppart}2 ${luks_dev}"; then
			err "Luks Unlock Failed"
		else
			echo "Luks Unlocked"
		fi
	else
		# Check name if the target luks device is already open
		if [ "$(lsblk "${cfg_scadrial_device_name}${ppart}2" | grep -c crypt_root)" == 0 ]; then
			# Increment luks device name sequence
			luks_dev="${cfg_scadrial_device_luks}$(cd /dev/mapper/ && find . -maxdepth 1 -name 'crypt_root*' | wc -l)"

			# Open luks device with passphrase parameter (accounting for any dollar signs)
			if ! suds "echo -n ${1//$/\\$} | cryptsetup --key-file=- luksOpen ${cfg_scadrial_device_name}${ppart}2 ${luks_dev}"; then
				err "Luks Unlock Failed"
			else
				echo "Luks Unlocked"
			fi
		fi 
	fi
}
