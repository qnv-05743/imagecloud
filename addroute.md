#!/bin/bash

# Output file for the generated script
OUTPUT_FILE="generated_routes.sh"

# Initialize the output file
cat << EOF > $OUTPUT_FILE
#!/bin/bash
EOF

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# Detect OS
OS=$(detect_os)

# Get all network interfaces excluding the loopback
interfaces=$(ls /sys/class/net | grep -v lo)

# Start table ID from 100
table_id_base=100
table_counter=0

# Network configuration path
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    CONFIG_FILE="/etc/network/interfaces"
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    CONFIG_PATH="/etc/sysconfig/network-scripts/"
else
    echo "Unsupported OS."
    exit 1
fi

for iface in $interfaces; do
    echo "Processing interface: $iface"

    # Check and configure network settings
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        # For Debian/Ubuntu
        if ! grep -q "iface $iface inet dhcp" "$CONFIG_FILE"; then
            echo "Adding DHCP configuration for $iface in $CONFIG_FILE."
            echo -e "\nauto $iface\niface $iface inet dhcp" >> "$CONFIG_FILE"
            echo "Restarting interface $iface."
            ifdown $iface 2>/dev/null && ifup $iface 2>/dev/null
        fi
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        # For CentOS/RHEL
        CONFIG_FILE="${CONFIG_PATH}ifcfg-$iface"
        if [ ! -f "$CONFIG_FILE" ]; then
            echo "Creating DHCP configuration for $iface in $CONFIG_FILE."
            cat << EOF > "$CONFIG_FILE"
DEVICE=$iface
BOOTPROTO=dhcp
ONBOOT=yes
EOF
            echo "Restarting interface $iface."
            ifdown $iface 2>/dev/null || nmcli conn down $iface 2>/dev/null
            ifup $iface 2>/dev/null || nmcli conn up $iface 2>/dev/null
        fi
    fi

    # Check if the interface is up, if not, bring it up
    iface_status=$(cat /sys/class/net/$iface/operstate)
    if [ "$iface_status" != "up" ]; then
        echo "Interface $iface is down. Bringing it up."
        ip link set $iface up
    fi

    # Get the IP address assigned to the interface
    ip_address=$(ip -4 addr | grep $iface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

    if [ -z "$ip_address" ]; then
        echo "No IP address found for $iface. Skipping."
        continue
    fi

    # Get the CIDR subnet mask
    subnet=$(echo $ip_address | awk -F. '{print $1 "." $2 "." $3 ".0"}')

    # Default gateway is .1 of the same subnet
    gateway=$(echo $ip_address | awk -F. '{print $1 "." $2 "." $3 ".1"}')

    # Assign a unique table ID starting from 100
    table_id=$((table_id_base + table_counter))
    table_counter=$((table_counter + 1))

    echo "IP: $ip_address, Gateway: $gateway, Subnet: $subnet, Table ID: $table_id"

    # Append the routing rules to the output file
    cat << EOF >> $OUTPUT_FILE
# Configuration for interface $iface
ip route add $subnet/24 dev $iface src $ip_address table $table_id
ip route add default via $gateway dev $iface table $table_id
ip rule add from $ip_address/32 table $table_id
ip rule add to $ip_address/32 table $table_id
EOF
done

# Make the output file executable
chmod +x $OUTPUT_FILE

./$OUTPUT_FILE
# Notify the user
echo "Routing script generated: $OUTPUT_FILE"
