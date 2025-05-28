IMAGE := e2b-orchestration/client-proxy

.PHONY: build
build:
	# Allow for passing commit sha directly for docker builds
	$(eval COMMIT_SHA ?= $(shell git rev-parse --short HEAD))
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o bin/client-proxy  .

.PHONY: build-and-upload
build-and-upload:
	@rm -rf .shared/
	@cp -r ../shared .shared/
	@sudo docker buildx install || true # sets up the buildx as default docker builder
	
	@if [ -n "$(GCP_PROJECT_ID)" ] && [ -n "$(GCP_REGION)" ]; then \
		sudo docker build --platform linux/amd64 --tag "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(IMAGE)" . && \
		sudo docker push "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(IMAGE)"; \
	elif [ -n "$(AWS_ACCOUNT_ID)" ]; then \
		aws ecr describe-repositories --repository-names $(IMAGE) --region $(AWS_REGION) || \
		aws ecr create-repository --repository-name $(IMAGE) --region $(AWS_REGION); \
		aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com; \
		sudo docker build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" . && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"; \
	else \
		echo "Either GCP_PROJECT_ID and GCP_REGION or AWS_ACCOUNT_ID must be set"; \
		exit 1; \
	fi
	
	@rm -rf .shared/

.PHONY: test
test:
	go test -v ./...



.PHONY: build-and-upload-aws
build-and-upload-aws:
	$(eval AWS_ACCOUNT_ID := $(shell grep "^account_id=" /opt/config.properties | cut -d= -f2))
	$(eval AWS_REGION := $(shell grep "^AWSREGION=" /opt/config.properties | cut -d= -f2))
	$(eval ARCHITECTURE := $(shell grep "^architecture=" /opt/config.properties | cut -d= -f2 || echo "x86_64"))
	
	@rm -rf .shared/
	@cp -r ../shared .shared/
	@docker buildx install || true # sets up the buildx as default docker builder
	# Create ECR repository if it doesn't exist
	@aws ecr describe-repositories --repository-names $(IMAGE) || aws ecr create-repository --repository-name $(IMAGE)
	# Login to ECR
	@aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	# Build and push the image for the specified architecture
	@echo "Building for architecture: $(ARCHITECTURE)"
	@if [ "$(ARCHITECTURE)" = "arm64" ]; then \
		echo "Building for ARM64 architecture"; \
		docker buildx build --platform linux/arm64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-arm64" . && \
		docker buildx build --platform linux/arm64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" . && \
		docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-arm64" && \
		docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"; \
	else \
		echo "Building for x86_64 architecture"; \
		docker buildx build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-amd64" . && \
		docker buildx build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" . && \
		docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-amd64" && \
		docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"; \
	fi
	@rm -rf .shared/
