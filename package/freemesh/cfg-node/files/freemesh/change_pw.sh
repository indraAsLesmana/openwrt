#!/bin/sh

random_key() {
	tr -dc A-NP-Za-km-z2-9 </dev/urandom | head -c ${1:-16}
}

# change the node pw to the mesh backchannel wifi key
pubkey=$(uci get fm.router.pubkey)
	if [ -z "$pubkey" ]; then
		# INSECURE: no public key? use the mesh password
		pw=$(uci get wireless.mesh_five.key)
		yes "$pw" | passwd root
		echo "$(date) - changed the pw" >&2
		secure=INSECURE
	else
		echo "$pubkey" >> /etc/dropbear/authorized_keys
		# throw away the password               
		pw=$(random_key 16)
		yes "$pw" | passwd root
		secure=SECURE
		echo "$(date) - stored the public key and locked root" >&2
	fi

