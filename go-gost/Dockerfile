FROM golang:1.25-alpine AS builder

WORKDIR /src
ENV GOPROXY=https://proxy.golang.org,direct

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} env ${TARGETARCH:+GOARCH=${TARGETARCH}} \
    go build -ldflags="-s -w" -o /out/flvx-agent .

FROM alpine:latest

WORKDIR /app

RUN apk add --no-cache \
    ca-certificates \
    nftables \
    iptables \
    iproute2 \
    curl \
    wget \
    docker-cli

COPY --from=builder /out/flvx-agent /app/flvx-agent

ENTRYPOINT []
CMD ["./flvx-agent"]
