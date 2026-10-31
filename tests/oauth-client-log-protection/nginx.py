#!/usr/bin/env python3
"""Exercise module.nix's generated product config using private native nginx.

Adapted from the site's seven-case nginx fixture. Only paths, listener ports
and worker count are isolated; logging, rewrites, auth and locations are the
actual module output. This is not an installed PHP or service-VM check.
"""

import argparse
import base64
import hashlib
import http.client
import http.server
import json
from pathlib import Path
import re
import socket
import ssl
import subprocess
import tempfile
import threading
import time


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-values", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    run = args.output_dir.resolve()
    run.mkdir(exist_ok=False)
    (run / "logs").mkdir()
    values_raw = args.module_values.read_bytes()
    values = json.loads(values_raw)["runtime"]
    nginx = values["nginx"]
    assert Path(nginx).is_file(), "selected locked nginx must already be available"
    sentinels = {key: "SYNTH_" + key.upper() + "_926b" for key in (
        "code", "state", "access_token", "refresh_token", "client_secret",
        "cookie", "authorization", "referer", "location", "set_cookie", "provider_body",
    )}
    requests = []

    class Upstream(http.server.BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_GET(self):
            requests.append({"path": self.path, "headers": dict(self.headers)})
            status = 502 if "provider-error" in self.path else 302 if "callback" in self.path else 200
            body = sentinels["provider_body"].encode() if status == 502 else b"ordinary response"
            self.send_response(status)
            self.send_header("Referrer-Policy", "unsafe-url")
            self.send_header("Location", "/continue?code=" + sentinels["location"])
            self.send_header("Set-Cookie", "session=" + sentinels["set_cookie"] + "; HttpOnly")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", "/CN=api.test", "-keyout", str(run / "key.pem"), "-out", str(run / "cert.pem")],
                   check=True, capture_output=True)
    password = sentinels["authorization"]
    hashed = subprocess.check_output(["openssl", "passwd", "-apr1", password], text=True).strip()
    (run / "htpasswd").write_text("synthetic:" + hashed + "\n")
    challenge = run / "acme/.well-known/acme-challenge"
    challenge.mkdir(parents=True)
    (challenge / "proof").write_text("challenge")
    maintenance = run / "maintenance"
    maintenance.mkdir()
    (maintenance / "maintenance.json").write_text('{"status":false,"message":"Server under maintenance."}')
    (maintenance / "maintenance.html").write_text("Maintenance")

    upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    socket_dir = tempfile.TemporaryDirectory(prefix="vpa-nginx-")
    thread = threading.Thread(target=upstream.serve_forever, daemon=True)
    thread.start()
    http_port, tls_port = free_port(), free_port()
    generated = values["nginxConfig"]
    config = generated.replace("/run/nginx/nginx.pid", str(run / "nginx.pid"))
    config = config.replace("error_log stderr;", "error_log " + str(run / "startup-error.log") + ";")
    config = config.replace("/var/log/nginx/", str(run / "logs") + "/")
    config = config.replace("/run/phpfpm/vpsadmin-webui.sock", socket_dir.name + "/php.sock")
    config = config.replace("/fixture/", str(run) + "/")
    config = config.replace("/var/lib/acme/api.test/fullchain.pem", str(run / "cert.pem"))
    config = config.replace("/var/lib/acme/api.test/key.pem", str(run / "key.pem"))
    config = config.replace("/var/lib/acme/api.test/chain.pem", str(run / "cert.pem"))
    config = re.sub(r"/nix/store/[a-z0-9]+-[a-z-]+-maintenance-root", str(maintenance), config)
    config = config.replace(":18080", ":" + str(http_port)).replace(":18443", ":" + str(tls_port))
    config = config.replace(":18081", ":" + str(upstream.server_port))
    config = config.replace("worker_processes auto;", "worker_processes 1;")
    config_path = run / "nginx.conf"
    config_path.write_text(config)
    (run / "adaptations.json").write_text(json.dumps({
        "module_values_sha256": hashlib.sha256(values_raw).hexdigest(),
        "generated_config_sha256": hashlib.sha256(generated.encode()).hexdigest(),
        "isolated": ["PID/log/FastCGI/cert/auth/ACME/maintenance paths", "listener/upstream ports", "worker count"],
        "policy_or_locations_replaced": False,
    }, indent=2) + "\n")
    common = ["-e", "stderr", "-c", str(config_path), "-p", str(run)]
    proc = None
    checks = []
    try:
        syntax = subprocess.run([nginx, "-t", *common], capture_output=True, text=True)
        (run / "syntax.stderr").write_text(syntax.stderr)
        assert syntax.returncode == 0, syntax.stderr
        with (run / "nginx.stdout").open("w") as stdout, (run / "nginx.stderr").open("w") as stderr:
            proc = subprocess.Popen([nginx, *common], stdout=stdout, stderr=stderr)
            deadline = time.monotonic() + 5
            while True:
                assert proc.poll() is None, "owned nginx failed at launch"
                try:
                    with socket.create_connection(("127.0.0.1", http_port), timeout=0.1):
                        break
                except OSError:
                    assert time.monotonic() < deadline, "owned listener setup failed"
                    time.sleep(0.05)

            basic = "Basic " + base64.b64encode(("synthetic:" + password).encode()).decode()
            headers = {"Cookie": "session=" + sentinels["cookie"], "Authorization": basic,
                       "Referer": "https://api.test/callback?code=" + sentinels["referer"],
                       "X-Forwarded-For": "192.0.2.77", "X-Forwarded-Proto": "spoofed", "Forwarded": "spoofed"}
            query = "&".join(key + "=" + sentinels[key] for key in (
                "code", "state", "access_token", "refresh_token", "client_secret")) + "&encoded=a%2Bb%26c"

            def request(host, path, tls=True, authenticated=True):
                conn = (http.client.HTTPSConnection("127.0.0.1", tls_port, context=ssl._create_unverified_context(), timeout=3)
                        if tls else http.client.HTTPConnection("127.0.0.1", http_port, timeout=3))
                try:
                    sent = dict(headers, Host=host) if host != "unrelated.test" else {"Host": host}
                    if not authenticated:
                        sent.pop("Authorization", None)
                    conn.request("GET", path, headers=sent)
                    response = conn.getresponse()
                    result = response.status, response.read(), response.getheaders()
                    checks.append({"host": host, "path": path.split("?")[0], "tls": tls, "status": response.status})
                    return result
                finally:
                    conn.close()

            for host, path in (("api.test", "/callback"), ("alias.test", "/callback"),
                               ("auth.test", "/_auth/oauth2/callback"), ("webui.test", "/callback"),
                               ("php.test", "/index.php"), ("maintenance.test", "/callback")):
                target = path + "?" + query
                status, _, response_headers = request(host, target, tls=False, authenticated=False)
                assert status == 308 and dict(response_headers)["Location"] == "https://" + host + target
                status, _, _ = request(host, target, authenticated=False)
                assert status == 401, (host, status)

            status, body, _ = request("api.test", "/.well-known/acme-challenge/proof?" + query, tls=False, authenticated=False)
            assert status == 200 and body == b"challenge"
            for host, path in (("api.test", "/callback"), ("auth.test", "/_auth/oauth2/callback"),
                               ("webui.test", "/callback"), ("api.test", "/provider-error")):
                target = path + "?" + query
                status, body, response_headers = request(host, target)
                assert status == (502 if "provider-error" in path else 302), (host, status, body)
                record = requests[-1]
                assert record["path"] == target
                for key in ("Cookie", "Authorization", "Referer"):
                    assert record["headers"][key] == headers[key], (host, key)
                if host in ("api.test", "auth.test"):
                    assert record["headers"]["X-Forwarded-For"] == "127.0.0.1"
                    assert record["headers"]["X-Forwarded-Proto"] == "https"
                    assert "Forwarded" not in record["headers"]
                assert dict(response_headers)["Location"] == "/continue?code=" + sentinels["location"]
                assert dict(response_headers)["Set-Cookie"] == "session=" + sentinels["set_cookie"] + "; HttpOnly"
                if host == "webui.test":
                    assert [v for k, v in response_headers if k.lower() == "referrer-policy"] == ["strict-origin"]
            status, body, _ = request("maintenance.test", "/callback?" + query)
            assert status == 503 and b"Server under maintenance" in body
            for path in ("/index.php", "/config.js.php", "/keepalive.php", "/session-time-zone.php", "/denied.php"):
                status, _, response_headers = request("php.test", path + "?" + query)
                assert status == (404 if path == "/denied.php" else 502), (path, status)
                assert [v for k, v in response_headers if k.lower() == "referrer-policy"] == ["strict-origin"]
            status, _, _ = request("unrelated.test", "/ordinary", tls=False)
            assert status == 204
    finally:
        if proc is not None and proc.poll() is None:
            quit_result = subprocess.run([nginx, "-s", "quit", *common], capture_output=True, text=True)
            (run / "quit.stderr").write_text(quit_result.stderr)
            assert quit_result.returncode == 0
            proc.wait(timeout=5)
        upstream.shutdown()
        upstream.server_close()
        thread.join(timeout=2)
        socket_dir.cleanup()
        (run / "reconciliation.json").write_text(json.dumps({
            "nginx_exit": proc.returncode if proc else None, "upstream_thread_alive": thread.is_alive(),
        }) + "\n")
    logs = "".join(p.read_text() for p in (list((run / "logs").glob("*.log")) + [
        run / "startup-error.log", run / "nginx.stdout", run / "nginx.stderr"]) if p.exists())
    assert all(value not in logs for value in (*sentinels.values(), basic)), "sentinel in native nginx output"
    access = "".join(p.read_text() for p in (run / "logs").glob("vpsadmin-*.log"))
    assert "?" not in access and " 502 " in access and " 503 " in access and " 308 " in access
    assert proc.returncode == 0 and not thread.is_alive()
    for port in (http_port, tls_port):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", port))
    result = {"result": "PASS", "scope": "actual module-generated native nginx; no installed PHP/application login",
              "checks": checks, "sentinels_absent": True, "safe_status_timing_diagnostics": True,
              "auth_wire_and_redirect_query_preserved": True, "owned_effects_reconciled": True}
    (run / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
