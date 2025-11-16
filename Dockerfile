FROM alpine:3.22

ENV LOCAL_IPV4_SUBNETS="192.168.0.0/16"
ENV TZ="UTC"
ENV WEBUI_HOST="http://localhost:8080"
ENV WIREGUARD_INTERFACE="wg0"

RUN apk add --update --no-cache \
        bash ca-certificates curl iproute2 iptables ip6tables jq libnatpmp tzdata wireguard-tools \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone

COPY entrypoint.sh /entrypoint.sh

HEALTHCHECK --start-period=15s --interval=60s --timeout=10s --retries=3 \
    CMD ping -c 1 10.2.0.1 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
