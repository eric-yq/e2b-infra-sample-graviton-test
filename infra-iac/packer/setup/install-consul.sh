#!/bin/bash

set -e

# Import the appropriate bash commons libraries
readonly BASH_COMMONS_DIR="/opt/gruntwork/bash-commons"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly DEFAULT_INSTALL_PATH="/opt/consul"
readonly DEFAULT_CONSUL_USER="consul"
readonly DOWNLOAD_PACKAGE_PATH="/tmp/consul.zip"
readonly SYSTEM_BIN_DIR="/usr/local/bin"

if [[ ! -d "$BASH_COMMONS_DIR" ]]; then
  echo "ERROR: this script requires that bash-commons is installed in $BASH_COMMONS_DIR. See https://github.com/gruntwork-io/bash-commons for more info."
  exit 1
fi

source "$BASH_COMMONS_DIR/assert.sh"
source "$BASH_COMMONS_DIR/log.sh"
source "$BASH_COMMONS_DIR/os.sh"

function print_usage {
  echo
  echo "Usage: install-consul [OPTIONS]"
  echo
  echo "This script can be used to install Consul and its dependencies. This script has been tested with Ubuntu 18.04."
  echo
  echo "Options:"
  echo
  echo -e "  --version\t\tThe version of Consul to install. Optional if download-url is provided."
  echo -e "  --download-url\t\tUrl to exact Consul package to be installed. Optional if version is provided."
  echo -e "  --path\t\tThe path where Consul should be installed. Optional. Default: $DEFAULT_INSTALL_PATH."
  echo -e "  --user\t\tThe user who will own the Consul install directories. Optional. Default: $DEFAULT_CONSUL_USER."
  echo -e "  --arch\t\tThe architecture to use (x86_64 or arm64). Optional. Default: Auto-detected."
  echo -e "  --ca-file-path\t\tPath to a PEM-encoded certificate authority used to encrypt and verify authenticity of client and server connections. Will be installed under <install-path>/tls/ca."
  echo -e "  --cert-file-path\t\tPath to a PEM-encoded certificate, which will be provided to clients or servers to verify the agent's authenticity. Will be installed under <install-path>/tls. Must be provided along with --key-file-path."
  echo -e "  --key-file-path\t\tPath to a PEM-encoded private key, used with the certificate to verify the agent's authenticity. Will be installed under <install-path>/tls. Must be provided along with --cert-file-path"
  echo
  echo "Example:"
  echo
  echo "  install-consul --version 1.8.3"
  echo "  install-consul --version 1.8.3 --arch arm64"
}

# A retry function that attempts to run a command a number of times and returns the output
function retry {
  local -r cmd="$1"
  local -r description="$2"

  for i in $(seq 1 5); do
    log_info "$description"

    # The boolean operations with the exit status are there to temporarily circumvent the "set -e" at the
    # beginning of this script which exits the script immediatelly for error status while not losing the exit status code
    output=$(eval "$cmd") && exit_status=0 || exit_status=$?
    log_info "$output"
    if [[ $exit_status -eq 0 ]]; then
      echo "$output"
      return
    fi
    log_warn "$description failed. Will sleep for 10 seconds and try again."
    sleep 10
  done;

  log_error "$description failed after 5 attempts."
  exit $exit_status
}

function install_dependencies {
  log_info "Installing dependencies"

  if os_is_ubuntu; then
    sudo apt-get update -y
    sudo apt-get install -y curl unzip jq
  else
    log_error "Could not find apt-get. Cannot install dependencies on this OS."
    exit 1
  fi
}

function create_consul_user {
  local -r username="$1"

  if os_user_exists "$username"; then
    echo "User $username already exists. Will not create again."
  else
    log_info "Creating user named $username"
    sudo useradd "$username"
  fi
}

function create_consul_install_paths {
  local -r path="$1"
  local -r username="$2"

  log_info "Creating install dirs for Consul at $path"
  sudo mkdir -p "$path"
  sudo mkdir -p "$path/bin"
  sudo mkdir -p "$path/config"
  sudo mkdir -p "$path/data"
  sudo mkdir -p "$path/tls/ca"

  log_info "Changing ownership of $path to $username"
  sudo chown -R "$username:$username" "$path"
}

function fetch_binary {
  local -r version="$1"
  local download_url="$2"
  local -r arch_param="$3"

  if [[ -z "$download_url" && -n "$version" ]];  then
    # Detect system architecture
    local arch
    if [[ -n "$arch_param" ]]; then
      arch="$arch_param"
      log_info "Using specified architecture: $arch"
    else
      arch=$(uname -m)
      log_info "Auto-detected architecture: $arch"
    fi
    
    local consul_arch="amd64"
    
    # Map architecture to Consul's naming convention
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
      consul_arch="arm64"
    elif [[ "$arch" == "x86_64" ]]; then
      consul_arch="amd64"
    else
      log_error "Unsupported architecture: $arch"
      exit 1
    fi
    
    log_info "Using Consul architecture: $consul_arch"
    download_url="https://releases.hashicorp.com/consul/${version}/consul_${version}_linux_${consul_arch}.zip"
  fi

  retry \
    "curl -o '$DOWNLOAD_PACKAGE_PATH' '$download_url' --location --silent --fail --show-error" \
    "Downloading Consul to $DOWNLOAD_PACKAGE_PATH"
}

function install_binary {
  local -r install_path="$1"
  local -r username="$2"

  local -r bin_dir="$install_path/bin"
  local -r consul_dest_path="$bin_dir/consul"

  unzip -d /tmp "$DOWNLOAD_PACKAGE_PATH"

  log_info "Moving Consul binary to $consul_dest_path"
  sudo mv "/tmp/consul" "$consul_dest_path"
  sudo chown "$username:$username" "$consul_dest_path"
  sudo chmod a+x "$consul_dest_path"

  local -r symlink_path="$SYSTEM_BIN_DIR/consul"
  if [[ -f "$symlink_path" ]]; then
    log_info "Symlink $symlink_path already exists. Will not add again."
  else
    log_info "Adding symlink to $consul_dest_path in $symlink_path"
    sudo ln -s "$consul_dest_path" "$symlink_path"
  fi
}

function install_tls_certificates {
  local -r path="$1"
  local -r user="$2"
  local -r ca_file_path="$3"
  local -r cert_file_path="$4"
  local -r key_file_path="$5"

  local -r consul_tls_certs_path="$path/tls"
  local -r ca_certs_path="$consul_tls_certs_path/ca"

  log_info "Moving TLS certs to $consul_tls_certs_path and $ca_certs_path"

  sudo mkdir -p "$ca_certs_path"
  sudo mv "$ca_file_path" "$ca_certs_path/"
  sudo mv "$cert_file_path" "$consul_tls_certs_path/"
  sudo mv "$key_file_path" "$consul_tls_certs_path/"

  sudo chown -R "$user:$user" "$consul_tls_certs_path/"
  sudo find "$consul_tls_certs_path/" -type f -exec chmod u=r,g=,o= {} \;
}

function install {
  local version=""
  local download_url=""
  local path="$DEFAULT_INSTALL_PATH"
  local user="$DEFAULT_CONSUL_USER"
  local ca_file_path=""
  local cert_file_path=""
  local key_file_path=""
  local arch_param=""

  while [[ $# -gt 0 ]]; do
    local key="$1"

    case "$key" in
      --version)
        version="$2"
        shift
        ;;
      --download-url)
        download_url="$2"
        shift
        ;;
      --path)
        path="$2"
        shift
        ;;
      --user)
        user="$2"
        shift
        ;;
      --arch)
        arch_param="$2"
        shift
        ;;
      --ca-file-path)
        assert_not_empty "$key" "$2"
        ca_file_path="$2"
        shift
        ;;
      --cert-file-path)
        assert_not_empty "$key" "$2"
        cert_file_path="$2"
        shift
        ;;
      --key-file-path)
        assert_not_empty "$key" "$2"
        key_file_path="$2"
        shift
        ;;
      --help)
        print_usage
        exit
        ;;
      *)
        log_error "Unrecognized argument: $key"
        print_usage
        exit 1
        ;;
    esac

    shift
  done

  assert_exactly_one_of "--version" "$version" "--download-url" "$download_url"
  assert_not_empty "--path" "$path"
  assert_not_empty "--user" "$user"

  log_info "Starting Consul install"

  install_dependencies
  create_consul_user "$user"
  create_consul_install_paths "$path" "$user"

  fetch_binary "$version" "$download_url" "$arch_param"
  install_binary "$path" "$user"

  if [[ -n "$ca_file_path" || -n "$cert_file_path" || -n "$key_file_path" ]]; then
    install_tls_certificates "$path" "$user" "$ca_file_path" "$cert_file_path" "$key_file_path"
  fi

  if command -v consul; then
    log_info "Consul install complete!";
  else
    log_info "Could not find consul command. Aborting.";
    exit 1;
  fi
}

install "$@"