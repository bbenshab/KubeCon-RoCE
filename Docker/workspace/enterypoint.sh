#!/bin/bash

# Set script paths
METRICS_SCRIPT="collect_metrics.sh"
DISK_USAGE_SCRIPT="collect_disk_usage.sh"
master_ip_file="/mnt/storage/Boaz/master_ip.txt"

# Export environment variables
export NNODES=${NNODES:-2}
export NPROC_PER_NODE=${NPROC_PER_NODE:-2}
export MASTER_PORT=${MASTER_PORT:-24685}
export TRAINING_SCRIPT=${TRAINING_SCRIPT:-/mnt/storage/fms-hf-tuning/tuning/sft_trainer.py}
export MODEL_NAME_OR_PATH=${MODEL_NAME_OR_PATH:-/mnt/storage/Llama-3.2-3B-Instruct}
export OUTPUT_DIR=${OUTPUT_DIR:-/mnt/storage/output}
export FSDP_CONFIG=${FSDP_CONFIG:-/mnt/storage/fsdp_config.json}
export TRAINING_DATA_PATH=${TRAINING_DATA_PATH:-/mnt/storage/twitter_complaints.jsonl}
export NUM_TRAIN_EPOCHS=${NUM_TRAIN_EPOCHS:-3}
export LEARNING_RATE=${LEARNING_RATE:-2e-5}
export LR_SCHEDULER_TYPE=${LR_SCHEDULER_TYPE:-cosine}
export FSDP=${FSDP:-"hybrid_shard auto_wrap"}
export SAVE_STEPS=${SAVE_STEPS:-10}
export TORCH_DTYPE=${TORCH_DTYPE:-bfloat16}
export LOGGING_STRATEGY=${LOGGING_STRATEGY:-steps}
export LOGGING_STEPS=${LOGGING_STEPS:-10}
export PER_DEVICE_TRAIN_BATCH_SIZE=${PER_DEVICE_TRAIN_BATCH_SIZE:-64}
export TARGET_MODULES=${TARGET_MODULES:-"q_proj v_proj k_proj o_proj"}
export LORA_R=${LORA_R:-8}
export LORA_ALPHA=${LORA_ALPHA:-8}
export LORA_DROPOUT=${LORA_DROPOUT:-0.1}
export PEFT_METHOD=${PEFT_METHOD:-"lora"}
export NUM_WORKERS=${NUM_WORKERS:-2}
export RDZV_BACKEND="nccl"
export MAX_SEQ_LENGTH=${MAX_SEQ_LENGTH:-8}
export PEFT_METHOD_ENABLED=${PEFT_METHOD_ENABLED:-false}
export HF_HOME=${HF_HOME:-"/root/.cache/huggingface"}
export ENABLE_RDMA=${ENABLE_RDMA:-true}
export QUANTIZATION_ENABLED=${QUANTIZATION_ENABLED:-false}

# Handle RDMA enable/disable
if [[ "$ENABLE_RDMA" == "false" ]]; then
    export NCCL_IB_DISABLE=1
    export NCCL_NET="socket"
    export NCCL_IBEXT_DISABLE=1
    echo "RDMA is disabled. NCCL configured to use socket transport."
else
    unset NCCL_IB_DISABLE
    unset NCCL_NET
    unset NCCL_IBEXT_DISABLE
    echo "RDMA is enabled. NCCL configured for InfiniBand."
fi

# Ensure OUTPUT_DIR exists
mkdir -p "$OUTPUT_DIR"

# Set file paths
hostname=$(cat /etc/hostname)
metrics_file="${OUTPUT_DIR}/${hostname}-hwstat.csv"
disk_usage_file="${OUTPUT_DIR}/${hostname}_disk_usage.csv"
log_file="${OUTPUT_DIR}/${hostname}_torchrun.log"
summary_file="${OUTPUT_DIR}/${hostname}_summary.csv"

# Export disk usage file path
export DISK_USAGE_FILE="$disk_usage_file"

# Clear logs
: > "$log_file"
: > "$summary_file"
: > "$disk_usage_file"

echo "Hostname: $hostname"

# Determine node rank and master IP based on hostname and NCCL_SOCKET_IFNAME
if [[ $hostname == *master* ]]; then
    node_rank=0

    # Get the list of interfaces from NCCL_SOCKET_IFNAME or default to net1
    interfaces=${NCCL_SOCKET_IFNAME:-net1}
    for iface in ${interfaces//,/ }; do
        ip_candidate=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
        if [[ -n "$ip_candidate" ]]; then
            master_ip="$ip_candidate"
            break
        fi
    done

    if [[ -z "$master_ip" ]]; then
        echo "No valid interface found for NCCL_SOCKET_IFNAME=$interfaces. Exiting."
        exit 1
    fi

    # Write the selected IP to the file
    echo "$master_ip" > "$master_ip_file"
else
    # Workers read the master IP from the file
    while [ ! -f "$master_ip_file" ]; do
        echo "Waiting for master IP file..."
        sleep 1
    done
    master_ip=$(cat "$master_ip_file")
    if [[ -z "$master_ip" ]]; then
        echo "Master IP file is empty. Exiting."
        exit 1
    fi

    # Extract the worker's rank from its hostname
    if [[ $hostname =~ worker-([0-9]+)$ ]]; then
        node_rank=$((BASH_REMATCH[1] + 1))
    else
        echo "Failed to determine node rank from hostname: $hostname. Exiting."
        exit 1
    fi
fi

echo "Using master IP: $master_ip and node rank: $node_rank"

# Start background scripts for metrics and disk usage
bash "$METRICS_SCRIPT" & METRICS_PID=$!
bash "$DISK_USAGE_SCRIPT" & DISK_USAGE_PID=$!

torchrun_cmd=(
    "torchrun"
    "--nnodes=$NNODES"
    "--node_rank=$node_rank"
    "--nproc_per_node=$NPROC_PER_NODE"
    "--master_addr=$master_ip"
    "--master_port=$MASTER_PORT"
    "$TRAINING_SCRIPT"
    "--model_name_or_path=$MODEL_NAME_OR_PATH"
    "--num_train_epochs=$NUM_TRAIN_EPOCHS"
    "--learning_rate=$LEARNING_RATE"
    "--lr_scheduler_type=$LR_SCHEDULER_TYPE"
    "${SEED:+--seed=$SEED}"
    "--fsdp=$FSDP"
    "--fsdp_config=$FSDP_CONFIG"
    "--save_steps=$SAVE_STEPS"
    "--training_data_path=$TRAINING_DATA_PATH"
    "--torch_dtype=$TORCH_DTYPE"
    "--logging_strategy=$LOGGING_STRATEGY"
    "--logging_steps=$LOGGING_STEPS"
    "--per_device_train_batch_size=$PER_DEVICE_TRAIN_BATCH_SIZE"
    "--num_workers=$NUM_WORKERS"
    "--output_dir=$OUTPUT_DIR"
    "${MAX_SEQ_LENGTH:+--max_seq_length=$MAX_SEQ_LENGTH}"
    "--dataset_text_field=text"
    "--packing=True"
    #"--gradient_checkpointing=True"
)

# Add quantization parameters if enabled
if [[ "$QUANTIZATION_ENABLED" == "true" ]]; then
    torchrun_cmd+=(
        "--use_4bit_quantization=True"
        "--bnb_4bit_compute_dtype=bfloat16"
        "--bnb_4bit_quant_storage_dtype=bfloat16"
        "--use_nested_quant=True"
    )
fi

# Add PEFT_METHOD parameters if enabled
if [[ "$PEFT_METHOD_ENABLED" == "true" ]]; then
    torchrun_cmd+=(
        "--target_modules=$TARGET_MODULES"
        "--lora_r=$LORA_R"
        "--lora_alpha=$LORA_ALPHA"
        "--lora_dropout=$LORA_DROPOUT"
        "--peft_method=$PEFT_METHOD"
    )
fi

# Join the command into a single string for execution
torchrun_cmd_str=$(printf "%s " "${torchrun_cmd[@]}")

# Output the constructed command (optional)
echo "Constructed and executing torchrun command: $torchrun_cmd_str"

# Execute the torchrun command and log output
eval "$torchrun_cmd_str" | tee "$log_file"

# Stop background processes
echo "torchrun completed. Stopping metrics and disk usage collection..."
kill "$METRICS_PID"
kill "$DISK_USAGE_PID"

# Append hardware metrics to summary
if [[ -f "$metrics_file" ]]; then
    echo -e "\n--- Hardware Metrics ---" >> "$summary_file"
    cat "$metrics_file" >> "$summary_file"
else
    echo "No hardware metrics file found." >> "$summary_file"
fi

# Append disk usage to summary
if [[ -f "$disk_usage_file" ]]; then
    echo -e "\n--- Disk Usage ---" >> "$summary_file"
    cat "$disk_usage_file" >> "$summary_file"
else
    echo "No disk usage file found." >> "$summary_file"
fi

# Parse statistics from the log file
echo -e "\n--- Statistics Summary ---" >> "$summary_file"
echo "loss,grad_norm,learning_rate,epoch" >> "$summary_file"
grep -o "{'loss': [^}]*}" "$log_file" | sed -e "s/[{}']//g" -e "s/: /,/g" | awk -F, '{print $2,$4,$6,$8}' OFS=, >> "$summary_file"

# Parse final result from the log file
echo -e "\n--- Final Results ---" >> "$summary_file"
echo "train_runtime,train_samples_per_second,train_steps_per_second,train_loss,epoch" >> "$summary_file"
grep -o "{'train_runtime': [^}]*}" "$log_file" | sed -e "s/[{}']//g" -e "s/: /,/g" | awk -F, '{print $2,$4,$6,$8,$10}' OFS=, >> "$summary_file"

# Display summary
echo -e "\n--- Full Summary ---"
cat "$summary_file"
