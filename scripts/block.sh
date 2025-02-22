#!/bin/sh

# Script to set up or remove website blocking based on string matching for specific MAC address
# Save this as /scripts/block_website.sh

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to show usage
show_usage() {
    echo "Usage:"
    echo "  Add blocking rule:    $0 add MAC_ADDRESS BLOCK_STRING"
    echo "  Remove blocking rule: $0 remove MAC_ADDRESS"
    echo "  Example add:          $0 add 00:11:22:33:44:55 google"
    echo "  Example remove:       $0 remove 00:11:22:33:44:55"
    echo "  Without arguments:    $0 (interactive mode)"
}

# Create firewall.user if it doesn't exist
create_firewall_user() {
    if [ ! -f "/etc/firewall.user" ]; then
        log_message "Creating /etc/firewall.user file..."
        touch /etc/firewall.user
        chmod 644 /etc/firewall.user
        echo "#!/bin/sh" > /etc/firewall.user
        echo "# This file is interpreted as shell script." >> /etc/firewall.user
        echo "# Put your custom iptables rules here, they will" >> /etc/firewall.user
        echo "# be executed with each firewall (re-)start." >> /etc/firewall.user
    fi
}

# Function to install required packages
install_packages() {
    log_message "Updating package lists..."
    opkg update || {
        log_message "Error: Failed to update package lists"
        exit 1
    }
    
    log_message "Installing required packages..."
    opkg install iptables iptables-mod-filter kmod-ipt-filter || {
        log_message "Error: Failed to install required packages"
        exit 1
    }
}

# Function to remove blocking rules
remove_blocking() {
    local MAC_ADDRESS="$1"
    
    log_message "Removing rules for MAC address $MAC_ADDRESS..."
    # Remove from iptables
    iptables-save | grep -v "$MAC_ADDRESS" | iptables-restore
    
    # Remove from firewall.user
    if [ -f "/etc/firewall.user" ]; then
        sed -i "/$MAC_ADDRESS/d" /etc/firewall.user
    fi
    
    # Restart firewall
    log_message "Restarting firewall..."
    /etc/init.d/firewall restart
    
    log_message "Rules successfully removed for MAC address $MAC_ADDRESS"
}

# Function to add blocking rules
add_blocking() {
    local MAC_ADDRESS="$1"
    local BLOCK_STRING="$2"
    
    # Remove any existing rules first
    iptables-save | grep -v "$MAC_ADDRESS" | iptables-restore
    
    log_message "Adding iptables rules..."
    # Block HTTP traffic
    iptables -I FORWARD 1 -m mac --mac-source "$MAC_ADDRESS" -p tcp --dport 80 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
    # Block HTTPS traffic
    iptables -I FORWARD 1 -m mac --mac-source "$MAC_ADDRESS" -p tcp --dport 443 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
    # Block DNS queries containing the string
    iptables -I FORWARD 1 -m mac --mac-source "$MAC_ADDRESS" -p udp --dport 53 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
    
    # Update firewall.user
    sed -i "/$MAC_ADDRESS/d" /etc/firewall.user
    cat >> /etc/firewall.user << EOF

# Block websites containing $BLOCK_STRING for $MAC_ADDRESS
iptables -I FORWARD 1 -m mac --mac-source $MAC_ADDRESS -p tcp --dport 80 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
iptables -I FORWARD 1 -m mac --mac-source $MAC_ADDRESS -p tcp --dport 443 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
iptables -I FORWARD 1 -m mac --mac-source $MAC_ADDRESS -p udp --dport 53 -m string --string "$BLOCK_STRING" --algo bm --icase -j DROP
EOF
    
    # Restart firewall
    log_message "Restarting firewall..."
    /etc/init.d/firewall restart
    
    # Verify rules
    log_message "Verifying rules..."
    iptables -L FORWARD -n -v | grep "$MAC_ADDRESS"
    
    log_message "Setup completed successfully!"
    log_message "Blocking URLs containing '$BLOCK_STRING' for MAC address $MAC_ADDRESS"
}

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    log_message "Error: This script must be run as root"
    exit 1
fi

# Check and create firewall.user
create_firewall_user

# Check and install required packages if iptables is not found
if ! command_exists iptables; then
    log_message "iptables not found. Installing required packages..."
    install_packages
fi

# Handle command line arguments
if [ $# -eq 0 ]; then
    # Interactive mode
    echo "Select operation:"
    echo "1. Add blocking rule"
    echo "2. Remove blocking rule"
    read -p "Enter choice (1 or 2): " CHOICE
    
    echo -n "Enter MAC address (format XX:XX:XX:XX:XX:XX): "
    read MAC_ADDRESS
    
    # Validate MAC address
    if ! echo "$MAC_ADDRESS" | grep -E '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' >/dev/null; then
        log_message "Error: Invalid MAC address format. Use XX:XX:XX:XX:XX:XX"
        exit 1
    fi
    
    case $CHOICE in
        1)
            echo -n "Enter string to block (e.g., google): "
            read BLOCK_STRING
            add_blocking "$MAC_ADDRESS" "$BLOCK_STRING"
            ;;
        2)
            remove_blocking "$MAC_ADDRESS"
            ;;
        *)
            log_message "Invalid choice"
            show_usage
            exit 1
            ;;
    esac
else
    # Command line mode
    case $1 in
        "add")
            if [ $# -ne 3 ]; then
                show_usage
                exit 1
            fi
            if ! echo "$2" | grep -E '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' >/dev/null; then
                log_message "Error: Invalid MAC address format. Use XX:XX:XX:XX:XX:XX"
                exit 1
            fi
            add_blocking "$2" "$3"
            ;;
        "remove")
            if [ $# -ne 2 ]; then
                show_usage
                exit 1
            fi
            if ! echo "$2" | grep -E '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' >/dev/null; then
                log_message "Error: Invalid MAC address format. Use XX:XX:XX:XX:XX:XX"
                exit 1
            fi
            remove_blocking "$2"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
fi