#!/usr/bin/env bash

set -o errexit

default_route_ip=$(ip route | grep '^default' | awk '{print $3}')
if [[ -z "${default_route_ip}" ]]; then
        echo "Error: No default route configured" >&2
        exit 1
fi

if [[ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark)" != "1" ]]; then
        echo "Error: sysctl net.ipv4.conf.all.src_valid_mark=1 is not set" >&2
        exit 1
fi

# sysctl is set by container, wg-quick will then error
sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo Skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick

WIREGUARD_INTERFACE="${WIREGUARD_INTERFACE:-wg0}"

if [ ! -f "/etc/wireguard/${WIREGUARD_INTERFACE}.conf" ]; then
    echo "Error: Configuration file /etc/wireguard/${WIREGUARD_INTERFACE}.conf does not exist" >&2
    exit 1
fi

echo "Bringing up wireguard interface: ${WIREGUARD_INTERFACE}..."
wg-quick up ${WIREGUARD_INTERFACE}

shutdown () {
    wg-quick down ${WIREGUARD_INTERFACE}
    exit 0
}

trap shutdown SIGTERM SIGINT SIGQUIT

wg show

# kill switches for ipv4 and ipv6 wg-quick(8)
iptables -I OUTPUT ! -o ${WIREGUARD_INTERFACE} -m mark ! --mark $(wg show ${WIREGUARD_INTERFACE} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT
ip6tables -I OUTPUT ! -o ${WIREGUARD_INTERFACE} -m mark ! --mark $(wg show ${WIREGUARD_INTERFACE} fwmark) -m addrtype ! --dst-type LOCAL -j REJECT

# allow local container ipv4 subnets (especially helpful if using multiple networks)
for network in $(ip -o addr show | awk '/^(\d)+: eth(.+)inet / {print $4}'); do
    iptables -I OUTPUT -d ${network} -j ACCEPT
done

# allow connections user defined local ipv4 networks
for local_subnet in ${LOCAL_SUBNETS//,/$IFS}
do
    echo "Adding local subnet ${local_subnet} via ${default_route_ip}"
    ip route add ${local_subnet} via ${default_route_ip}
    iptables -I OUTPUT -d ${local_subnet} -j ACCEPT
done

sleep 2

# check to see if tunnel allows port forwarding
natpmpc -g 10.2.0.1

# give some delay until qbittorrent container launches
sleep 10

# qbittorrent webui host
WEBUI_HOST="${WEBUI_HOST:-http://localhost:8080}"

# loop now forever keeping port forward up to date (protonvpn)
# https://protonvpn.com/support/port-forwarding-manual-setup
while true; do
    tcp_output=$(natpmpc -a 1 0 tcp 60 -g 10.2.0.1)
    tcp_port=$(echo "${tcp_output}" | sed -n 's/.*Mapped public port \([0-9]\+\).*/\1/p')

    udp_output=$(natpmpc -a 1 0 udp 60 -g 10.2.0.1)
    udp_port=$(echo "${udp_output}" | sed -n 's/.*Mapped public port \([0-9]\+\).*/\1/p')

    if [[ "${tcp_port}" -ne "${udp_port}" ]]; then
        echo "Warning: tcp_port (${tcp_port}) and udp_port (${udp_port}) are different"
    fi

    # failure to connect to webui, we don't want to fail the loop, just log the error and try again
    current_port=$(curl --silent --header "Referer: ${WEBUI_HOST}" "${WEBUI_HOST}/api/v2/app/preferences" | jq .listen_port || true)

    if [[ "${tcp_port}" -ne "${current_port}" ]]; then
        echo "Port changed from '${current_port}' to '${tcp_port}'. Updating app preferences..."

        curl \
            --silent \
            --header "Referer: ${WEBUI_HOST}" \
            --request POST \
            --data "json={\"listen_port\": ${tcp_port}}" \
            "${WEBUI_HOST}/api/v2/app/setPreferences" || true
    fi

    sleep 45 &
    wait ${!}
done

echo "exiting"
exit 0
