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
TIMES=$2

if [ -z "$3" ];
then
    SLEEP=1
else
    SLEEP=$3
fi


echo $PIN > /sys/class/gpio/export
CURRENT=`cat /sys/class/gpio/gpio$PIN/value`
echo "high" > /sys/class/gpio/gpio$PIN/direction

if [ $CURRENT == 0 ]
then
    ACTION=1
else
    ACTION=0
fi

echo "Current state is $CURRENT FLASH x $TIMES"

for var in `seq 1 $TIMES`; 
do
    echo "$var SET PIN TO $ACTION"
    echo $ACTION > /sys/class/gpio/gpio$PIN/value
    if [ $ACTION == 1 ]
    then
        ACTION=0
    else
        ACTION=1
    fi
    sleep $SLEEP; 
done

#Restore original state
echo $CURRENT > /sys/class/gpio/gpio$PIN/value
CURRENT=`cat /sys/class/gpio/gpio$PIN/value`
echo "NEW Current state is $CURRENT"

echo $PIN > /sys/class/gpio/unexport



