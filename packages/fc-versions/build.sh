#!/bin/bash

set -euo pipefail

function build_version {
  local version=$1
  local arch=$2
  echo "Starting build for Firecracker commit: $version for architecture: $arch"

  echo "Checking out repo for Firecracker at commit: $version"
  git checkout "${version}"

  # The format will be: latest_tag_latest_commit_hash — v1.7.0-dev_g8bb88311
  version_name=$(git describe --tags --abbrev=0 $(git rev-parse HEAD))_$(git rev-parse --short HEAD)
  echo "Version name: $version_name"

  echo "Building Firecracker version: $version_name for architecture: $arch"
  
  if [ "$arch" = "arm64" ]; then
    # Build for ARM64
    tools/devtool -y build --release --libc musl --target aarch64-unknown-linux-musl
    
    echo "Copying finished ARM64 build to builds directory"
    mkdir -p "../builds/${version_name}-arm64"
    cp build/cargo_target/aarch64-unknown-linux-musl/release/firecracker "../builds/${version_name}-arm64/firecracker"
  else
    # Build for x86_64
    tools/devtool -y build --release
    
    echo "Copying finished x86_64 build to builds directory"
    mkdir -p "../builds/${version_name}"
    cp build/cargo_target/x86_64-unknown-linux-musl/release/firecracker "../builds/${version_name}/firecracker"
  fi
}

# Detect system architecture or use provided argument
ARCH=${1:-$(uname -m)}
if [ "$ARCH" = "aarch64" ]; then
  ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
  ARCH="x86_64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

echo "Building for architecture: $ARCH"

echo "Cloning the Firecracker repository"
git clone https://github.com/firecracker-microvm/firecracker.git firecracker
cd firecracker

# Install Rust if not already installed
if ! command -v rustup &> /dev/null; then
  echo "Installing Rust..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source $HOME/.cargo/env
fi

# Add target for ARM64 if building for ARM64
if [ "$ARCH" = "arm64" ]; then
  echo "Adding ARM64 target to Rust"
  rustup target add aarch64-unknown-linux-musl
fi

grep -v '^ *#' <../firecracker_versions.txt | while IFS= read -r version; do
  build_version "$version" "$ARCH"
done

cd ..
rm -rf firecracker
