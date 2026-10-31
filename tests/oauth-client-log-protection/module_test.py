#!/usr/bin/env python3
"""Check the evaluated product modules; pair this with nginx.py for native proof."""

import json
from pathlib import Path
import sys


values = json.loads(Path(sys.argv[1]).read_text())
cases = values["cases"]
plain = cases["plain"]
assert all(values["invalid"].values()), values["invalid"]
for name, case in cases.items():
    hosts = case["hosts"]
    api = hosts["api.test"]
    assert list(hosts) == list(plain["hosts"]), name
    assert api["default"] and api["serverAliases"] == ["alias.test"], name
    for host in ("api.test", "auth.test", "webui.test", "php.test"):
        assert " vpsadmin;" in hosts[host]["extraConfig"], (name, host)
        assert "error_log /dev/null crit;" in hosts[host]["extraConfig"], (name, host)
    assert "vpsadmin_redirect_scheme" not in hosts["console.test"]["extraConfig"], name
    assert "error_log /dev/null" not in hosts["unrelated.test"]["extraConfig"], name
    assert "Referrer-Policy strict-origin always" in hosts["php.test"]["extraConfig"], name
    assert "Referrer-Policy strict-origin always" in hosts["webui.test"]["extraConfig"], name
    assert case["poolSettings"]["php_admin_value[error_log]"] == "syslog", name
    assert case["poolSettings"]["php_admin_flag[log_errors]"] is True, name
    assert case["poolSettings"]["catch_workers_output"] is True, name
    haproxy = case["haproxy"]
    for app in ("api", "webui"):
        assert "no log" in haproxy.split("frontend " + app + "-test", 1)[1].split("backend", 1)[0]
    assert "no log" not in haproxy.split("frontend console-router-test", 1)[1].split("backend", 1)[0]
    assert "proxy_set_header X-Forwarded-For $remote_addr;" in case["nginxConfig"], name
    assert "proxy_set_header Forwarded \"\";" in case["nginxConfig"], name

for mode in ("plain", "addSSL", "onlySSL", "rejectSSL", "overrideGlobal"):
    assert "vpsadmin_redirect_scheme" not in cases[mode]["hosts"]["api.test"]["extraConfig"], mode
for mode in ("forceSSL", "customListeners", "explicitListeners", "httpOnlyList", "tlsOnlyList", "sharedHttpAcme", "dnsAcme"):
    api = cases[mode]["hosts"]["api.test"]
    assert not api["forceSSL"] and api["addSSL"], mode
    assert f'return {api["redirectCode"]} https://$host$request_uri;' in api["extraConfig"], mode
    assert cases[mode]["nginxConfig"].count("server_name api.test alias.test;") == 1, mode

for mode, expected in (("addSSL", "addSSL"), ("onlySSL", "onlySSL"), ("rejectSSL", "rejectSSL")):
    assert cases[mode]["hosts"]["api.test"][expected], mode
assert cases["customListeners"]["hosts"]["api.test"]["listenAddresses"] == ["127.0.0.2", "[::1]"]
assert "listen [::1]:18443 ssl" in cases["customListeners"]["nginxConfig"]
assert "listen 127.0.0.2:18080" in cases["customListeners"]["nginxConfig"]
explicit = cases["explicitListeners"]["hosts"]["api.test"]["listen"]
assert [(x["addr"], x["port"], x["ssl"]) for x in explicit] == [
    ("127.0.0.2", 18082, False), ("[::1]", 18445, True)
]
for mode, ssl in (("httpOnlyList", False), ("tlsOnlyList", True)):
    listeners = cases[mode]["hosts"]["api.test"]["listen"]
    assert len(listeners) == 1 and listeners[0]["ssl"] is ssl, mode
    # One server retains the literal list; an empty split-half cannot synthesize
    # the accidental listener that nginx supplied with the old two-server form.
    assert cases[mode]["nginxConfig"].count("server_name api.test alias.test;") == 1

assert 'set $vpsadmin_redirect_scheme "";' in cases["sharedHttpAcme"]["hosts"]["api.test"]["extraConfig"]
assert 'set $vpsadmin_redirect_scheme "";' not in cases["dnsAcme"]["hosts"]["api.test"]["extraConfig"]
runtime = values["runtime"]
for host in ("api.test", "auth.test", "webui.test", "php.test", "maintenance.test"):
    assert runtime["nginxConfig"].count("server_name " + host + " ") == 1, host
assert runtime["nginxConfig"].count('set $vpsadmin_redirect_scheme "";') == 1
assert "auth_basic off;" in runtime["nginxConfig"]
print(json.dumps({"result": "PASS", "generated_cases": len(cases), "invalid_modes_rejected": list(values["invalid"]),
                  "runtime_hosts": 5, "one_sided_listener_limit_exercised": True}))
