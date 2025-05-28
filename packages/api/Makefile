IMAGE := e2b-orchestration/api


openapi := ../../spec/openapi.yml
codegen := go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@latest

.PHONY: generate
generate:
	$(codegen) -old-config-style -generate gin --package api $(openapi) > internal/api/api.gen.go
	$(codegen) -old-config-style -generate types --package api $(openapi) > internal/api/types.gen.go
	$(codegen) -old-config-style -generate spec --package api $(openapi) > internal/api/spec.gen.go


.PHONY: build
build:
	# Allow for passing commit sha directly for docker builds
	$(eval COMMIT_SHA ?= $(shell git rev-parse --short HEAD))
	CGO_ENABLED=0 go build -v -o bin/api -ldflags "-X=main.commitSHA=$(COMMIT_SHA)" .

.PHONY: build-debug
build-debug:
	CGO_ENABLED=1 go build -race -gcflags=all="-N -l" -o bin/api .

.PHONY: run
run:
	make build-debug
	POSTGRES_CONNECTION_STRING=$(POSTGRES_CONNECTION_STRING) \
	GOTRACEBACK=crash \
	GODEBUG=madvdontneed=1 \
	TEMPLATE_BUCKET_NAME=$(TEMPLATE_BUCKET_NAME) \
	ENVIRONMENT=$(ENVIRONMENT) \
	./bin/api --port 3000


# You run the parametrized command like this:
# make metric=heap interval=90 profiler
.PHONY: profiler
profiler:
	go tool pprof -http :9991 http://localhost:3000/debug/pprof/$(metric)?seconds=$(interval)\&timeout=120

.PHONY: build-and-upload
build-and-upload:
	$(eval COMMIT_SHA := $(shell git rev-parse --short HEAD))
	@rm -rf .shared/
	@cp -r ../shared .shared/
	@sudo docker buildx install || true # sets up the buildx as default docker builder
	
	@if [ -n "$(GCP_PROJECT_ID)" ] && [ -n "$(GCP_REGION)" ]; then \
		sudo docker build --platform linux/amd64 --tag "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(IMAGE)" --build-arg COMMIT_SHA="$(COMMIT_SHA)" . && \
		sudo docker push "$(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(IMAGE)"; \
	elif [ -n "$(AWS_ACCOUNT_ID)" ]; then \
		aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com; \
		sudo docker build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" --build-arg COMMIT_SHA="$(COMMIT_SHA)" . && \
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
	@sudo docker buildx install || true # sets up the buildx as default docker builder
	# Create ECR repository if it doesn't exist
	@aws ecr describe-repositories --repository-names $(IMAGE) || aws ecr create-repository --repository-name $(IMAGE)
	# Login to ECR
	@aws ecr get-login-password --region $(AWS_REGION) | sudo docker login --username AWS --password-stdin $(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com
	# Build and push the image for both architectures
	@echo "Building for architecture: $(ARCHITECTURE)"
	@if [ "$(ARCHITECTURE)" = "arm64" ]; then \
		echo "Building for ARM64 architecture"; \
		sudo docker buildx build --platform linux/arm64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-arm64" . && \
		sudo docker buildx build --platform linux/arm64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" . && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-arm64" && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"; \
	else \
		echo "Building for x86_64 architecture"; \
		sudo docker buildx build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-amd64" . && \
		sudo docker buildx build --platform linux/amd64 --tag "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest" . && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest-amd64" && \
		sudo docker push "$(AWS_ACCOUNT_ID).dkr.ecr.$(AWS_REGION).amazonaws.com/$(IMAGE):latest"; \
	fi
	@rm -rf .shared/
