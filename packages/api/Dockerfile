FROM golang:1.24-alpine3.21 AS builder

# Use Docker's automatic platform detection
ARG TARGETPLATFORM
RUN echo "Building for $TARGETPLATFORM"

# Extract architecture from TARGETPLATFORM (linux/amd64 or linux/arm64)
RUN case "$TARGETPLATFORM" in \
      "linux/amd64") echo "amd64" > /tmp/arch ;; \
      "linux/arm64") echo "arm64" > /tmp/arch ;; \
      *) echo "amd64" > /tmp/arch ;; \
    esac

RUN apk add --no-cache make

WORKDIR /build/shared

COPY .shared/go.mod .shared/go.sum ./
RUN go mod download

COPY .shared/pkg pkg

WORKDIR /build/api

COPY go.mod go.sum Makefile ./
RUN go mod download

COPY internal internal
COPY main.go main.go
RUN go mod tidy
RUN --mount=type=cache,target=/root/.cache/go-build CGO_ENABLED=0 GOOS=linux GOARCH=$(cat /tmp/arch) go build -v -o bin/api .

RUN chmod +x /build/api/bin/api

FROM alpine:3.21

COPY --from=builder /build/api/bin/api .

# Set Gin server to the production mode
ENV GIN_MODE=release
ENTRYPOINT [ "./api"]

