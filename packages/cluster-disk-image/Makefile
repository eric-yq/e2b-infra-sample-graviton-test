ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

# Detect system architecture
ARCH := $(shell uname -m)
ifeq ($(ARCH),x86_64)
  ARCHITECTURE := x86_64
  AWS_INSTANCE_TYPE_DEFAULT := t3.xlarge
else ifeq ($(ARCH),aarch64)
  ARCHITECTURE := arm64
  AWS_INSTANCE_TYPE_DEFAULT := t4g.xlarge
else
  $(error Unsupported architecture: $(ARCH))
endif

# Use architecture-specific instance type if not specified
CLIENT_MACHINE_TYPE ?= $(AWS_INSTANCE_TYPE_DEFAULT)

init:
	packer init -upgrade .

build:
	if [ -n "$(GCP_PROJECT_ID)" ] && [ -n "$(GCP_ZONE)" ]; then \
		packer build -only=googlecompute.orch -var "gcp_project_id=$(GCP_PROJECT_ID)" -var "gcp_zone=$(GCP_ZONE)" -var "architecture=$(ARCHITECTURE)" .; \
	elif [ -n "$(AWS_REGION)" ]; then \
		PACKER_LOG=1 packer build -only=amazon-ebs.orch -var "aws_region=$(AWS_REGION)" -var "aws_instance_type=$(CLIENT_MACHINE_TYPE)" -var "architecture=$(ARCHITECTURE)" .; \
	else \
		echo "Error: Either GCP_PROJECT_ID and GCP_ZONE or AWS_REGION must be set"; \
		exit 1; \
	fi

format:
	packer fmt .
