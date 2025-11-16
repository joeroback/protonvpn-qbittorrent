# Proton VPN + Port Forwarding + qBittorrent

This relies on qBittorrent Web UI not requiring authentication for localhost connections.

```
Tools
  -> Options
    -> Web UI
      -> Authentication
        -> [X] Bypass authentication for clients on localhost
```

### Recommended Environment Variables

| Variable | Default | Examples | Description |
| -------- | ------- | ----- | ---------- |
| `TZ` | `UTC` | `America/Denver` | Set your [timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) to make sure logs rotate at local midnight instead of at UTC midnight.
| `WIREGUARD_INTERFACE` | `wg0` | `wg0`, `wg1`, ... | Set the wireguard interface name to use.
| `LOCAL_IPV4_SUBNETS` | `192.168.0.0/16` | `192.168.0.0/16, 10.0.0.0/8` | Comma separated list of local subnet CIDRs to be allowed outside the wireguard tunnel.
| `WEBUI_HOST` | `http://localhost:8080` | <URL to qBittorrent Web UI> | Url to the qBittorrent Web UI. Authenication must be disabled to localhost connections.
