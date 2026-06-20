FROM golang:bookworm AS awg-go-builder
RUN apt-get update && apt-get install -y --no-install-recommends git make ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-go.git /src/amneziawg-go
WORKDIR /src/amneziawg-go
RUN make && install -m 0755 amneziawg-go /usr/local/bin/amneziawg-go

FROM debian:bookworm AS awg-tools-builder
RUN apt-get update && apt-get install -y --no-install-recommends git make gcc libc6-dev ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/amnezia-vpn/amneziawg-tools.git /src/amneziawg-tools
WORKDIR /src/amneziawg-tools/src
RUN make && make install PREFIX=/usr/local WITH_BASHCOMPLETION=no WITH_SYSTEMDUNITS=no

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates iproute2 iptables openresolv procps curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=awg-go-builder /usr/local/bin/amneziawg-go /usr/local/bin/amneziawg-go
COPY --from=awg-tools-builder /usr/local/bin/awg /usr/local/bin/awg
COPY --from=awg-tools-builder /usr/local/bin/awg-quick /usr/local/bin/awg-quick
COPY start.sh /start.sh
RUN chmod +x /start.sh && mkdir -p /var/run/amneziawg
ENTRYPOINT ["/start.sh"]
