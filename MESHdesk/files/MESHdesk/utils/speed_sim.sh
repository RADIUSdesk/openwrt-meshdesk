while true; do
  LAT=$((10 + RANDOM % 90))  # 10–99 ms
  DOWN=$(awk -v r=$RANDOM 'BEGIN {srand(); print 50 + (r % 50) * 0.5}')
  UP=$(awk -v r=$RANDOM 'BEGIN {srand(); print 10 + (r % 40) * 0.4}')
  
  mosquitto_pub -h 192.168.8.117 -u openwrt -P openwrt -t "ap/speedtest" \
    -m "{\"latency\": $LAT, \"download\": $DOWN, \"upload\": $UP}"

  sleep 2
done


