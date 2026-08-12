FROM golang:bookworm AS awg-go-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git make ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
      --branch v0.2.19 \
      --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-go.git \
      /src/amneziawg-go \
    && test "$(git -C /src/amneziawg-go rev-parse --short=7 HEAD)" = "1cc9427"

WORKDIR /src/amneziawg-go

RUN make \
    && install -m 0755 amneziawg-go /usr/local/bin/amneziawg-go


FROM debian:bookworm AS awg-tools-builder

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git make gcc libc6-dev ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN git clone \
      --branch v1.0.20260618-2 \
      --depth 1 \
      https://github.com/amnezia-vpn/amneziawg-tools.git \
      /src/amneziawg-tools \
    && test "$(git -C /src/amneziawg-tools rev-parse --short=7 HEAD)" = "61e7417"

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

# AWG 2.0 must use amneziawg-go even when an AWG 3.0 kernel module
# is available on the Docker host.
RUN sed -i '/^add_if() {$/,/^}$/c\
add_if() {\
    cmd "${WG_QUICK_USERSPACE_IMPLEMENTATION:-amneziawg-go}" "$INTERFACE"\
}' /usr/local/bin/awg-quick \
    && grep -A3 '^add_if()' /usr/local/bin/awg-quick

COPY start.sh /start.sh

RUN chmod 0755 /start.sh \
    && mkdir -p /var/run/amneziawg

ENTRYPOINT ["/start.sh"]

# Repair forced userspace syntax and fail the build if awg-quick is invalid.
RUN sed -i '/^add_if()/ s/INTERFACE"}/INTERFACE"; }/' /usr/local/bin/awg-quick \
    && bash -n /usr/local/bin/awg-quick \
    && grep -A1 '^add_if()' /usr/local/bin/awg-quick
