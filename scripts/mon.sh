OPENWRT_SERVER="https://1a40-122-161-76-111.ngrok-free.app/mon"
LOG_FILE="./dns_log.json"
TMP_PAYLOAD="./dns_payload.json"
MAX_SIZE=524288  # Reduce batch size to 512KB
INTERVAL=5  # 30 minutes

# Ensure log file exists
touch "$LOG_FILE"

echo "Listening for DNS queries on br-lan..."

tcpdump -i br-lan -n -l port 53 2>/dev/null | grep -E "A\?|AAAA\?" | while read -r line; do
    TIMESTAMP=$(echo "$line" | awk '{print $1}')
    SRC_IP=$(echo "$line" | awk '{print $3}' | cut -d. -f1-4)
    DEST_IP=$(echo "$line" | awk '{print $5}' | cut -d. -f1-4)
    QUERY_TYPE=$(echo "$line" | grep -oE "A\?|AAAA\?")
    DOMAIN=$(echo "$line" | awk '{print $(NF-1)}' | sed 's/\.$//')

    # Filter out common background domains                                                                                                if echo "$DOMAIN" | grep -E -q "doubleclick|googleads|facebook|cloudfront|akamai|grammarly|tracking|analytics|cdn|ads"; then              continue  # Skip logging                                                                                                          fi                                                                                                                                                                                                                                                                          JSON_ENTRY="{\"timestamp\":\"$TIMESTAMP\", \"src_ip\":\"$SRC_IP\", \"dest_ip\":\"$DEST_IP\", \"query_type\":\"$QUERY_TYPE\", \"dom
    echo "$JSON_ENTRY" >> "$LOG_FILE"  # Append query to log file

    # Check file size
    FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || wc -c < "$LOG_FILE")
    if [ "$FILE_SIZE" -ge "$MAX_SIZE" ]; then
        jq -s . "$LOG_FILE" > "$TMP_PAYLOAD"  # Convert file contents to JSON array
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "@$TMP_PAYLOAD" "$OPENWRT_SER                                                                                                                                              if [ "$RESPONSE" -eq 200 ]; then                                                                                                          echo "... 512KB Batch Sent Successfully!"                                                                                             > "$LOG_FILE"  # Clear file only on success                                                                                       else                                                                                                                                      echo "... 512KB Batch Send Failed: HTTP $RESPONSE"
        fi                                                                                                                                fi
done &  # Run in background

# Periodically send batched data every 30 minutes (failsafe)
while true; do
    sleep "$INTERVAL"

    if [ -s "$LOG_FILE" ]; then  # Check if file is not empty
        jq -s . "$LOG_FILE" > "$TMP_PAYLOAD"  # Convert file contents to JSON array
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "@$TMP_PAYLOAD" "$OPENWRT_SER                                                                                                                                              if [ "$RESPONSE" -eq 200 ]; then                                                                                                          echo "... 30-Min Backup Batch Sent Successfully!"                                                                                     > "$LOG_FILE"  # Clear file only if successful                                                                                    else                                                                                                                                      echo "... 30-Min Backup Batch Send Failed: HTTP $RESPONSE"
        fi                                                                                                                                fi
done