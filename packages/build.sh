#!/bin/bash
# Set error handling - script will exit if any command fails
set -e

# Navigate to the directory containing the script
cd "$(dirname "$0")"

# Define project root directory (adjust according to actual situation)
PROJECT_ROOT=$(pwd)
echo "Project root directory: $PROJECT_ROOT"

# Get architecture from config file or use system architecture
if [ -f "/opt/config.properties" ]; then
  ARCHITECTURE=$(grep "^architecture=" /opt/config.properties | cut -d'=' -f2 || echo "")
fi

if [ -z "$ARCHITECTURE" ]; then
  # Detect system architecture
  ARCH=$(uname -m)
  if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCHITECTURE="arm64"
  elif [ "$ARCH" = "x86_64" ]; then
    ARCHITECTURE="x86_64"
  else
    echo "Unsupported architecture: $ARCH"
    exit 1
  fi
fi

echo "Building for architecture: $ARCHITECTURE"
export ARCHITECTURE

# Build and upload API module
echo "=== Building and uploading API module ==="
cd "$PROJECT_ROOT/api" || { echo "API directory not found"; exit 1; }
echo "Current directory: $(pwd)"
make build-and-upload-aws
echo "API module build and upload completed successfully"

# Build and upload client-proxy module
echo "=== Building and uploading client-proxy module ==="
cd "$PROJECT_ROOT/client-proxy" || { echo "client-proxy directory not found"; exit 1; }
echo "Current directory: $(pwd)"
make build-and-upload-aws
echo "client-proxy module build and upload completed successfully"

# Build and upload docker-reverse-proxy module
# echo "=== Building and uploading docker-reverse-proxy module ==="
# cd "$PROJECT_ROOT/docker-reverse-proxy" || { echo "docker-reverse-proxy directory not found"; exit 1; }
# echo "Current directory: $(pwd)"
# make build-and-upload-aws
# echo "docker-reverse-proxy module build and upload completed successfully"

# Build and upload orchestrator module
echo "=== Building and uploading orchestrator module ==="
cd "$PROJECT_ROOT/orchestrator" || { echo "orchestrator directory not found"; exit 1; }
echo "Current directory: $(pwd)"
make build-and-upload
echo "orchestrator module build and upload completed successfully"

# Build and upload template-manager module
echo "=== Building and uploading template-manager module ==="
cd "$PROJECT_ROOT/template-manager" || { echo "template-manager directory not found"; exit 1; }
echo "Current directory: $(pwd)"
make build-and-upload
echo "template-manager module build and upload completed successfully"

# Build and upload template-manager module
# echo "=== Building envd module ==="
# cd "$PROJECT_ROOT/envd" || { echo "envd directory not found"; exit 1; }
# echo "Current directory: $(pwd)"
# make build
# echo "envd module build  completed successfully"

# Upload envd and other required files
echo "=== Uploading envd and required files ==="
cd "$PROJECT_ROOT" || { echo "Cannot return to project root"; exit 1; }
echo "Current directory: $(pwd)"
chmod u+x upload.sh
./upload.sh
echo "envd upload completed successfully"

# Build and upload Firecracker kernels for the current architecture
echo "=== Building and uploading Firecracker kernels for $ARCHITECTURE ==="
cd "$PROJECT_ROOT/fc-kernels" || { echo "fc-kernels directory not found"; exit 1; }
echo "Current directory: $(pwd)"
./build.sh "$ARCHITECTURE"
echo "Firecracker kernels build completed successfully"

# Build and upload Firecracker versions for the current architecture
echo "=== Building and uploading Firecracker versions for $ARCHITECTURE ==="
cd "$PROJECT_ROOT/fc-versions" || { echo "fc-versions directory not found"; exit 1; }
echo "Current directory: $(pwd)"
./build.sh "$ARCHITECTURE"
echo "Firecracker versions build completed successfully"

echo "=== All builds and uploads completed successfully ==="