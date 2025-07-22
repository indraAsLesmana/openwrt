#!/bin/sh
# generate a list of UCI values
ucicsv() {
	comma=
	verbose=false
	if [ "$1" == "-v" ]; then
		shift
		verbose=true
		echo "Content-type: text/plain"
	else
		echo "Content-type: text/csv"
	fi

	# terminate HTTP headers now
	echo
	for uciparm
	do
	    if [ "$uciparm" == "fm.router.next_static" ]; then
	        # TODO: this assumes /24 network :(
	        subnet="$(uci get network.lan.ipaddr | cut -d. -f1-3)"
	        if $verbose; then
		    echo "network.lan.ipaddr=\'${subnet}.$(uci get $uciparm)\'"
			echo "network.default.ipaddr=\'192.168.10.$(uci get $uciparm)\'"
		else
		    echo -n "$comma${subnet}.$(uci get $uciparm)"
		fi
	    else
	        if $verbose; then
			uci show "$uciparm"
		else
		    echo -n "$comma$(uci get $uciparm)"
		fi
	    fi
	    comma=,
	done
	echo
}

# look up your mac from the request IP
realmac() {
    awk '$1 == "'$REMOTE_ADDR'" {print $4}' /proc/net/arp
}

# check_mac verifies the mac passed in is your actual mac
is_mac_spoofed() {
	# mac not spoofed if on localhost
        [ "$REMOTE_ADDR" == "127.0.0.1" ] && return 1
	[ "$1" != "$(realmac)" ]
}

# is_wireless checks to see if your mac shows up in a
# station dump 
is_wireless() {
	for iface in wlan0 wlan1; do
	    iw dev $iface station dump | 
		awk '$1 == "Station" {print $2}' |
	        while read mac
	    do
		if [ "$mac" = "$1" ]; then
		    return 0
		fi
	    done
	done
	return 1
}

echo "Content-type: text/plain"
echo "$QUERY_STRING" > /dev/klog
case "$QUERY_STRING" in
	# request by mac for a new mesh node
        # example: http://192.168.1.1/cgi-bin/handler.cgi?m=78:A3:51:XX:XX:XX:XX
	m=*) 
		# only a few macs are supported mesh nodes
		fullmac=$(echo "$QUERY_STRING" | cut -c 3-)
		if ! is_mac_spoofed "$fullmac"; then
			if is_wireless "$fullmac"; then
				echo "Status: 403"
				echo
				echo "Wireless request denied"
				exit 1
			else
				ucicsv \
				    wireless.ap_two.ssid \
					wireless.ap_two.key \
					wireless.ap_five.ssid \
					wireless.ap_five.key \
					wireless.mesh_five.mesh_id \
					wireless.mesh_five.key \
					fm.router.next_static
			        exit 0
			fi
		fi;;
	mac=*)
		# this is a slightly better interface; this produces a KV pair
		# which would allow for future data to be sent in a compatible
		# way! The client can filter the uci keys if desired
		fullmac=$(echo "$QUERY_STRING" | cut -c 5-)
		if ! is_mac_spoofed "$fullmac"; then
		    if ! is_wireless "$fullmac"; then
			ucicsv -v wireless.ap_two.ssid wireless.ap_two.key \
			    wireless.ap_five.ssid wireless.ap_five.key \
			    wireless.radio0.channel wireless.radio1.channel \
			    wireless.mesh_five.mesh_id wireless.mesh_five.key \
			    wireless.ap_two.nasid wireless.ap_two.r1_key_holder \
			    wireless.ap_five.nasid wireless.ap_five.r1_key_holder \
			    fm.router.shared_wlan5_nasid \
			    fm.router.shared_mobility_domain \
			    fm.router.pubkey \
			    fm.router.next_static
		    exit 0
		    fi
		fi;;
	p=*)
		# request from existing mesh node
		# http://192.168.1.1/cgi-bin/handler.cgi?p=<router_key>
		key=$(echo "$QUERY_STRING" | cut -c 3-)
		router_key="$(uci get wireless.mesh_five.key)"
		if [ "$key" == "$router_key" ]; then
        	    ucicsv wireless.ap_two.ssid wireless.ap_two.key \
			    wireless.ap_five.ssid wireless.ap_five.key
		    exit 0
		fi;;
	accept=*)
		# increment next static IP address
		# sent at the end of initialization of the mesh node
		# client sends mac,hostname,ipaddr
		# TODO: save the mac and reuse it when reconfiguring
		mac=$(echo "$QUERY_STRING" | cut -c 8-25)
		hn=$(echo "$QUERY_STRING" | cut -d, -f2)
		ip=$(echo "$QUERY_STRING" | cut -d, -f3)
		last="$(uci get fm.router.next_static)"
		nodeid=$((last-1))
		next=$((last+1))
		uci set fm.router.next_static=$next
		uci commit fm
		echo "$ip mesh-node-$nodeid $hn" >> /etc/hosts
		echo "Content-type: text/plain"
		echo
		echo "Next static is now $next";
		# restart wifi after 30 seconds when a node completes initialization
		(sleep 30 && wifi) &
		exit 0;;
	# log a random message to /tmp/Logger
	l=*)
		msg=$(echo "$QUERY_STRING" | cut -c 3-)
		echo "$msg" >> /tmp/Logger
		echo "Status: 204"
		echo
		exit 0;;
	info)
		echo "Content-type: text/plain"
		echo
		echo Your IP: $REMOTE_ADDR
		fullmac=$(realmac)
		echo Your MAC: $fullmac
		is_wireless "$fullmac" && echo WIRELESS
		! is_wireless "$fullmac" && echo WIRED
		exit 0;;
esac
echo "Status: 403"
echo
echo "Forbidden"
