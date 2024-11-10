#!/bin/bash

HOSTNAME=$(cat /etc/hostname)

OUTPUT_FILE="${OUTPUT_DIR}/${HOSTNAME}-hwstat.csv"
[ -f "$OUTPUT_FILE" ] && rm "$OUTPUT_FILE"

LOGGING_STEPS=${LOGGING_STEPS:-10}  # Default to 10 seconds if not set

get_gpu_usage() {
    local gpu_stats gpu_util gpu_mem gpu_power gpu_power_limit sm_utilization
    gpu_stats=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw,power.limit --format=csv,noheader,nounits)

    sm_utilization=($(nvidia-smi dmon -s u -c 1 | awk '$1 ~ /^[0-9]+$/ {print $2}'))

    gpu_util=()
    gpu_mem=()
    gpu_power_percent=()
    gpu_sm=()

    while IFS=',' read -r util mem power power_limit; do
        gpu_util+=("$util")
        gpu_mem+=("$mem")
        power_percent=$(awk -v power="$power" -v limit="$power_limit" 'BEGIN { printf "%.2f", (limit > 0 ? (power / limit) * 100 : 0) }')
        gpu_power_percent+=("$power_percent")
    done <<< "$gpu_stats"

    local gpu_data
    for ((i=0; i<${#gpu_util[@]}; i++)); do
        gpu_data+="${gpu_util[$i]},${gpu_mem[$i]},${gpu_power_percent[$i]},${sm_utilization[$i]:-0},"
    done
    echo "${gpu_data%,}"
}

get_cpu_memory_usage() {
    local cpu_util mem_total
    cpu_util=$(top -b -n1 | awk 'NR>7 { sum += $9; } END { print sum }')
    mem_total=$(free -m | awk '/Mem:/ {print $3}')
    echo "$cpu_util,$mem_total"
}

# Asynchronously run `sar` to collect RX and TX throughput
start_sar_monitoring() {
    local iface=$1
    sar -n DEV "$LOGGING_STEPS" 1 > "/tmp/sar_${iface}.log" &
}

# Retrieve throughput for a given interface
get_interface_throughput() {
    local iface=$1
    awk -v iface="$iface" '
        $1 ~ /^[0-9]/ && $2 == iface {
            rx_kb=$5;
            tx_kb=$6;
            rx_mib=rx_kb / 1024;
            tx_mib=tx_kb / 1024;
            printf "%.2f,%.2f", rx_mib, tx_mib;
        }
    ' "/tmp/sar_${iface}.log"
}

gpu_power_limits=($(nvidia-smi --query-gpu=power.limit --format=csv,noheader,nounits))
interfaces=$(sar -n DEV 1 1 | awk '$1 ~ /^[0-9]/ && $2 != "IFACE" && $2 != "lo" {print $2}' | sort | uniq)

header="Elapsed Seconds"
gpu_count=$(nvidia-smi -L | wc -l)
for ((i=0; i<gpu_count; i++)); do
    header+=",GPU${i} %,GPU${i} MEM (MiB),GPU${i} Power (%) [Limit: ${gpu_power_limits[$i]}W],GPU${i}_SM"
done
header+=",CPU %,MEM (MiB)"
for iface in $interfaces; do
    header+=",${iface} RX (MiB/s),${iface} TX (MiB/s)"
done
echo "$header" > "$OUTPUT_FILE"

start_time=$(date +%s)

while true; do
    # Start sar monitoring for all interfaces
    for iface in $interfaces; do
        start_sar_monitoring "$iface"
    done

    # Sleep for the desired logging interval
    sleep "$LOGGING_STEPS"

    # Calculate elapsed time
    current_time=$(date +%s)
    elapsed_seconds=$((current_time - start_time))

    # Retrieve GPU and CPU/memory usage
    gpu_stats=$(get_gpu_usage)
    cpu_mem_stats=$(get_cpu_memory_usage)
    row="$elapsed_seconds,$gpu_stats,$cpu_mem_stats"

    # Collect throughput for each interface
    for iface in $interfaces; do
        iface_throughput=$(get_interface_throughput "$iface")
        row+=",$iface_throughput"
    done

    # Write the row to the output file
    echo "$row" >> "$OUTPUT_FILE"
done
