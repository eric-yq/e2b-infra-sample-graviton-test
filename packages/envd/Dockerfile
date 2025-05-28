FROM golang:1.23 AS builder

WORKDIR /build/shared
COPY .shared/go.mod .shared/go.sum ./
RUN go mod download

COPY .shared/pkg pkg

WORKDIR /build/envd
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG COMMIT_SHA=""
# Fix any module issues first
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o bin/envd -ldflags "-X=main.commit=${COMMIT_SHA}"

FROM alpine:3.17

COPY --from=builder /build/envd/bin/envd .
CMD ["/envd"]