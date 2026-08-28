FROM golang:bookworm AS awg-go-builder

ARG AWG_GO_TAG=v3.1.20260814
ARG AWG_GO_COMMIT=1b86b2ae0e493e7ea93f8c1a0f0cb6735b1551f1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git make ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
      --branch "${AWG_GO_TAG}" \
      --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-go.git \
      /src/amneziawg-go \
    && test "$(git -C /src/amneziawg-go rev-parse HEAD)" = "${AWG_GO_COMMIT}"

WORKDIR /src/amneziawg-go

RUN make \
    && install -m 0755 amneziawg-go /usr/local/bin/amneziawg-go


FROM debian:bookworm AS awg-tools-builder

ARG AWG_TOOLS_TAG=v3.1.20260812
ARG AWG_TOOLS_COMMIT=ee0f0a9aa34ff0a0da4b3433b9512781cfe02843

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git make gcc libc6-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
      --branch "${AWG_TOOLS_TAG}" \
      --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-tools.git \
      /src/amneziawg-tools \
    && test "$(git -C /src/amneziawg-tools rev-parse HEAD)" = "${AWG_TOOLS_COMMIT}"

WORKDIR /src/amneziawg-tools/src

RUN make \
    && make install \
       PREFIX=/usr/local \
       WITH_BASHCOMPLETION=no \
       WITH_SYSTEMDUNITS=no


FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash ca-certificates iproute2 iptables openresolv procps curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=awg-go-builder \
  /usr/local/bin/amneziawg-go \
  /usr/local/bin/amneziawg-go

COPY --from=awg-tools-builder \
  /usr/local/bin/awg \
  /usr/local/bin/awg

COPY --from=awg-tools-builder \
  /usr/local/bin/awg-quick \
  /usr/local/bin/awg-quick

COPY start.sh /start.sh

RUN chmod 0755 /start.sh \
    && mkdir -p /var/run/amneziawg \
    && bash -n /usr/local/bin/awg-quick

ENTRYPOINT ["/start.sh"]
