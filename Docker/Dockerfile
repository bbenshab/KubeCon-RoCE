ARG BASE_UBI_IMAGE_TAG=9.4
ARG PYTHON_VERSION=3.11
ARG ENABLE_FMS_ACCELERATION=false
ARG ENABLE_AIM=false

FROM registry.access.redhat.com/ubi9/ubi:${BASE_UBI_IMAGE_TAG} AS base

# Install Python, basic tools, EPEL for nvtop, and nvtop
RUN dnf install -y python${PYTHON_VERSION} python${PYTHON_VERSION}-devel procps git \
    && dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %{rhel}).noarch.rpm \
    && dnf install -y --setopt=install_weak_deps=False nvtop git jq wget vim tmux qperf sysstat \
    && python -m ensurepip --upgrade \
    && python -m pip install --upgrade pip setuptools --no-cache-dir \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/lib/dnf /var/log/*

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# Install CUDA
ARG CUDA_VERSION=12.1.0
ARG NV_CUDA_LIB_VERSION=12.1.0-1
ARG NV_CUDA_CUDART_VERSION=12.1.55-1
ARG NV_CUDA_COMPAT_VERSION=530.30.02-1

RUN dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo \
    && dnf install -y --nodocs ethtool iputils net-tools \
        cuda-cudart-12-1-${NV_CUDA_CUDART_VERSION} \
        cuda-compat-12-1-${NV_CUDA_COMPAT_VERSION} \
        libcudnn8 libcudnn8-devel \
        nvidia-container-toolkit \
    && echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf \
    && echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf \
    && ldconfig \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/lib/dnf /var/log/*

ENV CUDA_HOME="/usr/local/cuda" \
    PATH="/usr/local/nvidia/bin:${CUDA_HOME}/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/lib64:/usr/local/nvidia/lib:/usr/local/nvidia/lib64:$CUDA_HOME/lib64:$CUDA_HOME/extras/CUPTI/lib64:${LD_LIBRARY_PATH}"

RUN python -m pip install torch==2.3.1+cu121 -f https://download.pytorch.org/whl/torch_stable.html --no-cache-dir

# CUDA development libraries
ARG NV_CUDA_CUDART_DEV_VERSION=12.1.55-1
ARG NV_NVML_DEV_VERSION=12.1.55-1
ARG NV_LIBCUBLAS_DEV_VERSION=12.1.0.26-1
ARG NV_LIBNPP_DEV_VERSION=12.0.2.50-1
ARG NV_LIBNCCL_DEV_PACKAGE_VERSION=2.18.3-1+cuda12.1

RUN dnf install -y --nodocs \
        cuda-command-line-tools-12-1-${NV_CUDA_LIB_VERSION} \
        cuda-libraries-devel-12-1-${NV_CUDA_LIB_VERSION} \
        cuda-minimal-build-12-1-${NV_CUDA_LIB_VERSION} \
        cuda-cudart-devel-12-1-${NV_CUDA_CUDART_DEV_VERSION} \
        cuda-nvml-devel-12-1-${NV_NVML_DEV_VERSION} \
        libcublas-devel-12-1-${NV_LIBCUBLAS_DEV_VERSION} \
        libnpp-devel-12-1-${NV_LIBNPP_DEV_VERSION} \
        libnccl-devel-${NV_LIBNCCL_DEV_PACKAGE_VERSION} \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/lib/dnf /var/log/*

ENV LIBRARY_PATH="$CUDA_HOME/lib64/stubs"

# Remove system-installed requests and other conflicting packages
RUN dnf remove -y python3-requests python3-dateutil python3-fsspec

# Python packages including fms-hf-tuning[fms-accel] and plugin installation
RUN python -m pip install --upgrade setuptools wheel cmake --no-cache-dir \
    && python -m pip install fms-hf-tuning[fms-accel] flash-attn --no-cache-dir \
    && python -m fms_acceleration.cli install fms_acceleration_peft

RUN if [[ "${ENABLE_AIM}" == "true" ]]; then \
        python -m pip install fms-hf-tuning[aim] --no-cache-dir; \
    fi

# Install Mellanox drivers
RUN rpm --import https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox \
    && curl -o /etc/yum.repos.d/mellanox_mlnx_ofed.repo https://linux.mellanox.com/public/repo/mlnx_ofed/latest/rhel9.4/mellanox_mlnx_ofed.repo \
    && dnf install -y --nodocs rdma-core infiniband-diags libibverbs libibumad librdmacm \
    && dnf clean all \
    && rm -rf /var/cache/dnf /var/lib/dnf /var/log/*

# Install Nsight Compute CLI
#RUN dnf install -y dnf-plugins-core && \
#    dnf config-manager --add-repo=https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo && \
#    dnf install -y --nodocs cuda-nsight-compute-12-1 && \
#    dnf clean all && \
#    rm -rf /var/cache/dnf /var/lib/dnf /var/log/*
#ENV PATH="/usr/local/cuda/bin:$PATH"

# Add workspace directory to the image
COPY workspace /workspace

# Set the working directory to /workspace
WORKDIR /workspace

# Set the entrypoint script
ENTRYPOINT ["./enterypoint.sh"]

#Note this image is blasted with all kind of debug tools that are not requried and may be removed to reduce the image size
