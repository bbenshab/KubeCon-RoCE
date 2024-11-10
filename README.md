# Distributed Training with PyTorch and Metrics Monitoring

A comprehensive repository for setting up distributed training workflows using PyTorch and Kubeflow, complete with metrics collection for GPUs, CPUs, memory, disk usage, and network throughput.

You may use the provided docker file or build your own image.
## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Setup](#setup)
   - [Requirements](#requirements)
   - [Installation](#installation)
4. [Usage](#usage)
   - [Training with PyTorchJob](#training-with-pytorchjob)
   - [Metrics Collection](#metrics-collection)
5. [Configuration](#configuration)
6. [Logging Details](#logging-details)
7. [Examples](#examples)

## Overview

This repository provides a robust framework for distributed training with PyTorch using Kubeflow's PyTorchJob. It includes detailed metrics collection scripts for monitoring resource usage across GPUs, CPUs, memory, and disk space during training.

## Features

- **Distributed Training**:
  - Deploy distributed PyTorch training jobs with `PyTorchJob` CRDs on Kubernetes.
  - Leverages RDMA-enabled GPUs for optimized throughput.
  
- **Metrics Collection**:
  - Logs GPU utilization, memory, and power.
  - Tracks CPU and memory usage.
  - Monitors disk and network throughput.

- **Flexible Configurations**:
  - Adjustable logging intervals.
  - Supports fine-tuning and evaluation of large-scale datasets.

- **Efficient Resource Management**:
  - Utilizes advanced techniques like gradient checkpointing and mixed precision for VRAM optimization.

## Setup

### Requirements

- Kubernetes cluster with Kubeflow installed
- NVIDIA GPUs with RDMA support and NCCL configured
- Python 3.8+
- PyTorch 2.3.1+cu121
- Persistent storage configured for training datasets and outputs

### Installation

1. Clone this repository:
   ```bash
   git clone [https://github.com/your-username/your-repo-name.git](https://github.com/bbenshab/KubeCon-RoCE.git)
   cd KubeCon-RoCE
   ```

2. Install the Kubeflow PyTorchJob CRD:
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubeflow/pytorch-operator/master/manifests/pytorch-operator.yaml
   ```

3. Configure your Kubernetes environment for multi-node, RDMA-enabled training.

## Usage

### Training with PyTorchJob

1. Define your `PyTorchJob` YAML configuration for training. Below is an example configuration:
   ```yaml
   apiVersion: kubeflow.org/v1
   kind: PyTorchJob
   metadata:
     name: pytorch-training
     namespace: default
   spec:
     pytorchReplicaSpecs:
       Master:
         replicas: 1
         restartPolicy: Never
         template:
           spec:
             containers:
               - name: pytorch
                 image: image-name
                 env:
                   - name: NCCL_DEBUG
                     value: INFO
                   - name: TRAINING_SCRIPT
                     value: /mnt/storage/fms-hf-tuning/tuning/sft_trainer.py
                 volumeMounts:
                   - name: storage-volume
                     mountPath: /mnt/storage
       Worker:
         replicas: 1
         restartPolicy: Never
         template:
           spec:
             containers:
               - name: pytorch
                 image: image-name
                 volumeMounts:
                   - name: storage-volume
                     mountPath: /mnt/storage
     ```
   
2. Submit the PyTorchJob to your Kubernetes cluster:
   ```bash
   kubectl apply -f pytorchjob.yaml
   ```

3. Monitor the job status:
   ```bash
   kubectl get pytorchjobs
   ```

### Metrics Collection

collect_metrics.sh will run during the training and print the statistics to the pod logs when training completes.

Monitored metrics include:
- GPU utilization, memory, and power usage
- CPU & memory utilization
- Disk and network throughput

## Configuration

This repository leverages multiple configurable environment variables to fine-tune the training setup. Below are the key variables extracted from the YAML configuration:

### General Settings
- `HF_HOME`: Temporary directory for Hugging Face cache (default: `/tmp/output`).
- `OUTPUT_DIR`: Directory where training outputs, checkpoints, and logs are saved.
- `SHARED_PATH`: Path to a shared directory across distributed nodes (default: `/mnt/shared`).
- `TRAINING_SCRIPT`: Path to the training script (e.g., `/mnt/storage/fms-hf-tuning/tuning/sft_trainer.py`).
- `MODEL_NAME_OR_PATH`: Path to the pre-trained model or model checkpoint for fine-tuning.
- `TRAINING_DATA_PATH`: Path to the dataset file for training (e.g., `/mnt/storage/openwebtext.jsonl`).

### Distributed Training Settings
- `NNODES`: Number of nodes participating in the training job.
- `NPROC_PER_NODE`: Number of processes per node (typically matches the number of GPUs per node).
- `MASTER_PORT`: Port used for communication between nodes.
- `BACKEND`: Backend used for distributed training (e.g., `nccl`).

### Training Hyperparameters
- `NUM_TRAIN_EPOCHS`: Number of epochs for training.
- `LEARNING_RATE`: Learning rate for the optimizer (e.g., `2e-5`).
- `LR_SCHEDULER_TYPE`: Type of learning rate scheduler (e.g., `cosine`).
- `MAX_SEQ_LENGTH`: Maximum sequence length for tokenized input.
- `PER_DEVICE_TRAIN_BATCH_SIZE`: Batch size per GPU.
- `SAVE_STEPS`: Frequency (in steps) to save checkpoints and log metrics.

### Fine-Tuning and Optimization
- `FSDP`: Configuration for Fully Sharded Data Parallelism (e.g., `full_shard`).
- `FSDP_CONFIG`: Path to the FSDP configuration JSON file.
- `TORCH_DTYPE`: Data type for PyTorch tensors (e.g., `bfloat16` for mixed precision training).
- `PEFT_METHOD`: Fine-tuning method (e.g., `lora`).
- `PEFT_METHOD_ENABLED`: Whether to enable the PEFT method (`true` or `false`).
- `TARGET_MODULES`: Target modules for LoRA fine-tuning (e.g., `q_proj v_proj k_proj o_proj`).
- `LORA_R`: LoRA rank (e.g., `8`).
- `LORA_ALPHA`: LoRA scaling factor (e.g., `8`).
- `LORA_DROPOUT`: LoRA dropout rate (e.g., `0.1`).

### Logging and Metrics
- `LOGGING_STRATEGY`: Logging strategy (`steps` or `epoch`).
- `LOGGING_STEPS`: Frequency (in steps) for logging metrics.
- `NUM_WORKERS`: Number of workers for data loading.

### Networking and RDMA
- `ENABLE_RDMA`: Whether to enable RDMA (`true` or `false`).
- `NCCL_SOCKET_IFNAME`: Network interfaces for NCCL communication (e.g., `net1-0,net1-1`).
- `NCCL_IB_HCA`: RDMA interfaces (e.g., `mlx5_3:1,mlx5_0:1`).
- `NCCL_IB_GID_INDEX`: GID index for RDMA (e.g., `3`).

These environment variables can be adjusted in the YAML file under the `env` section to customize the training configuration. 

## Logging Details

Output files include:
- **Hardware metrics** (`*-hwstat.csv`): Tracks GPU, CPU, and memory usage over time.
- **Metrics logs** (`*-metrics.log`): Includes disk usage and storage information.
- **Training logs**: Captures training progress, loss, and evaluation metrics.

## Examples

### Submitting a PyTorchJob

```bash
kubectl apply -f pytorchjob.yaml
```

### Monitoring the PyTorchJob

```bash
kubectl get pytorchjobs
```
