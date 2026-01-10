package main

import (
	"context"
	"embed"
	"encoding/json"
	"flag"
	"html/template"
	"log"
	"net"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
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

//go:embed assets/haveapi-client.js
var staticFiles embed.FS

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
    .spinner {
      display: none;
      width: 16px;
      height: 16px;
      border: 2px solid #ccc;
      border-top-color: #555;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    }
    @keyframes spin {
      to { transform: rotate(360deg); }
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
    .dropdown {
      position: relative;
      display: inline-block;
    }
    .dropdown-menu {
      display: none;
      position: absolute;
      top: 100%;
      left: 0;
      min-width: 120px;
      background: #fff;
      border: 1px solid #ccc;
      box-shadow: 0 2px 6px rgba(0,0,0,0.15);
      z-index: 10;
    }
    .dropdown-menu.open {
      display: block;
    }
    .dropdown-menu button {
      width: 100%;
      padding: 8px 10px;
      text-align: left;
      border: none;
      background: #fff;
      cursor: pointer;
    }
    .dropdown-menu button:hover {
      background: #f0f0f0;
    }
    .dropdown-menu button.disabled {
      color: #888;
      cursor: not-allowed;
    }
  </style>
</head>
<body>
  <div id="toolbar">
    <strong>VPS {{ .VpsID }}</strong>
    <span class="muted" id="status">disconnected</span>
    <span class="spinner" id="spinner" aria-label="loading"></span>
    <button id="btnConnect">Connect</button>
    <button id="btnDisconnect" style="display:none;">Disconnect</button>
    <label><input type="checkbox" id="scale" checked> Scale</label>
    <label><input type="checkbox" id="clip"> Clip</label>
    <div class="keys">
      <span class="muted">Special keys:</span>
      <button data-combo="Ctrl+Alt+Del">Ctrl+Alt+Del</button>
      <button data-combo="Ctrl+Alt+Backspace">Ctrl+Alt+Backspace</button>
      <button data-combo="Ctrl+Alt+F1">Ctrl+Alt+F1</button>
      <button data-combo="Ctrl+Alt+F2">Ctrl+Alt+F2</button>
      <button data-combo="Ctrl+Alt+F7">Ctrl+Alt+F7</button>
      <button id="toggleClipboard" class="muted">Show paste box</button>
    </div>
    <div class="dropdown" id="powerDropdown">
      <button id="powerToggle">Power ▾</button>
      <div class="dropdown-menu" id="powerMenu">
        <button data-action="start">Start</button>
        <button data-action="restart">Restart</button>
        <button data-action="stop">Stop</button>
        <button data-action="restart" data-force="true">Reset</button>
        <button data-action="stop" data-force="true">Poweroff</button>
      </div>
    </div>
  </div>
  <div id="clipboardBox" style="display:none;">
    <span class="muted">Paste:</span>
    <textarea id="clipboardInput" placeholder="Type or paste text to send to VM"></textarea>
    <button id="clipboardSend">Send to VM</button>
  </div>

  <div id="screen"></div>

  <script type="text/javascript" src="/haveapi-client.js"></script>
  <!-- noVNC RFB module -->
  <script type="module">
    import RFB from '/core/rfb.js';

    const pageData = {
      vpsId: {{ .VpsIDJS }},
      wsPath: {{ .WSPathJS }},
      clientToken: null,
      apiUrl: {{ .APIURLJS }},
      apiVersion: {{ .APIVersionJS }},
      authType: {{ .AuthTypeJS }},
      authToken: {{ .AuthTokenJS }},
    };

    const API_KEEPALIVE_MS = 60 * 1000;
    const RECONNECT_DELAY_MS = 2000;

    const screen = document.getElementById('screen');
    const status = document.getElementById('status');
    const spinner = document.getElementById('spinner');
    const btnConnect = document.getElementById('btnConnect');
    const btnDisconnect = document.getElementById('btnDisconnect');
    const scale = document.getElementById('scale');
    const clip = document.getElementById('clip');
    const keysButtons = Array.from(document.querySelectorAll('[data-combo]'));
    const clipboardInput = document.getElementById('clipboardInput');
    const clipboardSend = document.getElementById('clipboardSend');
    const toggleClipboard = document.getElementById('toggleClipboard');
    const clipboardBox = document.getElementById('clipboardBox');
    const powerDropdown = document.getElementById('powerDropdown');
    const powerToggle = document.getElementById('powerToggle');
    const powerMenu = document.getElementById('powerMenu');
    const powerButtons = Array.from(powerMenu ? powerMenu.querySelectorAll('[data-action]') : []);

    const hasApiAuth = !!(pageData.apiUrl && pageData.authType && pageData.authToken);

    let rfb = null;
    let manualDisconnect = false;
    let reconnecting = false;
    let reconnectTimer = null;
    let apiClientPromise = null;
    let apiKeepaliveTimer = null;
    let currentClientToken = pageData.clientToken;
    let powerBusy = false;
    let connectionBusy = false;

    function setStatus(text) {
      status.textContent = text;
    }

    function setSpinner(active) {
      if (!spinner) return;
      spinner.style.display = active ? 'inline-block' : 'none';
    }

    function setConnectionButtons(connected) {
      if (btnConnect && btnDisconnect) {
        btnConnect.style.display = connected ? 'none' : 'inline-block';
        btnDisconnect.style.display = connected ? 'inline-block' : 'none';
      }
    }

    function setConnectionBusy(busy) {
      connectionBusy = busy;
      if (btnConnect) btnConnect.disabled = busy;
      if (btnDisconnect) btnDisconnect.disabled = busy;
    }

    function buildWsUrl(token) {
      const wsPath = pageData.wsPath || '/ws';
      const proto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
      const url = new URL(proto + '//' + location.host + wsPath);
      url.searchParams.set('client_token', token || '');
      return url.toString();
    }

    function showCloseNotice(customText) {
      const msg = customText || 'Connection closed. You can use Connect to reconnect, or reopen the VNC console from vpsAdmin.';
      screen.innerHTML = '<div style="color:#fff;display:flex;align-items:center;justify-content:center;height:100%;font-family:sans-serif;font-size:16px;text-align:center;padding:24px;">'
        + msg
        + '</div>';
    }

    function requestAutoscale() {
      if (!rfb || !scale.checked) return;
      // Prefer noVNC's resize handler if present
      if (rfb._eventHandlers && typeof rfb._eventHandlers.windowResize === 'function') {
        rfb._eventHandlers.windowResize(new Event('resize'));
      }
      // Fallback: briefly toggle scaleViewport to force recalculation, then emit a resize
      rfb.scaleViewport = false;
      rfb.scaleViewport = true;
      window.dispatchEvent(new Event('resize'));
    }

    function applyViewOptions() {
      if (!rfb) return;
      rfb.scaleViewport = !!scale.checked;
      rfb.clipViewport = !!clip.checked;
      requestAutoscale();
    }

    async function ensureApiClient() {
      if (!hasApiAuth) {
        throw new Error('API auth not available');
      }

      if (!apiClientPromise) {
        if (!window.HaveAPI) {
          throw new Error('HaveAPI client not loaded');
        }

        apiClientPromise = new Promise((resolve, reject) => {
          const opts = pageData.apiVersion ? { version: pageData.apiVersion } : {};
          const client = new HaveAPI.Client(pageData.apiUrl, opts);

          let authOpts = null;
          if (pageData.authType === 'oauth2') {
            authOpts = { access_token: { access_token: pageData.authToken } };
          } else if (pageData.authType === 'token') {
            authOpts = { token: pageData.authToken };
          } else {
            reject(new Error('Unsupported auth type'));
            return;
          }

          client.authenticate(pageData.authType, authOpts, (c, ok) => {
            if (!ok) {
              reject(new Error('API authentication failed'));
              return;
            }
            resolve(client);
          });
        });
      }

      return apiClientPromise;
    }

    async function fetchNewVncToken() {
      const client = await ensureApiClient();
      return new Promise((resolve, reject) => {
        client.vps.vnc_token.create(pageData.vpsId, {
          onReply: (c, vncToken) => {
            if (!vncToken || !vncToken.isOk || !vncToken.isOk()) {
              const msg = (vncToken && typeof vncToken.message === 'function')
                ? vncToken.message()
                : 'Unable to acquire VNC token';
              reject(new Error(msg));
              return;
            }
            resolve(vncToken.client_token);
          },
        });
      });
    }

    async function apiKeepaliveLoop() {
      if (!hasApiAuth || manualDisconnect) return;

      try {
        const client = await ensureApiClient();
        await new Promise((resolve, reject) => {
          client.vps.show(pageData.vpsId, {
            onReply: (c, resp) => {
              if (!resp.isOk()) {
                reject(new Error(resp.message() || 'VPS unavailable'));
                return;
              }
              resolve();
            },
          });
        });
      } catch (err) {
        handleFatal('API session expired or VPS unavailable. Please reopen the console.', err);
        return;
      }

      apiKeepaliveTimer = setTimeout(apiKeepaliveLoop, API_KEEPALIVE_MS);
    }

    function setPowerBusy(busy) {
      powerBusy = busy;
      if (powerToggle) {
        powerToggle.disabled = busy || !hasApiAuth;
      }
      powerButtons.forEach((btn) => {
        btn.classList.toggle('disabled', busy || !hasApiAuth);
        btn.disabled = busy || !hasApiAuth;
      });
      setSpinner(busy);
    }

    function closePowerMenu() {
      if (powerMenu) {
        powerMenu.classList.remove('open');
      }
    }

    function togglePowerMenu() {
      if (!powerMenu || !hasApiAuth) return;
      powerMenu.classList.toggle('open');
    }

    function handlePowerAction(action, label, force) {
      if (!hasApiAuth || powerBusy) return;

      closePowerMenu();
      setPowerBusy(true);
      setStatus(label + '...');

      ensureApiClient()
        .then((client) => {
          const params = force ? { force: true } : undefined;

          client.vps[action](pageData.vpsId, {
            params,
            onReply: (c, resp) => {
              if (!resp || !resp.isOk || !resp.isOk()) {
                const msg = (resp && typeof resp.message === 'function') ? resp.message() : 'Action failed';
                setStatus('Error: ' + msg);
                setPowerBusy(false);
                return;
              }
              setStatus(label + ' in progress...');
            },
            onDone: (c, reply) => {
              if (!reply || !reply.isOk || !reply.isOk()) {
                const msg = (reply && typeof reply.message === 'function') ? reply.message() : 'Action failed';
                setStatus('Error: ' + msg);
              } else {
                setStatus(label + ' done');
              }
              setPowerBusy(false);
            },
          });
        })
        .catch((err) => {
          console.error('Power action failed', err);
          setStatus('Error: ' + err.message);
          setPowerBusy(false);
        });
    }

    function setupPowerMenu() {
      if (!powerToggle || !powerMenu) return;

      powerToggle.addEventListener('click', (e) => {
        e.stopPropagation();
        togglePowerMenu();
      });

      powerButtons.forEach((btn) => {
        btn.addEventListener('click', (e) => {
          e.stopPropagation();
          const action = btn.dataset.action;
          const force = btn.dataset.force === 'true';
          if (action === 'start') return handlePowerAction('start', 'Starting', force);
          if (action === 'restart') return handlePowerAction('restart', force ? 'Resetting' : 'Restarting', force);
          if (action === 'stop') return handlePowerAction('stop', force ? 'Powering off' : 'Stopping', force);
        });
      });

      document.addEventListener('click', (e) => {
        if (!powerDropdown || !powerDropdown.contains(e.target)) {
          closePowerMenu();
        }
      });

      setPowerBusy(false);
    }

    function scheduleReconnect() {
      if (reconnecting || manualDisconnect) return;
      reconnecting = true;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
      }

      reconnectTimer = setTimeout(async () => {
        try {
          const newToken = await fetchNewVncToken();
          currentClientToken = newToken;
          connect(currentClientToken);
        } catch (err) {
          handleFatal('Unable to reconnect automatically. Please reopen the console.', err);
        } finally {
          reconnecting = false;
        }
      }, RECONNECT_DELAY_MS);
    }

    function handleFatal(message, err) {
      console.error(message, err);
      manualDisconnect = true;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
      }
      if (apiKeepaliveTimer) {
        clearTimeout(apiKeepaliveTimer);
      }
      if (rfb) {
        try {
          rfb.disconnect();
        } catch (e) {
          // ignore
        }
      }
      setStatus('Disconnected');
      showCloseNotice(message);
    }

    function onDisconnect(e) {
      const clean = !!(e.detail && e.detail.clean);
      rfb = null;
      setStatus('Disconnected' + (clean ? '' : ' (error)'));
      setConnectionButtons(false);
      setConnectionBusy(false);
      setPowerBusy(false);

      if (manualDisconnect) {
        showCloseNotice();
        return;
      }
      if (!hasApiAuth) {
        showCloseNotice();
        return;
      }

      setStatus('Reconnecting...');
      scheduleReconnect();
    }

    function connect(token = currentClientToken) {
      if (rfb) return;

      currentClientToken = token || currentClientToken;
      if (!currentClientToken || typeof currentClientToken !== 'string') {
        handleFatal('Missing VNC token, cannot connect.');
        return;
      }
      setStatus('Connecting...');
      setConnectionButtons(false);
      setConnectionBusy(true);
      screen.innerHTML = '';
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }

      let wsUrl;
      try {
        wsUrl = buildWsUrl(currentClientToken);
      } catch (err) {
        handleFatal('Invalid VNC endpoint URL', err);
        return;
      }

      rfb = new RFB(screen, wsUrl, {
        // credentials: { password: '...' } // not used in your design
      });

      // Good defaults
      rfb.viewOnly = false;
      rfb.focusOnClick = true;

      applyViewOptions();

      rfb.addEventListener('connect', () => setStatus('Connected'));
      rfb.addEventListener('disconnect', onDisconnect);
      rfb.addEventListener('securityfailure', (e) => {
        setStatus('Security failure');
        console.error('securityfailure', e);
      });
      rfb.addEventListener('credentialsrequired', () => {
        setStatus('Credentials required (unexpected)');
      });
      rfb.addEventListener('clipboard', handleClipboard);
      rfb.addEventListener('connect', () => {
        setConnectionButtons(true);
        setConnectionBusy(false);
      });
    }

    async function ensureClientToken() {
      if (currentClientToken && typeof currentClientToken === 'string') {
        return currentClientToken;
      }
      if (!hasApiAuth) {
        throw new Error('API auth required to obtain VNC token');
      }
      setStatus('Requesting VNC token...');
      const newToken = await fetchNewVncToken();
      currentClientToken = newToken;
      return newToken;
    }

    async function startConnectionWorkflow() {
      if (connectionBusy) return;
      setConnectionBusy(true);
      try {
        const tok = await ensureClientToken();
        connect(tok);
      } catch (err) {
        handleFatal('Unable to start VNC session', err);
      }
    }

    if (hasApiAuth) {
      startConnectionWorkflow();
      apiKeepaliveLoop();
    } else if (currentClientToken) {
      connect();
    } else {
      setStatus('Missing credentials');
    }
    setupPowerMenu();

    if (btnConnect) {
      btnConnect.addEventListener('click', () => {
        if (connectionBusy) return;
        manualDisconnect = false;
        startConnectionWorkflow();
      });
    }

    if (btnDisconnect) {
      btnDisconnect.addEventListener('click', () => {
      if (!rfb || connectionBusy) return;
      manualDisconnect = true;
      setConnectionBusy(true);
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
      }
        if (apiKeepaliveTimer) {
          clearTimeout(apiKeepaliveTimer);
        }
        rfb.disconnect();
        showCloseNotice();
      });
    }

    scale.addEventListener('change', applyViewOptions);
    clip.addEventListener('change', applyViewOptions);
    keysButtons.forEach((btn) => {
      btn.addEventListener('click', () => sendCombo(btn.dataset.combo));
    });
    clipboardSend.addEventListener('click', sendClipboard);
    toggleClipboard.addEventListener('click', () => {
      if (clipboardBox.style.display === 'none') {
        clipboardBox.style.display = 'flex';
        toggleClipboard.textContent = 'Hide paste box';
      } else {
        clipboardBox.style.display = 'none';
        toggleClipboard.textContent = 'Show paste box';
      }
      applyViewOptions();
    });

    // Re-apply scaling when textarea is resized
    let resizeObserver = null;
    if ('ResizeObserver' in window) {
      resizeObserver = new ResizeObserver(() => applyViewOptions());
      resizeObserver.observe(clipboardBox);
      resizeObserver.observe(clipboardInput);
    }

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
	WSPath       string
	VpsIDJS      template.JS
	WSPathJS     template.JS
	VpsID        int
	APIURLJS     template.JS
	APIVersionJS template.JS
	AuthTypeJS   template.JS
	AuthTokenJS  template.JS
}

func jsStringOrNull(s string) template.JS {
	if s == "" {
		return template.JS("null")
	}

	b, _ := json.Marshal(s)
	return template.JS(b)
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
	mux.HandleFunc("/haveapi-client.js", func(w http.ResponseWriter, r *http.Request) {
		data, err := staticFiles.ReadFile("assets/haveapi-client.js")
		if err != nil {
			http.Error(w, "not found", http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/javascript")
		_, _ = w.Write(data)
	})

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

	// Wrapper page: /console?client_token=... or /console?api_url=...&auth_type=...&auth_token=...&vps_id=...
	mux.HandleFunc("/console", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()

		apiURL := q.Get("api_url")
		apiVersion := q.Get("api_version")
		authType := strings.ToLower(q.Get("auth_type"))
		authToken := q.Get("auth_token")
		vpsID := 0
		if vpsIDStr := q.Get("vps_id"); vpsIDStr != "" {
			if parsed, err := strconv.Atoi(vpsIDStr); err == nil && parsed > 0 {
				vpsID = parsed
			}
		}

		if authType != "oauth2" && authType != "token" {
			authType = ""
			authToken = ""
		} else if authToken == "" {
			authType = ""
		}

		if vpsID == 0 {
			http.Error(w, "missing vps_id", http.StatusBadRequest)
			return
		}

		if apiURL == "" {
			http.Error(w, "missing api_url", http.StatusBadRequest)
			return
		}

		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_ = consoleTpl.Execute(w, consolePageData{
			WSPath:       wsPath,
			WSPathJS:     jsStringOrNull(wsPath),
			VpsID:        vpsID,
			VpsIDJS:      jsStringOrNull(strconv.Itoa(vpsID)),
			APIURLJS:     jsStringOrNull(apiURL),
			APIVersionJS: jsStringOrNull(apiVersion),
			AuthTypeJS:   jsStringOrNull(authType),
			AuthTokenJS:  jsStringOrNull(authToken),
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
	noVNCFS := http.FileServer(http.Dir(cfg.NoVNCDir))
	mux.Handle("/", noVNCFS)

	srv := &http.Server{
		Addr:              cfg.ListenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("vnc_router listening on http://%s", cfg.ListenAddr)
	log.Fatal(srv.ListenAndServe())
}
