#!/bin/bash

set -euo pipefail

AWS_S3_BUCKET=$1
AWS_REGION=${2:-us-east-1}

chmod +x bin/template-manager

aws s3 cp \
  --region ${AWS_REGION} \
  --cache-control "no-cache, max-age=0" \
  bin/template-manager "s3://${AWS_S3_BUCKET}/template-manager"
