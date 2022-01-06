#!/bin/sh

BR=$1
TAPDEV=$2
/sbin/ip link set "$TAPDEV" up
/usr/sbin/brctl addif $BR $TAPDEV

