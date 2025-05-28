#!/bin/bash
set -e

echo "Starting migration script..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Created temporary directory: ${TEMP_DIR}"

# Read configuration file
CONFIG_FILE="/opt/config.properties"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE does not exist"
    exit 1
fi

# Read bucket information from configuration file
BUCKET_FC_ENV_PIPELINE=$(grep "BUCKET_FC_ENV_PIPELINE" $CONFIG_FILE | cut -d'=' -f2)
BUCKET_FC_KERNELS=$(grep "BUCKET_FC_KERNELS" $CONFIG_FILE | cut -d'=' -f2)
BUCKET_FC_VERSIONS=$(grep "BUCKET_FC_VERSIONS" $CONFIG_FILE | cut -d'=' -f2)
ARCHITECTURE=$(grep "^architecture=" $CONFIG_FILE | cut -d'=' -f2 || echo "x86_64")

if [ -z "$BUCKET_FC_ENV_PIPELINE" ] || [ -z "$BUCKET_FC_KERNELS" ] || [ -z "$BUCKET_FC_VERSIONS" ]; then
    echo "Error: Could not read all required bucket information from configuration file"
    echo "BUCKET_FC_ENV_PIPELINE: $BUCKET_FC_ENV_PIPELINE"
    echo "BUCKET_FC_KERNELS: $BUCKET_FC_KERNELS"
    echo "BUCKET_FC_VERSIONS: $BUCKET_FC_VERSIONS"
    exit 1
fi

echo "Bucket information read from configuration file:"
echo "BUCKET_FC_ENV_PIPELINE: $BUCKET_FC_ENV_PIPELINE"
echo "BUCKET_FC_KERNELS: $BUCKET_FC_KERNELS"
echo "BUCKET_FC_VERSIONS: $BUCKET_FC_VERSIONS"
echo "Architecture: $ARCHITECTURE"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI..."
    sudo apt-get install -y awscli
    echo "AWS CLI installation completed"
else
    echo "AWS CLI is already installed"
fi

# Create subdirectories
mkdir -p "${TEMP_DIR}/kernels"
mkdir -p "${TEMP_DIR}/firecrackers"

# Download envd binaries from GitHub releases based on architecture
echo "Downloading envd binaries for architecture: $ARCHITECTURE"

# Determine architecture suffix for GitHub downloads
if [ "$ARCHITECTURE" = "arm64" ]; then
    ARCH_SUFFIX="arm64"
else
    ARCH_SUFFIX="x86_64"
fi
# Download envd v0.0.1
echo "Downloading envd v0.0.1 for $ARCH_SUFFIX..."
curl -L "https://github.com/tensorchord/envd/releases/download/v0.0.1/envd_0.0.1_Linux_${ARCH_SUFFIX}" -o "${TEMP_DIR}/envd-v0.0.1"
chmod +x "${TEMP_DIR}/envd-v0.0.1"
# Download envd v0.2.0 (replace original 0.1.5)
echo "Downloading envd v0.2.0 for $ARCH_SUFFIX..."
curl -L "https://github.com/tensorchord/envd/releases/download/v0.2.0/envd_0.2.0_Linux_${ARCH_SUFFIX}" -o "${TEMP_DIR}/envd"
chmod +x "${TEMP_DIR}/envd"

# Download architecture-specific kernels and firecrackers
if [ "$ARCHITECTURE" = "arm64" ]; then
    ARCH_SUFFIX="aarch64"
else
    ARCH_SUFFIX="x86_64"
fi
release_url="https://github.com/firecracker-microvm/firecracker/releases"
latest_version=$(basename $(curl -fsSLI -o /dev/null -w  %{url_effective} ${release_url}/latest))
CI_VERSION=${latest_version%.*}
latest_kernel_key=$(curl "http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/$CI_VERSION/$ARCH_SUFFIX/vmlinux-&list-type=2" \
    | grep -oP "(?<=<Key>)(firecracker-ci/$CI_VERSION/$ARCH_SUFFIX/vmlinux-[0-9]+\.[0-9]+\.[0-9]{1,3})(?=</Key>)" \
    | sort -V | tail -1)
VMLINUX_VERSION=$(echo $latest_kernel_key | awk -F/ '{print $NF}')
mkdir -p "${TEMP_DIR}/kernels/$VMLINUX_VERSION"

# Download a kernel binary
wget "https://s3.amazonaws.com/spec.ccfc.min/${latest_kernel_key}" -O "${TEMP_DIR}/kernels/$VMLINUX_VERSION/vmlinux.bin"

# Download a firecracker binary
curl -L ${release_url}/download/${latest_version}/firecracker-${latest_version}-${ARCH_SUFFIX}.tgz | tar -xz
mkdir -p "${TEMP_DIR}/firecrackers/${latest_version}"
mv release-${latest_version}-${ARCH_SUFFIX}/firecracker-${latest_version}-${ARCH_SUFFIX} \
   ${TEMP_DIR}/firecrackers/${latest_version}/firecracker
rm -rf release-${latest_version}-${ARCH_SUFFIX}

echo "File download completed"

# Upload to S3
echo "Starting file upload to S3..."
# Copy envd binary to S3 bucket
aws s3 cp "${TEMP_DIR}/envd-v0.0.1" "s3://${BUCKET_FC_ENV_PIPELINE}/envd-v0.0.1" --recursive
aws s3 cp "${TEMP_DIR}/envd" "s3://${BUCKET_FC_ENV_PIPELINE}/envd" --recursive
aws s3 cp --recursive "${TEMP_DIR}/kernels/" "s3://${BUCKET_FC_KERNELS}/"
aws s3 cp --recursive "${TEMP_DIR}/firecrackers/" "s3://${BUCKET_FC_VERSIONS}/"
echo "File upload to S3 completed"

# Clean up temporary directory
echo "Cleaning up temporary files..."
rm -rf "${TEMP_DIR}"
echo "Temporary files cleaned up"

echo "Migration completed!"