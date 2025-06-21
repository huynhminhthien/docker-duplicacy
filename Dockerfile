FROM ghcr.io/linuxserver/baseimage-alpine:3.21

ARG DUPLICACY_VERSION=2.7.2

ENV BACKUP_SCHEDULE='@hourly'
ENV PRUNE_SCHEDULE='@daily'
ENV COPY_SCHEDULE=''
ENV HC_PING_ID=''
ENV DUPLICACY_BACKUP_OPTIONS=''
ENV DUPLICACY_PRUNE_OPTIONS='-keep 60:360 -keep 30:180 -keep 7:30 -keep 2:14 -keep 1:7'
ENV DUPLICACY_COPY_OPTIONS=''

RUN apk --no-cache add ca-certificates curl && update-ca-certificates

RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        ARCH_SUFFIX="x64"; \
    elif [ "$ARCH" = "i386" ]; then \
        ARCH_SUFFIX="i386"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        ARCH_SUFFIX="arm64"; \
    elif [ "$ARCH" = "armv7l" ]; then \
        ARCH_SUFFIX="arm"; \
    else \
        echo "Unsupported architecture: $ARCH"; exit 1; \
    fi && \
    wget https://github.com/gilbertchen/duplicacy/releases/download/v${DUPLICACY_VERSION}/duplicacy_linux_${ARCH_SUFFIX}_${DUPLICACY_VERSION} -O /usr/bin/duplicacy && \
    chmod +x /usr/bin/duplicacy

COPY root /

WORKDIR /data
VOLUME ["/data"]
