#!/bin/sh
# This script runs at startup from /etc/init.d/fmstartup
# when fm.startup.firstboot is 1

# random_key generates a random string N characters
# of the specified length (default 16)
# The string comes from the set of alphanumerics,
# skipping 'Ll10O' to # make it readable
# NOTE: this password is used as the root password for
# mesh nodes, as well as the password for the mesh
# itself
random_key() {
	tr -dc A-NP-Za-km-z2-9 </dev/urandom | head -c ${1:-16}
}

first_boot() {
	# need to test this function? Run with D=echo
	exec 3>&2		# preserve existing stderr
	exec 2>/tmp/firstboot.log	# redirect stderr to /tmp/firstboot.log
	set -x			# and record all executions
	echo "`date` - starting first_boot()" >&2

	# STEP 1 - set wifi configs
	# STEP 1a - hardcode MAC addresses for these interfaces
	wlan5_mac="$(cat /sys/class/ieee80211/phy0/macaddress)"
	wlan5_nasid="$(echo $wlan5_mac|sed 's/://g')";
	# Generate a proper 4-digit hexadecimal value (0000-FFFF)
	# Method: Generate random number between 0-65535 and convert to hex
	rand_hex_int=$(awk 'BEGIN{srand(); print int(rand()*65536)}')
	shared_mobility_domain=$(printf '%04x' $rand_hex_int)

	$D uci set wireless.ap_two.nasid="$wlan5_nasid"
	$D uci set wireless.ap_five.nasid="$wlan5_nasid"
	$D uci set wireless.ap_two.mobility_domain="$shared_mobility_domain"
	$D uci set wireless.ap_five.mobility_domain="$shared_mobility_domain"

	# STEP 1c - generate shared 802.11r parameters for distribution to nodes
	# This allows all APs in the mesh to use consistent 802.11r identifiers
	$D uci set fm.router.shared_wlan2_nasid="$wlan5_nasid"
	$D uci set fm.router.shared_wlan5_nasid="$wlan5_nasid"
	$D uci set fm.router.shared_mobility_domain="$shared_mobility_domain"

	# STEP 1b - generate a random mesh_id and key
	# if mesh_id is already set, don't overwrite it
	if [ -z "$(uci get wireless.mesh_five.mesh_id)" ]; then
		$D uci set wireless.mesh_five.mesh_id=$(random_key)
		$D uci set wireless.mesh_five.key=$(random_key)
	fi
	$D uci commit wireless;

	# STEP 2a - if the hostname doesn't look like mesh-rtr-XX
	#           then generate a hostname that does look like that
	hostname="$(uci get system.@system[0].hostname)"
	case "$hostname" in
		mesh-rtr-??) true;;
		*) hostname="mesh-rtr-$(random_key 2)"
		   $D uci set system.@system[0].hostname=$hostname
        esac

	# STEP 2b - add CNAMEs
	# (this allows clients to just connect to 'router'
	#  or 'freemesh')
	for cname in router freemesh
	do
		# search for an existing cname for this entry
		id=0
		found=false
		while uci get dhcp.@cname[$id].cname >/dev/null 2>&1
		do
			oldcname=$(uci get dhcp.@cname[$id].cname)
			if [ "$oldcname" == "$cname.lan" ]; then
				found=true
				break
			fi
			let id++
		done
		if ! $found; then
			$D id=$($D uci add dhcp cname)
		fi
		$D uci set dhcp.@cname[$id].cname="$cname.lan"
		$D uci set dhcp.@cname[$id].target="$hostname.lan"
	done
	$D uci commit dhcp
	$D /etc/init.d/dnsmasq restart

	# STEP 3 - hack wireless.js (REMOVED)
	# Custom wireless.js override has been removed from the system
	# The system now uses the default LuCI wireless interface

	# STEP 4 - generate a ssh key for the downstream nodes
	$D mkdir /root/.ssh 2>/dev/null
	dropbearkey -f /root/.ssh/id_dropbear -t rsa
	pubkey=$(dropbearkey -y -f /root/.ssh/id_dropbear | grep "^ssh-rsa")
	uci set fm.router.pubkey="$pubkey"

	# STEP 5 - firstboot is done
	$D uci set fm.router.firstboot=0;
	$D uci commit;
	echo "`date` - end of first_boot()" >&2

	# STEP 6 - Flash LEDs to let the end-user know we're done
	# with configuration, so they can unplug and move the router
	$D /freemesh/flashled.sh &
	set +x
	exec 2>&3 # restore stderr, closing fmlog
	exec 3>&- # cleanup
	wifi
}

first_boot
