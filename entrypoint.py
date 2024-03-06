#!/usr/local/protonvpn-natpmp/bin/python3

import json
import logging
import natpmp
import os
import signal
import sys
import time
import urllib.parse
import urllib.request

# https://protonvpn.com/support/port-forwarding/


class SignalHandler:
    def __init__(self):
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGQUIT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)

    def signal_handler(self, signum, frame):
        logging.info(f'A signal {signum} was caught. Exiting...')
        sys.exit(0)

class QBittorrentClient:
    def __init__(self, host, port):
        self.timeout = 10
        self.base_url = f'http://{host}:{port}'

        # qBittorrent API says to set the referer header
        # https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-4.1)
        self.headers = {
            'Referer': self.base_url,
            'Content-Type': 'application/x-www-form-urlencoded',
        }

    def get_version(self):
        req = urllib.request.Request(
            f'{self.base_url}/api/v2/app/version',
            headers=self.headers,
            method='GET'
        )

        resp = urllib.request.urlopen(req, timeout=self.timeout)
        return resp.read().decode('utf-8')

    def get_listen_port(self):
        req = urllib.request.Request(
            f'{self.base_url}/api/v2/app/preferences',
            headers=self.headers,
            method='GET'
        )

        resp = urllib.request.urlopen(req, timeout=self.timeout)
        preferences = json.loads(resp.read().decode('utf-8'))

        return preferences['listen_port']

    def set_listen_port(self, port):
        data = json.dumps({
            'listen_port': port,
            'random_port': False,
            'upnp': False,
        })
        data = f'json={data}'.encode('utf-8')

        req = urllib.request.Request(
            f'{self.base_url}/api/v2/app/setPreferences',
            data=data,
            headers=self.headers,
            method='POST'
        )

        resp = urllib.request.urlopen(req, timeout=self.timeout)
        if resp.status == 200:
            logging.info(f'Successfully updated qBittorrent listen port to {port}')
        else:
            logging.error(f'Failed to update qBittorrent listen port: {resp.status} - {resp.reason}')


def main():
    sig_handler = SignalHandler()

    logging.basicConfig(
        format='%(asctime)s:%(levelname)s: %(message)s', level=logging.INFO
    )
    logging.info('Starting Proton VPN NAT-PMP port forwarding daemon')

    # pause a bit at startup
    time.sleep(1)

    qbittorrent_host = os.getenv('QBITTORRENT_HOST') or 'localhost'
    qbittorrent_port = os.getenv('QBITTORRENT_PORT') or '8080'
    gateway_ip = os.getenv('GATEWAY_IP') or '10.2.0.1'

    qbittorrent_client = QBittorrentClient(qbittorrent_host, int(qbittorrent_port))

    while True:
        try:
            # request port forward, use public port 1, private port 0
            # protonvpn will return the opened public port. set lifetime to 60,
            # seems no matter whatever it is set to, it always returns 60s...
            tcp = natpmp.map_tcp_port(
                1,
                0,
                lifetime=60,
                gateway_ip=gateway_ip,
                retry=3,
                use_exception=True,
            )

            udp = natpmp.map_udp_port(
                1,
                0,
                lifetime=60,
                gateway_ip=gateway_ip,
                retry=3,
                use_exception=True,
            )

            assert tcp.private_port == 0
            assert udp.private_port == 0
            assert tcp.public_port == udp.public_port

            qbittorrent_version = qbittorrent_client.get_version()
            qbittorrent_listen_port = qbittorrent_client.get_listen_port()

            # only if port changed, update qBittorrent
            if tcp.public_port != qbittorrent_listen_port:
                logging.info(f'    NAT-PMP TCP Port: {tcp.public_port}')
                logging.info(f'    NAT-PMP UDP Port: {udp.public_port}')
                logging.info(f'    qBittorrent Version: {qbittorrent_version}')
                logging.info(f'qBittorrent Listen Port: {qbittorrent_listen_port}')
                qbittorrent_client.set_listen_port(tcp.public_port)

            sleep_for = max(1, min(tcp.lifetime, udp.lifetime) - 5)
            logging.debug(f'Sleeping for {sleep_for}s...')
            time.sleep(sleep_for)
        except Exception as e:
            logging.exception('An exception was thrown!')
            time.sleep(5)


if __name__ == '__main__':
    main()
