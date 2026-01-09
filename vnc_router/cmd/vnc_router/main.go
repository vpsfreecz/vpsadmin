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
  <title>VPS {{ .VpsID }}</title>
  <style>
    html, body { height: 100%; margin: 0; }
    body { display: flex; flex-direction: column; }
    #toolbar {
      display: flex; gap: 8px; align-items: center;
      padding: 8px 10px; border-bottom: 1px solid #ddd;
      font-family: sans-serif; font-size: 14px;
      flex-wrap: wrap;
    }
    #screen {
      width: 100%;
      flex: 1;
      background: #000;
    }
    .muted { color: #666; }
    button { padding: 6px 10px; }
    .keys { display: flex; gap: 6px; align-items: center; }
    #clipboardBox {
      display: flex; gap: 6px; align-items: center;
      padding: 8px 10px; border-bottom: 1px solid #ddd;
      font-family: sans-serif; font-size: 14px;
      background: #fafafa;
    }
    #clipboardInput {
      flex: 1;
      min-width: 260px;
      min-height: 32px;
      font-family: monospace;
    }
  </style>
</head>
<body>
  <div id="toolbar">
    <strong>VPS {{ .VpsID }}</strong>
    <span class="muted" id="status">disconnected</span>
    <button id="btnDisconnect">Disconnect</button>
    <label><input type="checkbox" id="scale" checked> Scale</label>
    <label><input type="checkbox" id="clip"> Clip</label>
    <div class="keys">
      <span class="muted">Special keys:</span>
      <button data-combo="Ctrl+Alt+Del">Ctrl+Alt+Del</button>
      <button data-combo="Ctrl+Alt+Backspace">Ctrl+Alt+Backspace</button>
      <button data-combo="Ctrl+Alt+F1">Ctrl+Alt+F1</button>
      <button data-combo="Ctrl+Alt+F2">Ctrl+Alt+F2</button>
      <button data-combo="Ctrl+Alt+F7">Ctrl+Alt+F7</button>
    </div>
  </div>
  <div id="clipboardBox">
    <span class="muted">Paste:</span>
    <textarea id="clipboardInput" placeholder="Type or paste text to send to VM"></textarea>
    <button id="clipboardSend">Send to VM</button>
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
    const btnDisconnect = document.getElementById('btnDisconnect');
    const scale = document.getElementById('scale');
    const clip = document.getElementById('clip');
    const keysButtons = Array.from(document.querySelectorAll('[data-combo]'));
    const clipboardInput = document.getElementById('clipboardInput');
    const clipboardSend = document.getElementById('clipboardSend');

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

      const showCloseNotice = () => {
        screen.innerHTML = '<div style="color:#fff;display:flex;align-items:center;justify-content:center;height:100%;font-family:sans-serif;font-size:16px;text-align:center;padding:24px;">'
          + 'Connection closed. Please close this window and reopen the VNC console from vpsAdmin to start a new session.'
          + '</div>';
      };

      rfb.addEventListener('connect', () => setStatus('connected'));
      rfb.addEventListener('disconnect', (e) => {
        setStatus('disconnected' + (e.detail && e.detail.clean ? '' : ' (error)'));
        showCloseNotice();
        rfb = null;
      });
      rfb.addEventListener('securityfailure', (e) => {
        setStatus('security failure');
        console.error('securityfailure', e);
      });
      rfb.addEventListener('credentialsrequired', () => {
        setStatus('credentials required (unexpected)');
      });
      rfb.addEventListener('clipboard', handleClipboard);
      btnDisconnect.addEventListener('click', () => {
        if (!rfb) return;
        rfb.disconnect();
        showCloseNotice();
      });
    }

    connect();
    scale.addEventListener('change', applyViewOptions);
    clip.addEventListener('change', applyViewOptions);
    keysButtons.forEach((btn) => {
      btn.addEventListener('click', () => sendCombo(btn.dataset.combo));
    });
    clipboardSend.addEventListener('click', sendClipboard);

    function sendCombo(name) {
      if (!rfb) return;

      const combos = {
        'Ctrl+Alt+Del': [
          { keysym: 0xffe3, code: 'ControlLeft' }, // Control_L
          { keysym: 0xffe9, code: 'AltLeft' },     // Alt_L
          { keysym: 0xffff, code: 'Delete' }       // Delete
        ],
        'Ctrl+Alt+Backspace': [
          { keysym: 0xffe3, code: 'ControlLeft' },
          { keysym: 0xffe9, code: 'AltLeft' },
          { keysym: 0xff08, code: 'Backspace' }
        ],
        'Ctrl+Alt+F1': [
          { keysym: 0xffe3, code: 'ControlLeft' },
          { keysym: 0xffe9, code: 'AltLeft' },
          { keysym: 0xffbe, code: 'F1' }
        ],
        'Ctrl+Alt+F2': [
          { keysym: 0xffe3, code: 'ControlLeft' },
          { keysym: 0xffe9, code: 'AltLeft' },
          { keysym: 0xffbf, code: 'F2' }
        ],
        'Ctrl+Alt+F7': [
          { keysym: 0xffe3, code: 'ControlLeft' },
          { keysym: 0xffe9, code: 'AltLeft' },
          { keysym: 0xffc4, code: 'F7' }
        ],
      };

      const combo = combos[name];
      if (!combo) return;

      combo.forEach((k) => rfb.sendKey(k.keysym, k.code, true));
      for (let i = combo.length - 1; i >= 0; i--) {
        const k = combo[i];
        rfb.sendKey(k.keysym, k.code, false);
      }
    }

    function sendClipboard() {
      if (!rfb) return;
      const text = clipboardInput.value || '';
      for (const ch of text) {
        sendCharAsKey(ch);
      }
    }

    // Update textarea when VM clipboard changes
    function handleClipboard(event) {
      if (!event?.detail?.text) return;
      clipboardInput.value = event.detail.text;
    }

    function sendCharAsKey(ch) {
      // Covers printable ASCII with shift handling for common symbols.
      const special = {
        '\r': { keysym: 0xff0d, code: 'Enter' },
        '\n': { keysym: 0xff0d, code: 'Enter' },
        '\t': { keysym: 0xff09, code: 'Tab' },
        ' ': { keysym: 0x20, code: 'Space' },
        '!': { keysym: 0x21, code: 'Digit1', shift: true },
        '"': { keysym: 0x22, code: 'Quote', shift: true },
        '#': { keysym: 0x23, code: 'Digit3', shift: true },
        '$': { keysym: 0x24, code: 'Digit4', shift: true },
        '%': { keysym: 0x25, code: 'Digit5', shift: true },
        '&': { keysym: 0x26, code: 'Digit7', shift: true },
        '\'': { keysym: 0x27, code: 'Quote' },
        '(': { keysym: 0x28, code: 'Digit9', shift: true },
        ')': { keysym: 0x29, code: 'Digit0', shift: true },
        '*': { keysym: 0x2a, code: 'Digit8', shift: true },
        '+': { keysym: 0x2b, code: 'Equal', shift: true },
        ',': { keysym: 0x2c, code: 'Comma' },
        '-': { keysym: 0x2d, code: 'Minus' },
        '.': { keysym: 0x2e, code: 'Period' },
        '/': { keysym: 0x2f, code: 'Slash' },
        ':': { keysym: 0x3a, code: 'Semicolon', shift: true },
        ';': { keysym: 0x3b, code: 'Semicolon' },
        '<': { keysym: 0x3c, code: 'Comma', shift: true },
        '=': { keysym: 0x3d, code: 'Equal' },
        '>': { keysym: 0x3e, code: 'Period', shift: true },
        '?': { keysym: 0x3f, code: 'Slash', shift: true },
        '@': { keysym: 0x40, code: 'Digit2', shift: true },
        '[': { keysym: 0x5b, code: 'BracketLeft' },
        '\\': { keysym: 0x5c, code: 'Backslash' },
        ']': { keysym: 0x5d, code: 'BracketRight' },
        '^': { keysym: 0x5e, code: 'Digit6', shift: true },
        '_': { keysym: 0x5f, code: 'Minus', shift: true },
        [String.fromCharCode(96)]: { keysym: 0x60, code: 'Backquote' },
        '{': { keysym: 0x7b, code: 'BracketLeft', shift: true },
        '|': { keysym: 0x7c, code: 'Backslash', shift: true },
        '}': { keysym: 0x7d, code: 'BracketRight', shift: true },
        '~': { keysym: 0x7e, code: 'Backquote', shift: true },
      };

      if (special[ch]) {
        return sendKeyWithMods(special[ch]);
      }

      if (ch >= 'a' && ch <= 'z') {
        return sendKeyWithMods({ keysym: ch.codePointAt(0), code: 'Key' + ch.toUpperCase() });
      }
      if (ch >= 'A' && ch <= 'Z') {
        return sendKeyWithMods({ keysym: ch.codePointAt(0), code: 'Key' + ch, shift: true });
      }
      if (ch >= '0' && ch <= '9') {
        return sendKeyWithMods({ keysym: ch.codePointAt(0), code: 'Digit' + ch });
      }

      const codePoint = ch.codePointAt(0);
      if (codePoint === undefined) return;
      sendKeyStroke(codePoint, undefined);
    }

    function sendKeyWithMods(info) {
      if (info.shift) {
        rfb.sendKey(0xffe1, 'ShiftLeft', true);
      }
      sendKeyStroke(info.keysym, info.code);
      if (info.shift) {
        rfb.sendKey(0xffe1, 'ShiftLeft', false);
      }
    }

    function sendKeyStroke(keysym, code) {
      rfb.sendKey(keysym, code || undefined, true);
      rfb.sendKey(keysym, code || undefined, false);
    }
  </script>
</body>
</html>`))

type consolePageData struct {
	ClientTokenJS template.JS // JSON-encoded string literal
	WSPath        string
	VpsID         int
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

	// Wrapper page: /console?client_token=...
	mux.HandleFunc("/console", func(w http.ResponseWriter, r *http.Request) {
		clientToken := r.URL.Query().Get("client_token")
		if clientToken == "" {
			http.Error(w, "missing client_token", http.StatusBadRequest)
			return
		}

		// Safe JS string literal via json.Marshal
		b, _ := json.Marshal(clientToken)

		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		target, err := rpcClient.GetVncTarget(ctx, clientToken)
		cancel()
		if err != nil {
			debugf("console: get_vnc_target failed from %s: %v", r.RemoteAddr, err)
			http.Error(w, "auth failed", http.StatusForbidden)
			return
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = consoleTpl.Execute(w, consolePageData{
			ClientTokenJS: template.JS(b),
			WSPath:        wsPath,
			VpsID:         target.VpsID,
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
