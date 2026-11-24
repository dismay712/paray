"""Run on Linux with Docker, curl, and the image supplied on the command line."""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid


class Echo(BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


def test_image(image, directory, origin_port):
    user_id = str(uuid.uuid4())
    server = json.loads(Path("config.json").read_text())
    server["inbounds"][0]["listen"] = "127.0.0.1"
    # Both the router and Freedom block private destinations for VLESS.
    # Allow only the echo service in the temporary test configuration.
    echo_target = {"network": "tcp", "ip": ["127.0.0.1/32"], "port": str(origin_port)}
    server["routing"]["rules"].insert(0, {
        "type": "field", **echo_target, "outboundTag": "direct",
    })
    direct = next(out for out in server["outbounds"] if out["tag"] == "direct")
    direct.setdefault("settings", {}).setdefault("finalRules", []).insert(0, {
        "action": "allow", **echo_target,
    })
    server_file = directory / "server.json"
    server_file.write_text(json.dumps(server))

    example = re.search(r"^```json\n(.*?)\n```$", Path("README.md").read_text(), re.M | re.S)
    client = json.loads(example.group(1))
    outbound = client["outbounds"][0]
    outbound["settings"].update(address="127.0.0.1", port=8488, id=user_id, encryption="none")
    # TLS normally terminates at the public ingress. Exercise the documented
    # XHTTP transport directly against the container's plaintext listener.
    outbound["streamSettings"]["security"] = "none"
    outbound["streamSettings"].pop("tlsSettings", None)
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        socks_port = sock.getsockname()[1]
    client["inbounds"] = [{"listen": "127.0.0.1", "port": socks_port, "protocol": "socks"}]
    client_file = directory / "client.json"
    client_file.write_text(json.dumps(client))

    container = docker("run", "-d", "--network", "host", "-e", f"WEBJS_UUID={user_id}",
                       "-v", f"{server_file}:/etc/paray/config.json:ro",
                       "-v", f"{client_file}:/tmp/client.json:ro", image)
    try:
        for _ in range(30):
            if subprocess.run(["docker", "exec", container, "healthcheck"],
                              stderr=subprocess.DEVNULL).returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError("Xray did not become healthy")

        for service in ("cloudflared", "komari"):
            state = docker("exec", container, "s6-svstat", "-o", "up,wantedup",
                           f"/run/service/{service}")
            if state != "false false":
                raise RuntimeError(f"{service} should be down with restart disabled: {state}")

        docker("exec", "-d", container, "sh", "-c",
               "exec xray run -config /tmp/client.json >/tmp/client.log 2>&1")
        payload = os.urandom(2 * 1024 * 1024)
        upload = directory / "upload.bin"
        upload.write_bytes(payload)
        response = subprocess.check_output([
            "curl", "--silent", "--show-error", "--fail", "--max-time", "30",
            "--retry", "5", "--retry-delay", "1", "--retry-connrefused", "--retry-max-time", "10",
            "--noproxy", "", "--proxy", f"socks5h://127.0.0.1:{socks_port}",
            "--header", "Expect:", "--data-binary", f"@{upload}",
            f"http://127.0.0.1:{origin_port}/echo",
        ])
        if response != payload:
            raise RuntimeError("XHTTP echo differed from the uploaded payload")
    except Exception:
        subprocess.run(["docker", "logs", container])
        subprocess.run(["docker", "exec", container, "sh", "-c",
                        "test ! -f /tmp/client.log || cat /tmp/client.log"])
        raise
    finally:
        docker("rm", "-f", container)


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp, HTTPServer(("127.0.0.1", 0), Echo) as origin:
        threading.Thread(target=origin.serve_forever, daemon=True).start()
        try:
            test_image(sys.argv[1], Path(tmp), origin.server_port)
        finally:
            origin.shutdown()
