# Proton VPN + qBittorrent

This relies on qBittorrent web ui not requiring authentication for localhost.

```
Tools
  -> Options
    -> Web UI
      -> Authentication
        -> [X] Bypass authentication for clients on localhost
```

Example docker-compose.yml

```
version: '3'

services:
  wireguard:
    image: ghcr.io/jordanpotter/docker-wireguard:latest
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    sysctls:
      net.ipv4.conf.all.src_valid_mark: 1
      net.ipv6.conf.all.disable_ipv6: 1
    volumes:
      - ./wg0.conf:/etc/wireguard/wg0.conf
    environment:
      LOCAL_SUBNETS: '192.168.1.0/24'
    restart: always
    ports:
      - '8080:8080/tcp'
  protonvpn-natpmp:
    image: ghcr.io/joeroback/protonvpn-qbittorrent:latest
    network_mode: service:wireguard
    depends_on:
      - wireguard
    environment:
      QBITTORRENT_HOST: 'localhost'
      QBITTORRENT_PORT: '8080'
      GATEWAY_IP: '10.2.0.1'
    restart: always
  qbittorrent:
    image: ghcr.io/qbittorrent/docker-qbittorrent-nox:latest
    network_mode: service:wireguard
    depends_on:
      - wireguard
      - natpmp
    restart: always
    stop_grace_period: 5m
    cap_add:
      - CHOWN
      - SYS_NICE
    tmpfs: '/tmp'
    read_only: true
    environment:
      QBT_LEGAL_NOTICE: 'confirm'
      QBT_WEBUI_PORT: '8080'
      TZ: 'America/Denver'
    volumes:
      - './config:/config'
      - './downloads:/downloads'
```
