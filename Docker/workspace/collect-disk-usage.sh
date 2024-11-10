#!/bin/bash

# Paths for the directories to monitor
OUTPUT_DIR=${OUTPUT_DIR:-"/mnt/storage/Boaz/output"}
HF_HOME=${HF_HOME:-"/root/.cache/huggingface"}  # Default value if HF_HOME is unset
hostname=$(cat /etc/hostname)
disk_usage_file="${DISK_USAGE_FILE:-/mnt/storage/Boaz/output/${hostname}_disk_usage.csv}"

# Wait until both directories are created
while [ ! -d "$HF_HOME" ] || [ ! -d "$OUTPUT_DIR" ]; do
    sleep 1
done

# Ensure the output file exists and add the header
echo "Date,Time,HF_HOME Size (GB),OUTPUT_DIR Size (GB)" > "$disk_usage_file"

# Function to get directory size in GB with 2 decimal precision
get_dir_size_gb() {
    du -sb "$1" 2>/dev/null | awk '{printf "%.2f", $1/1024/1024/1024}'
}

# Main loop to collect disk usage
while true; do
    # Get current date and time
    current_date=$(date '+%Y-%m-%d,%H:%M:%S')

    # Calculate sizes
    hf_size=$(get_dir_size_gb "$HF_HOME")
    output_size=$(get_dir_size_gb "$OUTPUT_DIR")

    # Handle cases where directories may not exist
    hf_size=${hf_size:-0}
    output_size=${output_size:-0}

    # Write to the disk usage file
    echo "$current_date,$hf_size,$output_size" >> "$disk_usage_file"

    # Sleep for the defined interval
    sleep "${LOGGING_STEPS:-10}"
done
