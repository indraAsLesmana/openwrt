#!/bin/sh

echo "none" > /sys/class/leds/blue:status/trigger;
echo "none" > /sys/class/leds/green:status/trigger;
echo "none" > /sys/class/leds/red:status/trigger;

echo "1" > /sys/class/leds/blue:status/brightness;
echo "0" > /sys/class/leds/green:status/brightness;
echo "0" > /sys/class/leds/red:status/brightness;

led_state=0;

while true
do
	if [ "$led_state" == 0 ]; then
		led_state=1;
	else
		led_state=0;
	fi

	echo $led_state > /sys/class/leds/green:status/brightness;

	sleep 1;
done