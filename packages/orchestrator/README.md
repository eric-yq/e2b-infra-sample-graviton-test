# Orchestrator

## Storage Providers

The orchestrator supports both Google Cloud Storage (GCS) and AWS S3 as storage backends.

### Storage Configuration

#### AWS S3 Configuration

To use AWS S3 as your storage provider:

1. Set environment variables:
   - `AWS_ENABLED=true` - Enables AWS S3 as the storage provider
   - `TEMPLATE_AWS_BUCKET_NAME` - Name of your S3 bucket for template storage
   - `AWS_REGION` - AWS region where your S3 bucket is located (defaults to us-east-1)
   - `AWS_ACCESS_KEY_ID` - Your AWS access key
   - `AWS_SECRET_ACCESS_KEY` - Your AWS secret key

2. Infrastructure preparation:
   - Create an S3 bucket in your AWS account
   - Ensure the IAM user associated with your credentials has appropriate permissions:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "s3:GetObject",
             "s3:PutObject",
             "s3:ListBucket",
             "s3:DeleteObject"
           ],
           "Resource": [
             "arn:aws:s3:::YOUR_BUCKET_NAME",
             "arn:aws:s3:::YOUR_BUCKET_NAME/*"
           ]
         }
       ]
     }
     ```

3. To build and upload the orchestrator to AWS:
   ```
   make build-and-upload
   ```

#### Google Cloud Storage Configuration (default)

To use Google Cloud Storage:
- Ensure `AWS_ENABLED` is not set or set to any value other than "true"
- Set `TEMPLATE_BUCKET_NAME` to your GCS bucket name
- Configure standard GCP credentials

## Development

### Building for AWS

```bash
# Build the Docker image and push to AWS ECR
make upload-aws

# Build local binary
make build-local
```

### Testing AWS S3 Integration

To test the AWS S3 integration:

1. Set the required environment variables
2. Run the mock sandbox with AWS configuration:
   ```bash
   AWS_ENABLED=true \
   TEMPLATE_AWS_BUCKET_NAME=your-s3-bucket \
   AWS_REGION=us-east-1 \
   AWS_ACCESS_KEY_ID=your-access-key \
   AWS_SECRET_ACCESS_KEY=your-secret-key \
   sudo go run cmd/mock-sandbox/mock.go -template your-template-id -build your-build-id -alive 1 -count 1
   ```