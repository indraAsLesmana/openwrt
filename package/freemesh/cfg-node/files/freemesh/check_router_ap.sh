#!/bin/sh

if [ -f /tmp/normal_boot ] ; then 
	echo "`date` - Inside normal_boot" >> /tmp/fmlog;
	pidofflash=`ps | grep -i -E 'flashled' | grep -v grep | awk '{print $1}'`;
	kill -9 $pidofflash;

	#kill the trigger so we control the leds
	echo "none" > /sys/class/leds/blue:status/trigger;
	echo "none" > /sys/class/leds/green:status/trigger;
	echo "none" > /sys/class/leds/red:status/trigger;

	gateway_ip=`uci get network.default.gateway`;

	ping -c 1 $gateway_ip
	rc=$?

	if [[ $rc -eq 0 ]] ; then
		#connected
		#Turn on wifi LEDs
		echo "1" > /sys/class/leds/blue:status/brightness;
		echo "1" > /sys/class/leds/green:status/brightness;
		echo "`date` - can ping, turning on solid" >> /tmp/fmlog;
	else
		#not connected
		#Alternate LEDs
		echo "`date` - NO ping, flashing" >> /tmp/fmlog;
		/freemesh/flashled.sh &
	fi
fi
#else - do nothing since we are controlling the leds elsewhere
