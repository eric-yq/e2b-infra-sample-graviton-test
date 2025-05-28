#!/bin/bash

set -euo pipefail

rm -rf linux

function build_version {
  local version=$1
  local arch=$2
  echo "Starting build for kernel version: $version for architecture: $arch"

  if [ "$arch" = "arm64" ]; then
    cp ../configs/"${version}.arm64.config" .config
  else
    cp ../configs/"${version}.config" .config
  fi

  echo "Checking out repo for kernel at version: $version"
  git fetch --depth 1 origin "v${version}"
  git checkout FETCH_HEAD

  echo "Building kernel version: $version for architecture: $arch"
  if [ "$arch" = "arm64" ]; then
    make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- vmlinux -j "$(nproc)"
    mkdir -p "../builds/vmlinux-${version}-arm64"
    cp vmlinux "../builds/vmlinux-${version}-arm64/vmlinux.bin"
  else
    make vmlinux -j "$(nproc)"
    mkdir -p "../builds/vmlinux-${version}"
    cp vmlinux "../builds/vmlinux-${version}/vmlinux.bin"
  fi

  echo "Copying finished build to builds directory"
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

# Install cross-compilation tools if building for ARM64
if [ "$ARCH" = "arm64" ]; then
  echo "Installing ARM64 cross-compilation tools"
  apt-get update
  apt-get install -y gcc-aarch64-linux-gnu
fi

echo "Cloning the linux kernel repository"
git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux
cd linux

grep -v '^ *#' <../kernel_versions.txt | while IFS= read -r version; do
  build_version "$version" "$ARCH"
done

cd ..
rm -rf linux
