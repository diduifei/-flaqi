FROM golang:1.25-alpine AS panel-builder
WORKDIR /src

ENV GOPROXY=https://proxy.golang.org,direct

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} env ${TARGETARCH:+GOARCH=${TARGETARCH}} go build -o /out/paneld ./cmd/paneld

FROM golang:1.25-alpine AS agent-builder
WORKDIR /src

ENV GOPROXY=https://proxy.golang.org,direct

RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/diduifei/-flaqi.git /src/flvx
WORKDIR /src/flvx/go-gost
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} env ${TARGETARCH:+GOARCH=${TARGETARCH}} go build -ldflags="-s -w" -o /out/flvx-agent .

FROM alpine:latest
WORKDIR /app

RUN apk add --no-cache \
    ca-certificates \
    nftables \
    iptables \
    iproute2 \
    curl \
    wget \
    iptables-nft \
    docker-cli \
    docker-cli-compose

COPY --from=panel-builder /out/paneld /app/paneld
COPY --from=agent-builder /out/flvx-agent /app/flvx-agent

ENV SERVER_ADDR=:6365
EXPOSE 6365
CMD ["./paneld"]
