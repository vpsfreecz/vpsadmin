package main

import (
	"context"
	"encoding/json"
	"flag"
	"html/template"
	"log"
	"net"
	"net/http"
	"path/filepath"
	"time"

	"vnc_router/internal/config"
	"vnc_router/internal/metrics"
	"vnc_router/internal/proxy"
	"vnc_router/internal/rpc"

	"github.com/gorilla/websocket"
)

const (
	wsPath = "/ws"

	rpcExchange    = "vnc:rpc"
	rpcRoutingKey  = "rpc"
	rpcSoftTimeout = 10 * time.Second
	rpcHardTimeout = 60 * time.Second
)

// multiFlag allows repeating -config multiple times
type multiFlag []string

func (m *multiFlag) String() string { return "" }
func (m *multiFlag) Set(v string) error {
	*m = append(*m, v)
	return nil
}

var consoleTpl = template.Must(template.New("console").Parse(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>VNC Console</title>
  <style>
    html, body { height: 100%; margin: 0; }
    #toolbar {
      display: flex; gap: 8px; align-items: center;
      padding: 8px 10px; border-bottom: 1px solid #ddd;
      font-family: sans-serif; font-size: 14px;
    }
    #screen {
      width: 100%;
      height: calc(100% - 42px);
      background: #000;
    }
    .muted { color: #666; }
    button { padding: 6px 10px; }
  </style>
</head>
<body>
  <div id="toolbar">
    <strong>VNC Console</strong>
    <span class="muted" id="status">disconnected</span>
    <button id="btnConnect">Connect</button>
    <button id="btnDisconnect">Disconnect</button>
    <label><input type="checkbox" id="scale" checked> Scale</label>
    <label><input type="checkbox" id="clip"> Clip</label>
  </div>

  <div id="screen"></div>

  <!-- noVNC RFB module -->
  <script type="module">
    import RFB from '/core/rfb.js';

    const clientToken = {{ .ClientTokenJS }};
    const wsUrl = (() => {
      const proto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
      return proto + '//' + location.host + '{{ .WSPath }}' + '?client_token=' + encodeURIComponent(clientToken);
    })();

    const screen = document.getElementById('screen');
    const status = document.getElementById('status');
    const btnConnect = document.getElementById('btnConnect');
    const btnDisconnect = document.getElementById('btnDisconnect');
    const scale = document.getElementById('scale');
    const clip = document.getElementById('clip');

    let rfb = null;

    function setStatus(text) {
      status.textContent = text;
    }

    function applyViewOptions() {
      if (!rfb) return;
      rfb.scaleViewport = !!scale.checked;
      rfb.clipViewport = !!clip.checked;
    }

    function connect() {
      if (rfb) return;
      setStatus('connecting...');
      rfb = new RFB(screen, wsUrl, {
        // credentials: { password: '...' } // not used in your design
      });

      // Good defaults
      rfb.viewOnly = false;
      rfb.focusOnClick = true;

      applyViewOptions();

      rfb.addEventListener('connect', () => setStatus('connected'));
      rfb.addEventListener('disconnect', (e) => {
        setStatus('disconnected' + (e.detail && e.detail.clean ? '' : ' (error)'));
        rfb = null;
      });
      rfb.addEventListener('securityfailure', (e) => {
        setStatus('security failure');
        console.error('securityfailure', e);
      });
      rfb.addEventListener('credentialsrequired', () => {
        setStatus('credentials required (unexpected)');
      });
    }

    function disconnect() {
      if (!rfb) return;
      rfb.disconnect();
      // rfb becomes null in disconnect handler
    }

    btnConnect.addEventListener('click', connect);
    btnDisconnect.addEventListener('click', disconnect);
    scale.addEventListener('change', applyViewOptions);
    clip.addEventListener('change', applyViewOptions);

    // Optional: autoconnect
    {{ if .AutoConnect }}
    connect();
    {{ end }}
  </script>
</body>
</html>`))

type consolePageData struct {
	ClientTokenJS template.JS // JSON-encoded string literal
	WSPath        string
	AutoConnect   bool
}

func main() {
	var (
		configFiles multiFlag
		debug       bool
	)

	flag.Var(&configFiles, "config", "config file path (repeatable; later overrides earlier)")
	flag.BoolVar(&debug, "debug", false, "enable debug logging (stderr)")
	flag.Parse()

	debugf := func(format string, args ...any) {
		if debug {
			log.Printf(format, args...)
		}
	}

	cfg, err := config.LoadFiles([]string(configFiles))
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	metricsAllow := make([]*net.IPNet, 0, len(cfg.MetricsAllowedSubnets))
	for _, cidr := range cfg.MetricsAllowedSubnets {
		_, n, perr := net.ParseCIDR(cidr)
		if perr != nil {
			log.Fatalf("invalid metrics_allowed_subnets %q: %v", cidr, perr)
		}
		metricsAllow = append(metricsAllow, n)
	}

	absNoVNC, _ := filepath.Abs(cfg.NoVNCDir)
	debugf("noVNC dir: %s", absNoVNC)

	metricsRegistry := metrics.New()
	rpcClient := rpc.New(cfg.RabbitMQURL, rpcExchange, rpcRoutingKey, rpcSoftTimeout, rpcHardTimeout, debug)
	defer rpcClient.Close()

	mux := http.NewServeMux()

	ipAllowed := func(ip net.IP) bool {
		if ip == nil {
			return false
		}
		for _, n := range metricsAllow {
			if n.Contains(ip) {
				return true
			}
		}
		return false
	}

	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		host, _, err := net.SplitHostPort(r.RemoteAddr)
		if err != nil {
			host = r.RemoteAddr
		}
		ip := net.ParseIP(host)
		if !ipAllowed(ip) {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}

		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		metricsRegistry.ExportPrometheus(w)
	})

	// Wrapper page: /console?client_token=...&autoconnect=1
	mux.HandleFunc("/console", func(w http.ResponseWriter, r *http.Request) {
		clientToken := r.URL.Query().Get("client_token")
		if clientToken == "" {
			http.Error(w, "missing client_token", http.StatusBadRequest)
			return
		}

		// Allow ?autoconnect=1 (or true)
		ac := r.URL.Query().Get("autoconnect")
		auto := ac == "1" || ac == "true" || ac == "yes"

		// Safe JS string literal via json.Marshal
		b, _ := json.Marshal(clientToken)

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = consoleTpl.Execute(w, consolePageData{
			ClientTokenJS: template.JS(b),
			WSPath:        wsPath,
			AutoConnect:   auto,
		})
	})

	// WebSocket endpoint: /ws?client_token=...
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool { return true },
	}

	mux.HandleFunc(wsPath, func(w http.ResponseWriter, r *http.Request) {
		clientToken := r.URL.Query().Get("client_token")
		if clientToken == "" {
			debugf("ws: missing client_token from %s", r.RemoteAddr)
			http.Error(w, "missing client_token", http.StatusForbidden)
			return
		}

		ws, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			debugf("ws upgrade failed from %s: %v", r.RemoteAddr, err)
			return
		}
		defer ws.Close()

		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		target, err := rpcClient.GetVncTarget(ctx, clientToken)
		cancel()
		if err != nil {
			debugf("ws auth failed from %s: %v", r.RemoteAddr, err)
			_ = ws.WriteMessage(websocket.TextMessage, []byte("auth failed"))
			return
		}

		if target.NodeHost == "" || target.NodePort == 0 || target.NodeToken == "" {
			debugf("ws rpc returned incomplete target for %s: %+v", r.RemoteAddr, target)
			_ = ws.WriteMessage(websocket.TextMessage, []byte("server error"))
			return
		}

		connMetrics := metricsRegistry.NewConnection(target.VpsID)
		defer connMetrics.Done()

		ws.SetReadLimit(8 * 1024 * 1024)

		debugf("ws connected from %s -> node %s:%d", r.RemoteAddr, target.NodeHost, target.NodePort)

		if err := proxy.ProxyWSToNode(r.Context(), ws, target.NodeHost, target.NodePort, target.NodeToken, connMetrics); err != nil {
			debugf("ws proxy ended for %s (node %s:%d): %v", r.RemoteAddr, target.NodeHost, target.NodePort, err)
			return
		}

		debugf("ws disconnected cleanly from %s (node %s:%d)", r.RemoteAddr, target.NodeHost, target.NodePort)
	})

	// Generate defaults.json dynamically so /vnc.html connects to /ws by default.
	mux.HandleFunc("/defaults.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-cache")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"path": "ws",
		})
	})

	// Serve noVNC static files at "/" (so /vnc.html works).
	// Must be last so it doesn't shadow /ws, /console, /defaults.json.
	fs := http.FileServer(http.Dir(cfg.NoVNCDir))
	mux.Handle("/", fs)

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("vnc_router listening on http://%s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}
