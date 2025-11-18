#!/usr/bin/env bash

set -o errexit

info() {
    printf "I %5d %s\n" "${$}" "${*}"
}

fatal() {
    printf "F %5d %s\n" "${$}" "${*}" >&2
    exit 1
}

iptables-save | tee /tmp/rules.v4.$$.conf
ip6tables-save | tee /tmp/rules.v6.$$.conf

default_route_ip=$(ip route | grep '^default' | awk '{print $3}')
if [[ -z "${default_route_ip}" ]]; then
    fatal "Error: No default route configured"
fi

if [[ "$(cat /proc/sys/net/ipv4/conf/all/src_valid_mark)" != "1" ]]; then
    fatal "Error: sysctl net.ipv4.conf.all.src_valid_mark=1 is not set"
fi

# sysctl is set by container, wg-quick will then error
sed -i "s:sysctl -q net.ipv4.conf.all.src_valid_mark=1:echo Skipping setting net.ipv4.conf.all.src_valid_mark:" /usr/bin/wg-quick

WIREGUARD_INTERFACE="${WIREGUARD_INTERFACE:-wg0}"

if [ ! -f "/etc/wireguard/${WIREGUARD_INTERFACE}.conf" ]; then
    fatal "Error: Configuration file /etc/wireguard/${WIREGUARD_INTERFACE}.conf does not exist"
fi

info "Bringing up wireguard interface: ${WIREGUARD_INTERFACE}..."
wg-quick up ${WIREGUARD_INTERFACE}

shutdown () {
    info "shutting down wireguard interface: ${WIREGUARD_INTERFACE}..."
    wg-quick down ${WIREGUARD_INTERFACE}
    info "restoring iptables..."
    iptables-restore -n < /tmp/rules.v4.$$.conf
    info "restoring ip6tables..."
    ip6tables-restore -n < /tmp/rules.v6.$$.conf
}
trap shutdown EXIT

wg show
WIREGUARD_FWMARK=$(wg show ${WIREGUARD_INTERFACE} fwmark)

# allow connections from container subnets
for container_subnet in $(ip -o addr show | awk '/^(\d)+: eth(.+)inet / {print $4}')
do
    iptables -I INPUT -s ${container_subnet} -j ACCEPT
    iptables -I OUTPUT -d ${container_subnet} -j ACCEPT
done

# allow connections to local subnets specified by user, need to add routes since wireguard interface has 0.0.0.0/0 allowed ips
for local_subnet in ${LOCAL_IPV4_SUBNETS//,/$IFS}
do
    iptables -I INPUT -s ${local_subnet} -j ACCEPT
    iptables -I OUTPUT -d ${local_subnet} -j ACCEPT
    ip route add ${local_subnet} via ${default_route_ip}
done

# established connections
iptables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -I OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# kill switches for ipv4 -- @see wg-quick(8)
iptables -A OUTPUT ! -o ${WIREGUARD_INTERFACE} -m mark ! --mark ${WIREGUARD_FWMARK} -m addrtype ! --dst-type LOCAL -j REJECT --reject-with icmp-admin-prohibited

for container_subnet in $(ip -o addr show | awk '/^(\d)+: eth(.+)inet6 / {print $4}')
do
    ip6tables -I INPUT -s ${container_subnet} -j ACCEPT
    ip6tables -I OUTPUT -d ${container_subnet} -j ACCEPT
done

# established connections
ip6tables -I INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
ip6tables -I OUTPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# kill switches for ipv6 -- @see wg-quick(8)
ip6tables -A OUTPUT ! -o ${WIREGUARD_INTERFACE} -m mark ! --mark ${WIREGUARD_FWMARK} -m addrtype ! --dst-type LOCAL -j REJECT --reject-with icmp6-adm-prohibited

iptables-save | tee /tmp/rules.v4.${WIREGUARD_INTERFACE}.$$.conf
ip6tables-save | tee /tmp/rules.v6.${WIREGUARD_INTERFACE}.$$.conf

sleep 8 &
wait ${!}

# check to see if tunnel allows port forwarding
natpmpc -g 10.2.0.1

# give some delay until qbittorrent container launches
sleep 5 &
wait ${!}

# qbittorrent webui host
WEBUI_HOST="${WEBUI_HOST:-http://localhost:8080}"

# from this point on, its best effort, so just keep going and don't fail the container
set +o errexit

# loop now forever keeping port forward up to date (protonvpn)
# https://protonvpn.com/support/port-forwarding-manual-setup
while true; do
    tcp_output=$(natpmpc -a 1 0 tcp 60 -g 10.2.0.1)
    tcp_port=$(echo "${tcp_output}" | sed -n 's/.*Mapped public port \([0-9]\+\).*/\1/p')

    udp_output=$(natpmpc -a 1 0 udp 60 -g 10.2.0.1)
    udp_port=$(echo "${udp_output}" | sed -n 's/.*Mapped public port \([0-9]\+\).*/\1/p')

    if [[ "${tcp_port}" -ne "${udp_port}" ]]; then
        info "Warning: tcp_port (${tcp_port}) and udp_port (${udp_port}) are different"
    fi

    # failure to connect to webui, we don't want to fail the loop, just log the error and try again
    current_port=$(curl --silent --header "Referer: ${WEBUI_HOST}" "${WEBUI_HOST}/api/v2/app/preferences" | jq .listen_port || true)

    if [[ "${tcp_port}" -ne "${current_port}" ]]; then
        info "Port changed from '${current_port}' to '${tcp_port}'. Updating app preferences..."

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

info "exiting."
exit 0
