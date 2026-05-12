#!/bin/bash

# Configuration
LOG_FILE="/var/ossec/logs/active-responses.log"

# Read JSON input from STDIN
read -r INPUT_JSON

# Extract file path using jq
FILE_PATH=$(echo "$INPUT_JSON" | jq -r '.parameters.alert.syscheck.path')

# Path validation
if [ -z "$FILE_PATH" ] || [ "$FILE_PATH" == "null" ]; then
    echo "$(date '+%Y/%m/%d %H:%M:%S') custom-delete.sh: Error - File path not found in alert." >> ${LOG_FILE}
    exit 1
fi

# System directory protection (Anti-FP)
if [[ "$FILE_PATH" =~ ^/(etc|bin|sbin|usr)/ ]]; then
    echo "$(date '+%Y/%m/%d %H:%M:%S') custom-delete.sh: Denied - Deletion of system file blocked: $FILE_PATH" >> ${LOG_FILE}
    exit 1
fi

# Execution
if [ -f "$FILE_PATH" ]; then
    rm -f "$FILE_PATH"
    echo "$(date '+%Y/%m/%d %H:%M:%S') custom-delete.sh: Successfully deleted: $FILE_PATH" >> ${LOG_FILE}
else
    echo "$(date '+%Y/%m/%d %H:%M:%S') custom-delete.sh: File not found or already removed: $FILE_PATH" >> ${LOG_FILE}
fi

exit 0
