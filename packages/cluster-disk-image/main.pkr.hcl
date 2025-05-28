packer {
  required_version = ">=1.8.4"
  required_plugins {
    amazon = {
      version = "1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "orch" {
  ami_name      = "${var.aws_ami_name}-${formatdate("YYYY-MM-DD-hh-mm-ss", timestamp())}"
  instance_type = var.aws_instance_type
  region        = var.aws_region

  # Dynamic source AMI filter based on architecture
  source_ami_filter {
    filters = {
      name                = var.architecture == "arm64" ? "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*" : "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"] # Canonical's AWS account ID
  }
  
  ssh_username = "ubuntu"
  
  # Enable nested virtualization
  ami_virtualization_type = "hvm"
  
  # Use EBS for the root volume
  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 10
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = [
    "source.amazon-ebs.orch"
  ]

  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y ca-certificates curl"
    ]
  }
  
  provisioner "file" {
    source      = "${path.root}/setup/supervisord.conf"
    destination = "/tmp/supervisord.conf"
  }

  provisioner "file" {
    source      = "${path.root}/setup"
    destination = "/tmp"
  }

  provisioner "file" {
    source      = "${path.root}/setup/daemon.json"
    destination = "/tmp/daemon.json"
  }

  provisioner "file" {
    source      = "${path.root}/setup/limits.conf"
    destination = "/tmp/limits.conf"
  }

  # Install Docker
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /etc/docker",
      "sudo mv /tmp/daemon.json /etc/docker/daemon.json",
      "sudo curl -fsSL https://get.docker.com -o get-docker.sh",
      "sudo sh get-docker.sh",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y unzip jq net-tools qemu-utils make build-essential openssh-client openssh-server", # TODO: openssh-server is updated to prevent security vulnerabilities
    ]
  }
  
  provisioner "shell" {
    only = ["amazon-ebs.orch"]
    inline = [
      "sudo apt-get update && sudo apt-get upgrade -y",
      "ARCH=$(uname -m)",
      "if [ \"$ARCH\" = \"x86_64\" ]; then",
      "  sudo curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
      "elif [ \"$ARCH\" = \"aarch64\" ]; then",
      "  sudo curl 'https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip' -o 'awscliv2.zip'",
      "else",
      "  echo \"Unsupported architecture: $ARCH\"",
      "  exit 1",
      "fi",
      "sudo apt-get install -y zip",
      "sudo unzip awscliv2.zip",
      "sudo ./aws/install",
      "sudo apt-get install -y s3fs-fuse || echo 'Failed to install s3fs-fuse, will install from source'"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo snap install go --classic"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo systemctl start docker",
      "sudo usermod -aG docker $USER",
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/gruntwork",
      "git clone --branch v0.1.3 https://github.com/gruntwork-io/bash-commons.git /tmp/bash-commons",
      "sudo cp -r /tmp/bash-commons/modules/bash-commons/src /opt/gruntwork/bash-commons",
    ]
  }

  provisioner "shell" {
    script          = "${path.root}/setup/install-consul.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} ARCH=${var.architecture} {{ .Path }} --version ${var.consul_version}"
  }

  provisioner "shell" {
    script          = "${path.root}/setup/install-nomad.sh"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} ARCH=${var.architecture} {{ .Path }} --version ${var.nomad_version}"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/nomad/plugins",
    ]
  }
  
  provisioner "shell" {
    only = ["amazon-ebs.orch"]
    inline = [
      "ARCH=$(uname -m)",
      "sudo mkdir -p /opt/aws/amazon-cloudwatch-agent/bin/",
      "if [ \"$ARCH\" = \"x86_64\" ]; then",
      "  sudo wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb",
      "elif [ \"$ARCH\" = \"aarch64\" ]; then",
      "  sudo wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb -O /tmp/amazon-cloudwatch-agent.deb",
      "else",
      "  echo \"Unsupported architecture: $ARCH\"",
      "  exit 1",
      "fi",
      "sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb || sudo apt-get install -f -y",
      "sudo systemctl enable amazon-cloudwatch-agent"
    ]
  }

  provisioner "shell" {
    inline = [
      # Increase the maximum number of open files
      "sudo mv /tmp/limits.conf /etc/security/limits.conf",
      # Increase the maximum number of connections by 4x
      "echo 'net.netfilter.nf_conntrack_max = 2097152' | sudo tee -a /etc/sysctl.conf",
    ]
  }
}
