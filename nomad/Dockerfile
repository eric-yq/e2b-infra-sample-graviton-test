FROM ubuntu:22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Update and install base packages
RUN apt-get update && apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    wget \
    git \
    unzip \
    build-essential \
    python3 \
    python3-pip \
    python3-dev \
    sudo \
    vim \
    jq \
    iputils-ping \
    net-tools \
    dnsutils \
    locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Create a non-root user
RUN useradd -m -s /bin/bash -G sudo developer \
    && echo "developer ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/developer

# Set up Python environment
RUN pip3 install --no-cache-dir --upgrade pip \
    && pip3 install --no-cache-dir \
    ipython \
    jupyter \
    numpy \
    pandas \
    requests

# Set ownership for developer user
USER developer
WORKDIR /home/developer

# Set default command
CMD ["/bin/bash"]