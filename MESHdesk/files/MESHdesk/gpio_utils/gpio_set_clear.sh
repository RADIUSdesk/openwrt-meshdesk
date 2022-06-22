#!/bin/sh

if [ -z "$1" ] && [ -z "$2" ];
then
    echo "===============radiusdesk.com==================="
    echo "===GPIO Utility script to set and clear GPIO ==="
    echo "=== usage gpio_set_clear.sh gpio_nr 0/1 ========"
    echo "=== e.g. gpio_set_clear.sh 18 0 ================"
    echo "=== to clear gpio 18 ==========================="
    exit;
fi

PIN=$1
ACTION=$2
PRE_ACTION=1
if [ $ACTION == 1 ];
then
    PRE_ACTION=0
fi

echo $PIN > /sys/class/gpio/export
echo "high" > /sys/class/gpio/gpio$PIN/direction
echo $PRE_ACTION > /sys/class/gpio/gpio$PIN/value
echo $ACTION > /sys/class/gpio/gpio$PIN/value
echo "GPIO $PIN SET TO `cat /sys/class/gpio/gpio$PIN/value`"
echo $PIN > /sys/class/gpio/unexport




