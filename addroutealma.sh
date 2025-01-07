#!/bin/bash
# Get IP addresses associated with each interface and store them in ip.txt
ip -4 addr | grep ens | grep -oP '(?<=inet\s)\d+(\.\d+){3}' > ip.txt

i=3

# Iterate over each IP and create routing commands
while IFS= read -r line; do
    ip=$(echo "$line")
    gateway=$(echo "$line" | awk -F '.' '{print $1"."$2"."$3".1"}')

    # Add route and rule commands to add_route.sh for each interface IP
    echo "ip route add $ip/24 dev ens$i src $ip table 10$i" >> add_route.sh
    echo "ip route add default via $gateway dev ens$i table 10$i" >> add_route.sh
    echo "ip rule add from $ip/32 table 10$i" >> add_route.sh
    echo "ip rule add to $ip/32 table 10$i" >> add_route.sh
    echo "##################" >> add_route.sh

    i=$((i+1))
done < ip.txt

# Make add_route.sh executable and run it
chmod +x add_route.sh
bash add_route.sh

# Clean up by removing ip.txt
rm -rf ip.txt
