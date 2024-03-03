function VpsAdminConsole(element, vpsId, session) {
  this.element = element;
  this.url = "/console/feed/" + vpsId;
  this.session = session;
  this.term = new Terminal();
  this.pendingData = '';
  this.rate = 1.0 / 20 * 1000; // 20 times per second, 50 ms

  var that = this;

  this.term.onData(function (data) {
    that.pendingData += data;
  });
};

VpsAdminConsole.prototype.open = function () {
  this.term.open(this.element);

  var that = this;

  this.timeout = setTimeout(function () {
    that.sendData();
  }, 1);
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

        that.term.write(atob(jsonResponse.data));

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
