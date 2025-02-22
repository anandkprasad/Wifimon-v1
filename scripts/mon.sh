
# OPENWRT_SERVER="${OPENWRT_SERVER:-https://ebd7-122-161-76-111.ngrok-free.app/mon}"

# echo "Listening for DNS queries on eth0..."

# tcpdump -i br-lan -n -l port 53 2>/dev/null | grep -E "A\?|AAAA\?" | while read -r line; do
#     TIMESTAMP=$(awk '{print $1}' <<< "$line")
#     SRC_IP=$(awk '{print $3}' <<< "$line" | cut -d. -f1-4)
#     DEST_IP=$(awk '{print $5}' <<< "$line" | cut -d. -f1-4)
#     QUERY_TYPE=$(grep -oE "A\?|AAAA\?" <<< "$line")
#     DOMAIN=$(awk '{print $(NF-1)}' <<< "$line" | sed 's/\.$//')

#     JSON_PAYLOAD=$(jq -n \
#         --arg timestamp "$TIMESTAMP" \
#         --arg src_ip "$SRC_IP" \
#         --arg dest_ip "$DEST_IP" \
#         --arg query_type "$QUERY_TYPE" \
#         --arg domain "$DOMAIN" \
#         '{timestamp: $timestamp, src_ip: $src_ip, dest_ip: $dest_ip, query_type: $query_type, domain: $domain}')

#     RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$OPENWRT_SERVER")

#     [[ "$RESPONSE" -eq 200 ]] && echo "✅ Sent: $DOMAIN" || echo "❌ Failed: HTTP $RESPONSE"
# done

#!/bin/sh

OPENWRT_SERVER="https://ebd7-122-161-76-111.ngrok-free.app/mon"
LOG_FILE="/tmp/dns_log.json"
MAX_SIZE=1048576  # 1MB in bytes
INTERVAL=1800  # 30 minutes (in seconds)

# Ensure log file exists
touch "$LOG_FILE"

echo "Listening for DNS queries on br-lan..."

tcpdump -i br-lan -n -l port 53 2>/dev/null | grep -E "A\?|AAAA\?" | while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1}')
    SRC_IP=$(echo "$line" | awk '{print $3}' | cut -d. -f1-4)
    DEST_IP=$(echo "$line" | awk '{print $5}' | cut -d. -f1-4)
    QUERY_TYPE=$(echo "$line" | grep -oE "A\?|AAAA\?")
    DOMAIN=$(echo "$line" | awk '{print $(NF-1)}' | sed 's/\.$//')

    JSON_ENTRY="{\"timestamp\":\"$TIMESTAMP\", \"src_ip\":\"$SRC_IP\", \"dest_ip\":\"$DEST_IP\", \"query_type\":\"$QUERY_TYPE\", \"domain\":\"$DOMAIN\"}"

    echo "$JSON_ENTRY" >> "$LOG_FILE"  # Append query to log file

    # Check file size
    FILE_SIZE=$(stat -c%s "$LOG_FILE")
    if [ "$FILE_SIZE" -ge "$MAX_SIZE" ]; then
        JSON_PAYLOAD=$(jq -s . "$LOG_FILE")  # Convert file contents to JSON array
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$OPENWRT_SERVER")

        if [ "$RESPONSE" -eq 200 ]; then
            echo "✅ 1MB Batch Sent Successfully!"
            > "$LOG_FILE"  # Clear file after successful upload
        else
            echo "❌ 1MB Batch Send Failed: HTTP $RESPONSE"
        fi
    fi
done &  # Run in background

# Periodically send batched data every 30 minutes (failsafe)
while true; do
    sleep "$INTERVAL"

    if [ -s "$LOG_FILE" ]; then  # Check if file is not empty
        JSON_PAYLOAD=$(jq -s . "$LOG_FILE")  # Convert file contents to JSON array
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$OPENWRT_SERVER")

        if [ "$RESPONSE" -eq 200 ]; then
            echo "✅ 30-Min Backup Batch Sent Successfully!"
            > "$LOG_FILE"  # Clear file after successful upload
        else
            echo "❌ 30-Min Backup Batch Send Failed: HTTP $RESPONSE"
        fi
    fi
done

