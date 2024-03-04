FROM alpine:3.19 as builder

ARG PYTHONUNBUFFERED=1

RUN \
    apk add --update --no-cache \
        g++ \
        linux-headers \
        make \
        python3 \
        python3-dev

RUN \
    python3 -m venv /usr/local/protonvpn-natpmp && \
    /usr/local/protonvpn-natpmp/bin/pip3 install -U pip && \
    /usr/local/protonvpn-natpmp/bin/pip3 install NAT-PMP

FROM alpine:3.19

LABEL org.opencontainers.image.source="https://github.com/joeroback/protonvpn-qbittorrent"

RUN \
    apk add --update --no-cache \
        ca-certificates \
        curl \
        python3

COPY --from=builder /usr/local/protonvpn-natpmp /usr/local/protonvpn-natpmp

COPY entrypoint.py /entrypoint.py

ENTRYPOINT [ "/entrypoint.py" ]
