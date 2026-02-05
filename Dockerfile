# Dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get upgrade && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils netcat-traditional  \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt install netcat

RUN curl -L -o /tmp/shadowsocks.tar.xz \
    https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.24.0/shadowsocks-v1.24.0.x86_64-unknown-linux-gnu.tar.xz \
    && tar -xJf /tmp/shadowsocks.tar.xz -C /usr/local/bin \
    && rm /tmp/shadowsocks.tar.xz

COPY shadowsocks-config.json ./shadowsocks-config.json

CMD ["ssmanager", "-c", "shadowsocks-config.json"]