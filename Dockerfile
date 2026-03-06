FROM debian:bookworm-slim

# базовые зависимости
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    xz-utils \
    netcat-traditional \
 && rm -rf /var/lib/apt/lists/*

# shadowsocks-rust
RUN curl -L -o /tmp/shadowsocks.tar.xz \
    https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.24.0/shadowsocks-v1.24.0.x86_64-unknown-linux-gnu.tar.xz \
 && tar -xJf /tmp/shadowsocks.tar.xz -C /usr/local/bin \
 && rm /tmp/shadowsocks.tar.xz

# v2ray-plugin
RUN curl -L -o /tmp/v2ray-plugin.tar.gz \
     https://github.com/shadowsocks/v2ray-plugin/releases/download/v1.3.2/v2ray-plugin-linux-amd64-v1.3.2.tar.gz \
  && tar -xzf /tmp/v2ray-plugin.tar.gz -C /usr/local/bin \
  && chmod +x /usr/local/bin/v2ray-plugin \
  && rm -rf /tmp/*

# конфиг
COPY shadowsocks-config.json /shadowsocks-config.json

# проверка (опционально, но полезно)
RUN which ssmanager \
  && which v2ray-plugin

CMD ["ssmanager", "-c", "/shadowsocks-config.json"]