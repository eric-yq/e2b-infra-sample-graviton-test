ENV := $(shell cat ../../.last_used_env || echo "not-set")
-include ../../.env.${ENV}

BUILD := $(shell git rev-parse --short HEAD)
LDFLAGS=-ldflags "-X=main.commit=$(BUILD)"

.PHONY: init
init:
	brew install protobuf
	go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.28
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.2

upload-gcp:
	./upload.sh $(GCP_PROJECT_ID)

upload-aws:
	# Create repository if it doesn't exist
	$(eval IMAGE := e2b-orchestration/envd)
	aws ecr describe-repositories --repository-names $(IMAGE) --region $(AWS_REGION) || \
	aws ecr create-repository --repository-name $(IMAGE) --region $(AWS_REGION)
	# Login to ECR
	aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	# Build and push Docker image
	$(eval COMMIT_SHA := $(shell git rev-parse --short HEAD))
	sudo docker buildx install || true # sets up the buildx as default docker builder
	sudo docker build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" --build-arg COMMIT_SHA="$(COMMIT_SHA)" .
	sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"

upload:
	@if [ -n "$(GCP_PROJECT_ID)" ] && [ -n "$(GCP_REGION)" ]; then \
		$(MAKE) upload-gcp; \
	elif [ -n "$(AWS_ACCOUNT_ID)" ] && [ -n "$(AWS_REGION)" ]; then \
		$(MAKE) upload-aws; \
	else \
		echo "Either GCP_PROJECT_ID and GCP_REGION or AWS_ACCOUNT_ID and AWS_REGION must be set"; \
		exit 1; \
	fi

build:
	# Use Docker for building to ensure we have the Go environment
	@mkdir -p bin
	$(eval ARCHITECTURE := $(shell grep "^architecture=" /opt/config.properties | cut -d= -f2 || echo "x86_64"))
	@if [ "$(ARCHITECTURE)" = "arm64" ]; then \
		echo "Building for ARM64 architecture"; \
	    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -a -o bin/envd ${LDFLAGS} \
	else \
		echo "Building for x86_64 architecture"; \
	    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o bin/envd ${LDFLAGS} \
	fi

	# sudo docker run --rm -v $(PWD):/app -w /app golang:1.23 bash -c "CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o bin/envd ${LDFLAGS}"

build-debug:
	CGO_ENABLED=1 go build -race -gcflags=all="-N -l" -o bin/debug/envd ${LDFLAGS}

start-docker:
	DOCKER_BUILDKIT=1 docker build -t envd-debug . -f debug.Dockerfile
	docker run \
	--name envd \
	-p 49983:49983 \
	-p 2345:2345 \
	-p 9999:9999 \
	-p 8000:8000 \
	-p 8001:8001 \
	--rm \
	-i envd-debug \
	/usr/bin/envd -debug

build-and-upload:
	@rm -rf .shared/
	@cp -r ../shared .shared/ || true
	# We'll use docker to build and push directly
	$(eval COMMIT_SHA := $(shell git rev-parse --short HEAD))
	@if [ -n "$(GCP_PROJECT_ID)" ] && [ -n "$(GCP_REGION)" ]; then \
		sudo docker build --platform linux/amd64 --tag "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/e2b-orchestration/envd:latest" --build-arg COMMIT_SHA="$(COMMIT_SHA)" . && \
		sudo docker push "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/e2b-orchestration/envd:latest"; \
	elif [ -n "$(AWS_ACCOUNT_ID)" ]; then \
		aws ecr describe-repositories --repository-names e2b-orchestration/envd --region us-east-1 || \
		aws ecr create-repository --repository-name e2b-orchestration/envd --region us-east-1; \
		aws ecr get-login-password --region us-east-1 | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.us-east-1.amazonaws.com; \
		sudo docker buildx install || true; \
		sudo docker build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.us-east-1.amazonaws.com/e2b-orchestration/envd:latest" --build-arg COMMIT_SHA="$(COMMIT_SHA)" . && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.us-east-1.amazonaws.com/e2b-orchestration/envd:latest"; \
	else \
		echo "Either GCP_PROJECT_ID and GCP_REGION or AWS_ACCOUNT_ID must be set"; \
		exit 1; \
	fi
	@rm -rf .shared/

.PHONY: generate
generate:
	go generate ./...
	@if ! command -v buf >/dev/null 2>&1; then \
		echo "buf is not installed. Do you want to install it?  (Y/n): "; \
		read choice; \
		if [ "$$choice" = "Y" ]; then \
			go install github.com/bufbuild/buf/cmd/buf@latest && \
			go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
			go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest; \
		else \
			exit 1; \
		fi; \
	fi
	cd spec && buf generate

.PHONY: init-generate
init-generate:
	go install github.com/bufbuild/buf/cmd/buf@latest
	go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
	go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	go install connectrpc.com/connect/cmd/protoc-gen-connect-go@latest

.PHONY: test
test:
	go test -v ./...
