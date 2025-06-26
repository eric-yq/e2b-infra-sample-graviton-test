#!/bin/bash

# Change to the directory of the script
cd "$(dirname "$0")"

# Read parameters from /opt/config.properties
if [ -f /opt/config.properties ]; then
    # Use grep to extract variables
    AWSREGION=$(grep -E "^AWSREGION=" /opt/config.properties | cut -d'=' -f2)
    CFNDOMAIN=$(grep -E "^CFNDOMAIN=" /opt/config.properties | cut -d'=' -f2)
    
    echo "Found AWSREGION: $AWSREGION"
    echo "Found CFNDOMAIN: $CFNDOMAIN"
else
    echo "Error: Configuration file /opt/config.properties not found"
    exit 1
fi

# Read JSON configuration from ./../infra-iac/initdb/config.json
CONFIG_FILE="./../infra-iac/db/config.json"
if [ -f "$CONFIG_FILE" ]; then
    # Check if jq is installed
    if command -v jq &> /dev/null; then
        ACCESS_TOKEN=$(jq -r '.accessToken' "$CONFIG_FILE")
    else
        # Fallback to grep and sed if jq is not available
        ACCESS_TOKEN=$(grep -o '"accessToken": *"[^"]*"' "$CONFIG_FILE" | sed 's/"accessToken": *"\([^"]*\)"/\1/')
    fi
    
    echo "Found accessToken: $ACCESS_TOKEN"
else
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Make the POST request
echo "Making POST request to https://api.$CFNDOMAIN/templates with token $ACCESS_TOKEN"

RESPONSE=$(curl -s -X POST \
 "https://api.$CFNDOMAIN/templates" \
 -H "Authorization: $ACCESS_TOKEN" \
 -H 'Content-Type: application/json' \
 -d '{
 "dockerfile": "FROM ubuntu:22.04\nRUN apt-get update && apt-get install -y python3\nCMD [\"python3\", \"-m\", \"http.server\", \"8080\"]",
 "memoryMB": 4096,
 "cpuCount": 4,
 "startCommand": "echo $HOME"
 }')

# Extract buildID and templateID from response
if command -v jq &> /dev/null; then
    BUILD_ID=$(echo "$RESPONSE" | jq -r '.buildID')
    TEMPLATE_ID=$(echo "$RESPONSE" | jq -r '.templateID')
else
    # Fallback to grep and sed if jq is not available
    BUILD_ID=$(echo "$RESPONSE" | grep -o '"buildID": *"[^"]*"' | sed 's/"buildID": *"\([^"]*\)"/\1/')
    TEMPLATE_ID=$(echo "$RESPONSE" | grep -o '"templateID": *"[^"]*"' | sed 's/"templateID": *"\([^"]*\)"/\1/')
fi

echo "Response received:"
echo "$RESPONSE"
echo ""
echo "Extracted values:"
echo "buildID: $BUILD_ID"
echo "templateID: $TEMPLATE_ID"



# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to get AWS account ID"
    exit 1
fi
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Execute ECR login command
echo "Logging in to ECR..."
aws ecr get-login-password --region $AWSREGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWSREGION.amazonaws.com
if [ $? -ne 0 ]; then
    echo "Error: Failed to login to ECR"
    exit 1
fi

# Create ECR repository
echo "Creating ECR repository e2bdev/base/$TEMPLATE_ID..."
aws ecr create-repository --repository-name e2bdev/base/$TEMPLATE_ID --region $AWSREGION || true
if [ $? -ne 0 ]; then
    echo "Note: Repository may already exist or there was an error"
fi

# Pull the base Docker image
echo "Pulling e2bdev/base Docker image..."
docker pull e2bdev/base
if [ $? -ne 0 ]; then
    echo "Error: Failed to pull e2bdev/base Docker image"
    exit 1
fi

# Login to ECR again (to ensure credentials are fresh)
echo "Logging in to ECR again..."
aws ecr get-login-password --region $AWSREGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWSREGION.amazonaws.com
if [ $? -ne 0 ]; then
    echo "Error: Failed to login to ECR"
    exit 1
fi

# Tag the Docker image
ECR_REPOSITORY="$AWS_ACCOUNT_ID.dkr.ecr.$AWSREGION.amazonaws.com/e2bdev/base/$TEMPLATE_ID:$BUILD_ID"
echo "Tagging Docker image as $ECR_REPOSITORY..."
docker tag e2bdev/base:latest $ECR_REPOSITORY
if [ $? -ne 0 ]; then
    echo "Error: Failed to tag Docker image"
    exit 1
fi

# Push the Docker image to ECR
echo "Pushing Docker image to ECR..."
docker push $ECR_REPOSITORY
if [ $? -ne 0 ]; then
    echo "Error: Failed to push Docker image to ECR"
    exit 1
fi

echo "Docker image successfully pushed to ECR: $ECR_REPOSITORY"

# Notify the API that the build is complete
echo "Notifying API that the build is complete..."
BUILD_COMPLETE_RESPONSE=$(curl -s -X POST \
  "https://api.$CFNDOMAIN/templates/$TEMPLATE_ID/builds/$BUILD_ID" \
  -H "Authorization: $ACCESS_TOKEN" \
  -H 'Content-Type: application/json')

echo "Build completion notification response:"
echo "$BUILD_COMPLETE_RESPONSE"

# Poll build status every 10 seconds until it's no longer "building"
echo "Polling build status every 10 seconds until completion..."
while true; do
    FINAL_BUILD_STATUS_RESPONSE=$(curl -s \
      "https://api.$CFNDOMAIN/templates/$TEMPLATE_ID/builds/$BUILD_ID/status" \
      -H "Authorization: $ACCESS_TOKEN")
    
    echo "Current build status:"
    echo "$FINAL_BUILD_STATUS_RESPONSE"
    
    # Extract status value
    if command -v jq &> /dev/null; then
        STATUS=$(echo "$FINAL_BUILD_STATUS_RESPONSE" | jq -r '.status')
    else
        # Fallback to grep and sed if jq is not available
        STATUS=$(echo "$FINAL_BUILD_STATUS_RESPONSE" | grep -o '"status": *"[^"]*"' | sed 's/"status": *"\([^"]*\)"/\1/')
    fi
    
    if [ "$STATUS" != "building" ]; then
        echo "Build is no longer in 'building' state. Final status: $STATUS"
        echo "Done!"
        break
    fi
    
    echo "Build is still in progress. Checking again in 10 seconds..."
    sleep 10
done

echo "Script completed successfully!"
