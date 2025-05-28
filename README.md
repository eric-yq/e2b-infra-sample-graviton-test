# E2B on AWS Deployment Guide

## Introduction

### Purpose

E2B on AWS provides a secure, scalable, and customizable environment for running AI agent sandboxes in your own AWS account. This project addresses the growing need for organizations to maintain control over their AI infrastructure while leveraging the power of E2B's sandbox technology for AI agent development, testing, and deployment.

This project is built based on version [c746fd93d5f1260315c893dbd5d7290c0a41e52a](https://github.com/e2b-dev/infra/commit/c746fd93d5f1260315c893dbd5d7290c0a41e52a) (Mar 2), with newer versions still undergoing modifications. This E2B deployment can be used for testing purposes. If you encounter any issues, please contact the relevant team members or submit a PR directly. We would like to express our special thanks to all contributors involved in the project transformation.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
  - [1. Setup E2B Landing Zone](#1-setup-e2b-landing-zone)
  - [2. Setup E2B Infrastructure](#2-setup-e2b-infrastructure)
  - [3. Deploy E2B Applications](#3-deploy-e2b-applications)
  - [4. Setup E2B Database](#4-setup-e2b-database)
  - [5. Configure E2B Monitoring](#5-configure-e2b-monitoring)
  - [6. Test by E2B SDK](#6-test-by-e2b-sdk)
- [Using E2B CLI](#using-e2b-cli)
- [E2B SDK Cookbook](#e2b-sdk-cookbook)
- [Troubleshooting](#troubleshooting)
- [Appendix](#appendix)
- [Architecture Diagram](#architecture-diagram)

## Prerequisites

- An AWS account with appropriate permissions
- A domain name that you own(Cloudflare is recommended)

- Recommended for monitoring and logging
  - Grafana Account & Stack (see Step 15 for detailed notes)
  - Posthog Account (optional)

> **Production Security Checklist:** Before deploying to production, verify these critical security and reliability settings are enabled:
> - `DB_INSTANCE_BACKUP_ENABLED`
> - `RDS_AUTOMATIC_MINOR_VERSION_UPGRADE_ENABLED`
> - `RDS_ENHANCED_MONITORING_ENABLED`
> - `RDS_INSTANCE_LOGGING_ENABLED`
> - `RDS_MULTI_AZ_SUPPORT`
> - `S3_BUCKET_LOGGING_ENABLED`
> - `EC2 Metadata service configuration`

## Deployment Steps

### 1. Setup E2B Landing Zone

1. **Deploy CloudFormation Stack**
   - Open AWS CloudFormation console and create a new stack
   - Upload the `e2b-setup-env.yml` template file for Intel/AMD instances, or `e2b-setup-env_arm64.yml` for Graviton-based instances.
   - Configure the following parameters:
     - **Stack Name**: Enter a name for the stack, **must be lowercase**(e.g., `e2b-infra`)
     - **Domain Configuration**: Enter a domain you own (e.g., `example.com`)
     - **EC2 Key Pair**: Select an existing key pair for SSH access
     - **AllowRemoteSSHIPs**: Adjust IP range for SSH access (default restricts to private networks for security)
     - **Database Settings**: Configure RDS parameters following password requirements(must be 8-30 characters with letters and numbers)
   - Complete all required fields and launch the stack

2. **Validate Domain Certificate**
   - Navigate to Amazon Certificate Manager (ACM)
   - Find your domain certificate and note the required CNAME record
   - Add the CNAME record to your domain's DNS settings(Cloudflare DNS settings)
   - Wait for domain validation (typically 5-10 minutes)

3. **Monitor Stack Creation**
   - Return to CloudFormation console
   - Wait for stack creation to complete successfully

### 2. Setup E2B Infrastructure

1. **Connect to Deployment Machine**
   - Use SSH with your EC2 key pair: `ssh -i your-key.pem ubuntur@<instance-ip>`
   - Or use AWS Session Manager from the EC2 console for browser-based access

2. Execute the following commands:
```bash 
# Switch to root user for administrative privileges required for infrastructure setup
sudo su root

# Initialize the environment by setting up AWS metadata, CloudFormation outputs,
# and creating the configuration file at /opt/config.properties
bash infra-iac/init.sh

# Build custom AMI images using Packer for the E2B infrastructure
# This creates optimized machine images with pre-installed dependencies
# This may take a while, please be patient
bash infra-iac/packer/packer.sh $(cloud-init query region)$ arm64

# Deploy the complete E2B infrastructure using Terraform
# This provisions AWS resources including VPC, EC2 instances, RDS, ALB, etc.
# Wait until the terraform deployment completes
bash infra-iac/terraform/start.sh -a arm64
```

3. Setup Database:
```bash
bash infra-iac/db/init-db.sh

# Save the following token information for later use:
# User: xxx
# Team ID: <ID>
# Access Token: <e2b_token>
# Team API Key: <e2b_API>
```
4. Configure E2B DNS records(in Cloudflare):
   - **Setup Wildcard DNS**: Add a CNAME record for `*` (wildcard) pointing to the DNS name of the automatically created Application Load Balancer (ALB). This enables all E2B subdomains to route through the load balancer.
   - **Access Nomad Dashboard**: Navigate to `https://nomad.<your-domain>` in your browser and authenticate using the retrieved token to monitor and manage the Nomad cluster workloads.
   - **Retrieve Nomad Access Token**: Execute `more /opt/config.properties | grep NOMAD` to extract the Nomad cluster management token from the configuration file.

### 3. Deploy Applications

#### Application Image Configuration

**Custom Image Building (Recommended for Production)**
By default, E2B uses images from the public registry. For production deployments, it's highly recommended to build and use your own custom images for enhanced security and control:
   - **Build Custom Images**: Execute `bash packages/build.sh` to build custom E2B images and push them to your private ECR registry
   - **Configure Auto Scaling**: Set the desired capacity for client instance Auto Scaling Groups to 1 or 2 (default is 0 for cost optimization during initial setup)

#### Deploy Nomad Applications

```bash
# Load Nomad environment variables and configuration settings
source nomad/nomad.sh

# Prepare the Nomad cluster and configure job templates
bash nomad/prepare.sh

# Deploy all E2B applications to the Nomad cluster
bash nomad/deploy.sh

# There are 10 applications in total
```

### 5. Configure Grafana Monitoring（Optional）

1. Login to https://grafana.com/ (register if needed)
2. Access your settings page at https://grafana.com/orgs/<username>
3. In your Stack, find 'Manage your stack' page
4. Find 'OpenTelemetry' and click 'Configure'
5. Note the following values from the dashboard:
   ```
   Endpoint for sending OTLP signals: xxxx
   Instance ID: xxxxxxx
   Password / API Token: xxxxx
   ```

6. Export NOMAD environment variables:（Optional）
```bash
cat << EOF >> /opt/config.properties

# Grafana configuration
grafana_otel_collector_token=xxx
grafana_otlp_url=xxx
grafana_username=xxx
EOF

echo "Appended Grafana configuration to /opt/config.properties"
```

7. Deploy OpenTelemetry collector:（Optional）
```bash
bash nomad/deploy.sh otel-collector
```

8. Open Grafana Cloud Dashboard to view metrics, traces, and logs（Optional）


### 6. Test Sandbox SDK

Test creation template（The script includes the following steps 1-6）
```bash
bash nomad/create_template.sh
```

1. In EC2 Auto Scaling Group, set the desired capacity of **<e2b>client-asg** server to 1
2. Create a sandbox template:

```bash
curl -X POST \
 https://api.e2b.example.com/templates \
 -H 'Authorization: <e2b_token>' \
 -H 'Content-Type: application/json' \
 -d '{
 "dockerfile": "FROM ubuntu:22.04\nRUN apt-get update && apt-get install -y python3\nCMD [\"python3\", \"-m\", \"http.server\", \"8080\"]",
 "memoryMB": 4096,
 "cpuCount": 4,
 "startCommand": "echo $HOME"
 }'
```

3. Save the response (note the buildID and templateID):
```json
{
  "aliases": null,
  "buildCount": 0,
  "buildID": "<buildID>",
  "cpuCount": 0,
  "createdAt": "0001-01-01T00:00:00Z",
  "createdBy": null,
  "lastSpawnedAt": "0001-01-01T00:00:00Z",
  "memoryMB": 0,
  "public": false,
  "spawnCount": 0,
  "templateID": "<templateID>",
  "updatedAt": "0001-01-01T00:00:00Z"
}
```

4. Create ECR registry:
```bash
aws ecr get-login-password --region <AWS_REGION> | docker login --username AWS --password-stdin <AWS_acccount_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com
aws ecr create-repository --repository-name e2bdev/base/<templateID> --region <AWS_REGION> || true
```

5. Pull and push the image:
```bash
docker pull e2bdev/base

aws ecr get-login-password --region <AWS_REGION> | docker login --username AWS --password-stdin <AWS_acccount_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com
docker tag e2bdev/base:latest <AWS_acccount_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/e2bdev/base/<templateID>:<buildID>
docker push <AWS_acccount_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/e2bdev/base/<templateID>:<buildID>
```

6. Build RootFS:
```bash
curl -X POST \
  https://api.<e2bdomain>/templates/<templateID>/builds/<buildID> \
  -H 'Authorization: <e2b_token>' \
  -H 'Content-Type: application/json' 
```

7. Check API and Template Manager logs in Nomad Console for any issues
8. Create a sandbox(Get the value of e2b_API to execute commands---  more ../infra-iac/db/config.json):
```bash
curl -X POST \
 https://api.<e2bdomain>/sandboxes \
 -H "X-API-Key: <e2b_API>" \
 -H 'Content-Type: application/json' \
 -d '{
        "templateID": "<template_ID>",
        "timeout": 3600,
        "autoPause": true,
        "envVars": {
        "EXAMPLE_VAR": "example_value"
        },
        "metadata": {
            "purpose": "test"
        }
 }'
```

## Using E2B CLI

```bash
# Installation Guide: https://e2b.dev/docs/cli
# For macOS
brew install e2b

# Export environment variables
export E2B_API_KEY=xxx
export E2B_ACCESS_TOKEN=xxx
export E2B_DOMAIN="<e2bdomain>"

# Common E2B CLI commands
# List all sandboxes
e2b sandbox list
 
# Connect to a sandbox
e2b sandbox connect <sandbox-id>
 
# Kill a sandbox
e2b sandbox kill <sandbox-id>
e2b sandbox kill --all
```

## E2B SDK Cookbook

```bash
git clone https://github.com/e2b-dev/e2b-cookbook.git
cd e2b-cookbook/examples/hello-world-python
poetry install

# Edit .env file
vim .env
# Change E2B_API_KEY value

poetry run start
```

## Troubleshooting

1. **No nodes were eligible for evaluation error when deploying applications**
   - Check node status and constraints

2. **Driver Failure: Failed to pull from ECR**
   - Error: `Failed to pull xxx.dkr.ecr.us-west-2.amazonaws.com/e2b-orchestration/api:latest: API error (404): pull access denied for xxx.dkr.ecr.us-west-2.amazonaws.com/e2b-orchestration/api, repository does not exist or may require 'docker login': denied: Your authorization token has expired. Reauthenticate and try again.`
   - Solution: Execute `aws ecr get-login-password --region us-east-1` to get a new ECR token and update the HCL file

3. For other unresolved issues, contact support

## Appendix


## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.

#### Application Image Configuration