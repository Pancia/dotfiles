#!/usr/bin/env python3
"""Serve the current folder to this Mac, Tailscale and the shared Wi-Fi only.

This replaces `python3 -m http.server 8420`, which listened on every network.
This Mac has a public internet address on en0, so that command published the
Lakshmi content, including the shopping list, to the internet.

Each listener binds to one named address, so the public address refuses the
connection. An address that does not exist yet (Tailscale down, Internet Sharing
off) is retried until it appears.

The client check also matters. macOS accepts a packet for any of its addresses
on any network, so a machine on the public subnet could otherwise send directly
to the Tailscale address.
"""
import http.server
import ipaddress
import socket
import threading
import time

PORT = 8420
LISTEN_ADDRESSES = ["127.0.0.1", "::1", "100.64.0.1", "192.168.2.1"]
ALLOWED_CLIENTS = [
    ipaddress.ip_network(network)
    for network in ("127.0.0.0/8", "::1/128", "100.64.0.0/10", "192.168.2.0/24")
]
BIND_RETRY_SECONDS = 30


class ContentServer(http.server.ThreadingHTTPServer):
    def verify_request(self, request, client_address):
        client = ipaddress.ip_address(client_address[0])
        return any(client in network for network in ALLOWED_CLIENTS)


class ContentServerV6(ContentServer):
    address_family = socket.AF_INET6


def serve_on(address):
    server_class = ContentServerV6 if ":" in address else ContentServer
    logged_failure = False
    while True:
        try:
            server = server_class(
                (address, PORT), http.server.SimpleHTTPRequestHandler
            )
            break
        except OSError as error:
            if not logged_failure:
                print(f"Waiting for {address}:{PORT}: {error}", flush=True)
                logged_failure = True
            time.sleep(BIND_RETRY_SECONDS)
    print(f"Listening on {address}:{PORT}", flush=True)
    server.serve_forever()


def main():
    threads = [
        threading.Thread(target=serve_on, args=(address,), daemon=True)
        for address in LISTEN_ADDRESSES
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


if __name__ == "__main__":
    main()
