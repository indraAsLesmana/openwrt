#!/bin/sh
#run on startup each time

random_key() {
	tr -dc A-NP-Za-km-z2-9 </dev/urandom | head -c ${1:-16}
}

first_boot() {
	echo "`date` - first_boot() start" >> /tmp/fm.log;

	uci set system.@system[0].hostname="mesh-node-$(random_key 4)";
	uci set fm.node.state=initialize;
	uci commit;

	/freemesh/flashled.sh &

	echo "`date` - first_boot() end" >> /tmp/fm.log;
}

# gets the default route address
gateway() {
	ip ro | awk '$1 == "default" {print $3}'
}

# gets the ethernet port mac
mac() {
	ifconfig eth1 | awk 'NR == 1 {print $5}' | tr A-F a-f
}

remote_log() {
	gw=$1
	message=$2
    wget -q -O - http://$gw/cgi-bin/handler.cgi?l="$message"
}

initialize() {
	# preserve stderr, then redirect it to /tmp/fm.log
	exec 3>&2
	exec 2>>/tmp/fm.log
	echo "$(date) - initialize() start" >&2
	echo "$(date) - looking for a gateway" >&2
	/freemesh/flashled-init.sh &
	gw=$(gateway)
	while [ -z "$gw" ]
	do
		sleep 1
		gw=$(gateway)
	done

	echo "$(date) - gateway $gw ping start" >&2
	# ping the gateway
	while ! ping -c 1 $(gateway) 2>/dev/null
	do
		sleep 1
		gw=$(gateway)
	done

	gw=$(gateway)
	echo "$(date) - ping successful; gateway $gw" >&2
	set -x
	uci set fm.node.gateway_ip="$gw"
	uci set network.lan.gateway="$gw"
	uci add_list dhcp.@dnsmasq[0].server="$gw"
	uci set batmand.general.interface="bat0"

	# keep trying to get the configuration until it gets at least
	# the wireless.mesh_five.key value
    mac=$(mac)
	while :
	do
	    echo "$(date) - reading configuration from $gw" >&2
	    wget -q -O - http://$gw/cgi-bin/handler.cgi?mac=$mac |
		while read opt
		do
			# do some basic filtering; the server can
			# only set wireless parameters or the static
			# ip address
			case $opt in
				wireless.*=*)
					eval uci set $opt;;
				network.lan.ipaddr=*)
					eval uci set $opt;;
				network.default.ipaddr=*)
					eval uci set $opt;;					
				fm.*=*)
					eval uci set $opt;;
			esac
		done
	    [ -z "$(uci get wireless.mesh_five.key)" ] || break
	done

	uci set dhcp.lan.ignore=1
	uci commit
	echo "$(date) - committed changes" >&2

	# Set 802.11r parameters - use shared values from router if available,
	# otherwise fall back to node's own MAC addresses
	shared_wlan5_nasid="$(uci get fm.router.shared_wlan5_nasid 2>/dev/null)"
	shared_mobility_domain="$(uci get fm.router.shared_mobility_domain 2>/dev/null)"
	
	if [ -n "$shared_wlan5_nasid" ]; then
		# Use shared 802.11r parameters from router for consistent roaming
		uci set wireless.ap_two.nasid="$shared_wlan5_nasid"
		uci set wireless.ap_five.nasid="$shared_wlan5_nasid"
		echo "$(date) - set shared 802.11r: wlan5_nasid=$shared_wlan5_nasid" >&2
		
		# Set mobility domain if available
		if [ -n "$shared_mobility_domain" ]; then
			uci set wireless.ap_two.mobility_domain="$shared_mobility_domain"
			uci set wireless.ap_five.mobility_domain="$shared_mobility_domain"
			echo "$(date) - set shared mobility domain: $shared_mobility_domain" >&2
		fi
	else
		# Fallback: use node's own MAC addresses (like router does)
		if [ -e "/sys/class/ieee80211/phy1/macaddress" ]; then
			wlan2_mac="$(cat /sys/class/ieee80211/phy1/macaddress)"
			wlan2_nasid="$(echo $wlan2_mac|sed 's/://g')"
			uci set wireless.ap_two.nasid="$wlan2_nasid"
			echo "$(date) - set 2GHz nasid to $wlan2_nasid" >&2
		fi
		if [ -e "/sys/class/ieee80211/phy0/macaddress" ]; then
			wlan5_mac="$(cat /sys/class/ieee80211/phy0/macaddress)"
			wlan5_nasid="$(echo $wlan5_mac|sed 's/://g')"
			uci set wireless.ap_five.nasid="$wlan5_nasid"
			echo "$(date) - set 5GHz nasid to $wlan5_nasid" >&2
		fi
		
		# Generate and set mobility domain for fallback case
		rand_int_10=$(awk -v min=1000000000 -v max=9999999999 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
		mobility_domain=$(printf '%04X\n' $rand_int_10 | tail -c 5 | tr 'A-F' 'a-f')
		uci set wireless.ap_two.mobility_domain="$mobility_domain"
		uci set wireless.ap_five.mobility_domain="$mobility_domain"
		echo "$(date) - set fallback mobility domain: $mobility_domain" >&2
	fi
	uci commit wireless

	/freemesh/change_pw.sh &

	hostname=$(uci get system.@system[0].hostname)
	remote_log $gw \
		"config-success,hostname=$hostname,gw=$gw,$secure"

	# Tell router to increment next_static
	myip=$(uci get network.lan.ipaddr)
	wget -O - "http://$gw/cgi-bin/handler.cgi?accept=$mac,$hostname,$myip" >&2

	#kill the previous flash
	pidofflash=`ps | grep -i -E 'flashled' | grep -v grep | awk '{print $1}'`;
	kill -9 $pidofflash;

	#flash leds on initialize end	
	/freemesh/flashled.sh &
	echo "$(date) - started flashing LEDs" >&2

	# done -- set state to normal
	uci set fm.node.state=normal
	uci commit fm

	/etc/init.d/dnsmasq disable

	echo "`date` - initialize() end" >&2
	# turn off logging
	set +x

	# restore stderr
	exec 2>&3
	exec 3>&-
}

clear_leds() {
	echo "none" > /sys/class/leds/blue:status/trigger;
	echo "none" > /sys/class/leds/green:status/trigger;
	echo "none" > /sys/class/leds/red:status/trigger;

	echo "1" > /sys/class/leds/blue:status/brightness;
	echo "0" > /sys/class/leds/green:status/brightness;
	echo "0" > /sys/class/leds/red:status/brightness;
}

node_connectivity_check() {

    #create a flag to indicate router booted normally
	touch /tmp/normal_boot;

	#call this method after node state is stable
	#setup cron job ....
	crontab -l > /etc/crontabs/root;
	echo "0-59/1 * * * * /freemesh/check_router_ap.sh" >> /etc/crontabs/root;
	/etc/init.d/cron start;
}

case "$(uci get fm.node.state)" in
	#this is the setup scenario - being setup on our desk
	firstboot) 
		clear_leds
		first_boot;;
	#customer first-boot scenario - should auto-configure off the router once connected
	initialize)
		clear_leds
		initialize;;
	#boot every future time.
	normal)	
		node_connectivity_check;;
esac
