FROM golang:1.25-alpine AS panel-builder
WORKDIR /src

ENV GOPROXY=https://proxy.golang.org,direct

COPY go.mod go.sum ./
RUN go mod download

COPY . .
ARG TARGETOS=linux
ARG TARGETARCH
RUN CGO_ENABLED=0 GOOS=${TARGETOS} env ${TARGETARCH:+GOARCH=${TARGETARCH}} go build -o /out/paneld ./cmd/paneld

FROM alpine:latest
WORKDIR /app

RUN apk add --no-cache \
    ca-certificates \
    nftables \
    iptables \
    iproute2 \
    curl \
    wget \
    docker-cli \
    docker-cli-compose

COPY --from=panel-builder /out/paneld /app/paneld

ENV SERVER_ADDR=:6365
EXPOSE 6365
CMD ["./paneld"]
