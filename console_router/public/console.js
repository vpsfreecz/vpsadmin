function VpsAdminConsole(element, vpsId, session) {
  this.element = element;
  this.url = "/console/feed/" + vpsId;
  this.session = session;

  this.term = new Terminal();
  this.fitAddon = new FitAddon.FitAddon();

  this.term.loadAddon(this.fitAddon);

  this.pendingData = '';
  this.rate = 1.0 / 20 * 1000; // 20 times per second, 50 ms

  var that = this;

  this.term.onData(function (data) {
    that.pendingData += data;
  });
};

VpsAdminConsole.prototype.open = function () {
  this.term.open(this.element);
  this.fitAddon.fit();

  var that = this;

  this.timeout = setTimeout(function () {
    that.sendData();
  }, 1);
};

VpsAdminConsole.prototype.sendKey = function (key, code, keyCode, modifiers) {
  var opts = {
    key: key,
    code: code,
    keyCode: keyCode,
    charCode: keyCode,
    ctrlKey: modifiers.ctrlKey || false,
    shiftKey: modifiers.shiftKey || false,
    altKey: modifiers.altKey || false,
    metaKey: modifiers.metaKey || false
  };

  // Workaround for Ctrl+C, etc. Always send keyCodes for A-Z instead of a-z.
  // Otherwise, the sequence is not recognized.
  if (key.length == 1 && !modifiers.shiftKey && keyCode >= 97 && keyCode <= 122) {
    opts.keyCode -= 32;
  }

  if (modifiers.ctrlKey) {
    this.sendEventToTerminal(new KeyboardEvent('keydown', {key: 'ControlLeft', keyCode: 17}));
  }
  if (modifiers.shiftKey) {
    this.sendEventToTerminal(new KeyboardEvent('keydown', {key: 'ShiftLeft', keyCode: 16}));
  }
  if (modifiers.altKey) {
    this.sendEventToTerminal(new KeyboardEvent('keydown', {key: 'AltLeft', keyCode: 255}));
  }
  if (modifiers.metaKey) {
    this.sendEventToTerminal(new KeyboardEvent('keydown', {key: 'MetaLeft', keyCode: 91}));
  }

  this.sendEventToTerminal(new KeyboardEvent('keydown', opts));

  // Fire keypress event only for space and A-Z. Without keypress, these keys
  // are not accepted. Sending keypress for other keys causes them to be duplicated.
  if (key == ' ' || (key.length == 1 && keyCode >= 65 && keyCode <= 90))
    this.sendEventToTerminal(new KeyboardEvent('keypress', opts));

  this.sendEventToTerminal(new KeyboardEvent('keyup', opts));

  if (modifiers.ctrlKey) {
    this.sendEventToTerminal(new KeyboardEvent('keyup', {key: 'ControlLeft', keyCode: 17}));
  }
  if (modifiers.shiftKey) {
    this.sendEventToTerminal(new KeyboardEvent('keyup', {key: 'ShiftLeft', keyCode: 16}));
  }
  if (modifiers.altKey) {
    this.sendEventToTerminal(new KeyboardEvent('keyup', {key: 'AltLeft', keyCode: 255}));
  }
  if (modifiers.metaKey) {
    this.sendEventToTerminal(new KeyboardEvent('keyup', {key: 'MetaLeft', keyCode: 91}));
  }
};

VpsAdminConsole.prototype.sendEventToTerminal = function (ev) {
  this.term.textarea.dispatchEvent(ev);
};

VpsAdminConsole.prototype.sendData = function () {
  var request = new XMLHttpRequest();

  request.open('POST', this.url + '?', true);
  request.setRequestHeader('Cache-Control', 'no-cache');
  request.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=utf-8');

  var body = 'width=' + this.term.cols;
  body += '&height=' + this.term.rows;
  body += '&keys=' + encodeURIComponent(this.pendingData);
  body += '&session=' + encodeURIComponent(this.session);

  var that = this;

  request.onreadystatechange = function () {
    if (request.readyState == 4) {
      if (request.status == 200) {
        var jsonResponse = JSON.parse(request.responseText);

        // For some reason it appears that the data gets encoded twice, which
        // then breaks rendering and so decoding before writing helps.
        that.term.write(that.decodeUtf8(atob(jsonResponse.data)));

        if (jsonResponse.session) {
          that.scheduleNextRequest();
        }

      } else if (request.status == 0) {
        that.sendData();

      } else {
        that.term.write("Communication error, please refresh the page.");
      }
    }
  };

  this.pendingData = '';
  request.send(body);
};

VpsAdminConsole.prototype.scheduleNextRequest = function () {
  var that = this;

  this.timeout = setTimeout(function () {
    that.sendData();
  }, this.rate);
};

VpsAdminConsole.prototype.decodeUtf8 = function (v) {
  return decodeURIComponent(escape(v));
};
