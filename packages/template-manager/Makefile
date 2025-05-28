#client := gcloud compute instances list --format='csv(name)' --project $(GCP_PROJECT_ID) | grep "client"

.PHONY: init
init:
	brew install protobuf
	go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2

.PHONY: generate
generate:
	# You need to install protobuf (brew install protobuf) and following go packages: protoc-gen-go, protoc-gen-go-grpc
	# https://grpc.io/docs/languages/go/quickstart/
	@echo "Generating..."
	@protoc --go_out=../shared/pkg/grpc/template-manager/ --go_opt=paths=source_relative --go-grpc_out=../shared/pkg/grpc/template-manager/ --go-grpc_opt=paths=source_relative template-manager.proto
	@echo "Done"

.PHONY: build
build:
	# Allow for passing commit sha directly for docker builds
	$(eval COMMIT_SHA ?= $(shell git rev-parse --short HEAD))
	$(eval ARCHITECTURE := $(shell grep "^architecture=" /opt/config.properties | cut -d= -f2 || echo "x86_64"))
	go mod tidy
	@if [ "$(ARCHITECTURE)" = "arm64" ]; then \
		echo "Building for ARM64 architecture"; \
		CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o bin/template-manager -ldflags "-X=main.commitSHA=$(COMMIT_SHA)" .; \
	else \
		echo "Building for x86_64 architecture"; \
		CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/template-manager -ldflags "-X=main.commitSHA=$(COMMIT_SHA)" .; \
	fi

.PHONY: build-debug
build-debug:
	CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -race -gcflags=all="-N -l" -o bin/template-manager .

.PHONY: upload-gcp
upload-gcp:
	echo "GCP upload has been deprecated. Please use upload-aws or upload target instead."

.PHONY: upload-aws
upload-aws:
	# Create repository if it doesn't exist
	$(eval IMAGE := e2b-orchestration/template-manager)
	aws ecr describe-repositories --repository-names $(IMAGE) --region $(AWS_REGION) || \
	aws ecr create-repository --repository-name $(IMAGE) --region $(AWS_REGION)
	# Login to ECR
	aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	# Build and push Docker image
	$(eval COMMIT_SHA := $(shell git rev-parse --short HEAD))
	@cp -r ../shared .shared/
	sudo docker buildx install || true # sets up the buildx as default docker builder
	sudo docker build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" --build-arg COMMIT_SHA="$(COMMIT_SHA)" .
	sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"
	@rm -rf .shared/

.PHONY: upload
upload:
	@if [ -n "$(AWS_ACCOUNT_ID)" ] && [ -n "$(AWS_REGION)" ]; then \
		$(MAKE) upload-aws; \
	else \
		echo "AWS_ACCOUNT_ID and AWS_REGION must be set"; \
		exit 1; \
	fi

.PHONY: build-and-upload
build-and-upload:
	@rm -rf .shared/
	@cp -r ../shared .shared/
	$(MAKE) build
	@rm -rf .shared/
	$(eval E2B_EXECUTE_FILE_BUCKET := $(shell grep CFNSOFTWAREBUCKET /opt/config.properties | cut -d'=' -f2))
	@echo "Using bucket: $(E2B_EXECUTE_FILE_BUCKET)"
	aws s3 cp bin/template-manager s3://$(E2B_EXECUTE_FILE_BUCKET)/template-manager


.PHONY: test
test:
	go test -v ./...

.PHONY: test-build
test-build:
	sudo TEMPLATE_BUCKET_NAME=$(TEMPLATE_BUCKET_NAME) AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) AWS_ECR_REPOSITORY=$(AWS_ECR_REPOSITORY) AWS_REGION=$(AWS_REGION) go run -race -gcflags=all="-N -l" main.go -test build -template d6a5c9wp4ccm7uqi4jzi -build 8e00bbdf-7f55-4025-9964-eede203c6ee5

.PHONY: test-delete
test-delete:
	sudo TEMPLATE_BUCKET_NAME=$(TEMPLATE_BUCKET_NAME) AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) AWS_ECR_REPOSITORY=$(AWS_ECR_REPOSITORY) AWS_REGION=$(AWS_REGION) go run -race -gcflags=all="-N -l" main.go -test delete -env 0v0c9frk1etrhpxr5ljw

.PHONY: migrate
migrate:
	./upload-envs.sh /mnt/disks/fc-envs/v1 $(TEMPLATE_BUCKET_NAME)
