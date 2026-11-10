#!/usr/bin/env python3
"""Forward Tailscale and shared Wi-Fi connections to services that listen on 127.0.0.1.

This Mac has a public internet address on en0, so a service that listens on every
network is open to the whole internet. Copyparty, the wget server, YouTube transcribe,
TV board and the bookmark manager therefore listen on 127.0.0.1 only, and this gate
gives them back to the two private networks.

Each listener binds to one named address, so the public address refuses the connection.
An address that does not exist yet (Tailscale down, Internet Sharing off) is retried
until it appears, so a missing network never takes a service down.

The client check also matters. macOS accepts a packet for any of its addresses on any
network, so a machine on the public subnet could otherwise send directly to the
Tailscale address.

To add a service: make it listen on 127.0.0.1, then add its port to PORTS.
"""
import asyncio
import ipaddress

PORTS = {
    3003: "bookmark manager",
    3333: "TV board",
    3939: "copyparty",
    3940: "wget server",
    8086: "copyparty",
    8765: "YouTube transcribe",
}
GATE_ADDRESSES = ("100.64.0.1", "192.168.2.1")
ALLOWED_CLIENTS = (
    ipaddress.ip_network("100.64.0.0/10"),
    ipaddress.ip_network("192.168.2.0/24"),
)
BIND_RETRY_SECONDS = 30
READ_SIZE = 65536


async def pipe(reader, writer):
    while data := await reader.read(READ_SIZE):
        writer.write(data)
        await writer.drain()
    if writer.can_write_eof():
        writer.write_eof()


async def handle(client_reader, client_writer, port):
    client = client_writer.get_extra_info("peername")[0]
    if not any(ipaddress.ip_address(client) in net for net in ALLOWED_CLIENTS):
        print(f"Refused {client} on port {port}", flush=True)
        client_writer.close()
        return

    try:
        upstream_reader, upstream_writer = await asyncio.open_connection("127.0.0.1", port)
    except OSError:
        client_writer.close()
        return

    tasks = [
        asyncio.create_task(pipe(client_reader, upstream_writer)),
        asyncio.create_task(pipe(upstream_reader, client_writer)),
    ]
    try:
        await asyncio.gather(*tasks)
    except OSError:
        pass
    finally:
        for task in tasks:
            task.cancel()
        client_writer.close()
        upstream_writer.close()


async def listen(address, port):
    async def on_connect(reader, writer):
        await handle(reader, writer, port)

    logged_failure = False
    while True:
        try:
            server = await asyncio.start_server(on_connect, address, port)
            break
        except OSError as error:
            if not logged_failure:
                print(f"Waiting for {address}:{port}: {error}", flush=True)
                logged_failure = True
            await asyncio.sleep(BIND_RETRY_SECONDS)
    print(f"Listening on {address}:{port} for {PORTS[port]}", flush=True)
    await server.serve_forever()


async def main():
    await asyncio.gather(
        *(listen(address, port) for address in GATE_ADDRESSES for port in PORTS)
    )


if __name__ == "__main__":
    asyncio.run(main())
