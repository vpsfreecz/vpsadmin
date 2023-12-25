// ShellInABox.js -- Use XMLHttpRequest to provide an AJAX terminal emulator.
// Copyright (C) 2008-2010 Markus Gutschke <markus@shellinabox.com>
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License version 2 as
// published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
// In addition to these license terms, the author grants the following
// additional rights:
//
// If you modify this program, or any covered work, by linking or
// combining it with the OpenSSL project's OpenSSL library (or a
// modified version of that library), containing parts covered by the
// terms of the OpenSSL or SSLeay licenses, the author
// grants you additional permission to convey the resulting work.
// Corresponding Source for a non-source form of such a combination
// shall include the source code for the parts of OpenSSL used as well
// as that of the covered work.
//
// You may at your option choose to remove this additional permission from
// the work, or from any part of it.
//
// It is possible to build this program in a way that it loads OpenSSL
// libraries at run-time. If doing so, the following notices are required
// by the OpenSSL and SSLeay licenses:
//
// This product includes software developed by the OpenSSL Project
// for use in the OpenSSL Toolkit. (http://www.openssl.org/)
//
// This product includes cryptographic software written by Eric Young
// (eay@cryptsoft.com)
//
//
// The most up-to-date version of this program is always available from
// http://shellinabox.com
//
//
// Notes:
//
// The author believes that for the purposes of this license, you meet the
// requirements for publishing the source code, if your web server publishes
// the source in unmodified form (i.e. with licensing information, comments,
// formatting, and identifier names intact). If there are technical reasons
// that require you to make changes to the source code when serving the
// JavaScript (e.g to remove pre-processor directives from the source), these
// changes should be done in a reversible fashion.
//
// The author does not consider websites that reference this script in
// unmodified form, and web servers that serve this script in unmodified form
// to be derived works. As such, they are believed to be outside of the
// scope of this license and not subject to the rights or restrictions of the
// GNU General Public License.
//
// If in doubt, consult a legal professional familiar with the laws that
// apply in your country.

// #define XHR_UNITIALIZED 0
// #define XHR_OPEN        1
// #define XHR_SENT        2
// #define XHR_RECEIVING   3
// #define XHR_LOADED      4

// IE does not define XMLHttpRequest by default, so we provide a suitable
// wrapper.
if (typeof XMLHttpRequest == 'undefined') {
    XMLHttpRequest = function () {
        try {
            return new ActiveXObject('Msxml2.XMLHTTP.6.0');
        } catch (e) {
        }
        try {
            return new ActiveXObject('Msxml2.XMLHTTP.3.0');
        } catch (e) {
        }
        try {
            return new ActiveXObject('Msxml2.XMLHTTP');
        } catch (e) {
        }
        try {
            return new ActiveXObject('Microsoft.XMLHTTP');
        } catch (e) {
        }
        throw new Error('');
    };
}

function extend(subClass, baseClass) {
    function inheritance() {
    }

    inheritance.prototype = baseClass.prototype;
    subClass.prototype = new inheritance();
    subClass.prototype.constructor = subClass;
    subClass.prototype.superClass = baseClass.prototype;
};

function ShellInABox(api_url, vps_id, auth_type, auth_token, session, container) {
    this.api_url = api_url;
    this.vps_id = vps_id;
    this.url = "/console/feed/" + this.vps_id
    this.nextUrl = this.url;
    this.auth_type = auth_type;
    this.auth_token = auth_token;
    this.session = session;
    this.pendingKeys = '';
    this.connected = false;
    this.rate = 1.0 / 20 * 1000; // 20 times per second, 50 ms
    this.timeout = null;
    this.superClass.constructor.call(this, container);

    // We have to initiate the first XMLHttpRequest from a timer. Otherwise,
    // Chrome never realizes that the page has loaded.
    setTimeout(function (shellInABox) {
        return function () {
            shellInABox.sendRequest();
        };
    }(this), 1);
};
extend(ShellInABox, VT100);

ShellInABox.prototype.sessionClosed = function () {
    try {
        this.connected = false;

        if (this.timeout) {
            clearTimeout(this.timeout);
            this.timeout = null;
        }

        if (this.session) {
            this.session = undefined;

            if (this.cursorX > 0) {
                this.vt100('\r\n');
            }

            this.vt100('Session closed.');
        }
        this.showReconnect(true);

    } catch (e) {
    }
};

ShellInABox.prototype.reconnect = function () {
	var that = this;
    this.showReconnect(false);

	if (this.session)
		return false;

	var restart = function () {
		that.api.vps(that.vps_id).console_token.create(function (c, token) {
			that.session = token.token;
			that.pendingKeys = '';
			that.reset(true);
			that.sendRequest();
		});
	};

	if (this.api === undefined) {
		this.api = new HaveAPI.Client(this.api_url);

        switch (this.auth_type) {
        case 'oauth2':
            this.api.authenticate('oauth2', {
                access_token: {access_token: that.auth_token},
            }, restart);
            break;
        case 'token':
            this.api.authenticate('token', {
                token: that.auth_token
            }, restart);
            break;
        default:
            throw "Unknown authentication type";
        }

	} else restart();

    return false;
};

ShellInABox.prototype.sendRequest = function (request) {
    if (request == undefined) {
        request = new XMLHttpRequest();
    }
    request.open('POST', this.url + '?', true);
    request.setRequestHeader('Cache-Control', 'no-cache');
    request.setRequestHeader('Content-Type',
        'application/x-www-form-urlencoded; charset=utf-8');
    var content = 'width=' + this.terminalWidth +
        '&height=' + this.terminalHeight +
        '&keys=' + encodeURIComponent(this.pendingKeys) +
        (this.session ? '&session=' +
            encodeURIComponent(this.session) : '&rooturl=' +
            encodeURIComponent(this.rooturl));
    request.setRequestHeader('Content-Length', content.length);

    request.onreadystatechange = function (shellInABox) {
        return function () {
            try {
                return shellInABox.onReadyStateChange(request);

            } catch (e) {
                shellInABox.sessionClosed();
            }
        }
    }(this);

    this.pendingKeys = '';
    request.send(content);
};

ShellInABox.prototype.onReadyStateChange = function (request) {
    if (request.readyState == 4 /* XHR_LOADED */) {
        if (request.status == 200) {
            this.connected = true;
            var response = eval('(' + request.responseText + ')');
            if (response.data) {
                this.vt100(atob(response.data));
            }

            if (!response.session) {
                this.sessionClosed();

            } else {
                this.timeout = setTimeout(this.sendRequest.bind(this), this.rate);
            }

        } else if (request.status == 0) {
            // Time Out
            this.sendRequest(request);

        } else {
            this.sessionClosed();
        }
    }
};

ShellInABox.prototype.sendKeys = function (keys) {
    if (!this.connected)
        return;

    this.pendingKeys += keys;
};

ShellInABox.prototype.keysPressed = function (ch) {
    var hex = '0123456789ABCDEF';
    var s = '';
    for (var i = 0; i < ch.length; i++) {
        var c = ch.charCodeAt(i);
        if (c < 128) {
            s += hex.charAt(c >> 4) + hex.charAt(c & 0xF);
        } else if (c < 0x800) {
            s += hex.charAt(0xC + (c >> 10)) +
                hex.charAt((c >> 6) & 0xF) +
                hex.charAt(0x8 + ((c >> 4) & 0x3)) +
                hex.charAt(c & 0xF);
        } else if (c < 0x10000) {
            s += 'E' +
                hex.charAt((c >> 12)) +
                hex.charAt(0x8 + ((c >> 10) & 0x3)) +
                hex.charAt((c >> 6) & 0xF) +
                hex.charAt(0x8 + ((c >> 4) & 0x3)) +
                hex.charAt(c & 0xF);
        } else if (c < 0x110000) {
            s += 'F' +
                hex.charAt((c >> 18)) +
                hex.charAt(0x8 + ((c >> 16) & 0x3)) +
                hex.charAt((c >> 12) & 0xF) +
                hex.charAt(0x8 + ((c >> 10) & 0x3)) +
                hex.charAt((c >> 6) & 0xF) +
                hex.charAt(0x8 + ((c >> 4) & 0x3)) +
                hex.charAt(c & 0xF);
        }
    }
    this.sendKeys(ch);
};

ShellInABox.prototype.resized = function (w, h) {
    // Nothing to do
};

ShellInABox.prototype.toggleSSL = function () {
    if (document.location.hash != '') {
        if (this.nextUrl.match(/\?plain$/)) {
            this.nextUrl = this.nextUrl.replace(/\?plain$/, '');
        } else {
            this.nextUrl = this.nextUrl.replace(/[?#].*/, '') + '?plain';
        }
        if (!this.session) {
            parent.location = this.nextUrl;
        }
    } else {
        this.nextUrl = this.nextUrl.match(/^https:/)
            ? this.nextUrl.replace(/^https:/, 'http:').replace(/\/*$/, '/plain')
            : this.nextUrl.replace(/^http/, 'https').replace(/\/*plain$/, '');
    }
    if (this.nextUrl.match(/^[:]*:\/\/[^/]*$/)) {
        this.nextUrl += '/';
    }
    if (this.session && this.nextUrl != this.url) {
        alert('This change will take effect the next time you login.');
    }
};

ShellInABox.prototype.extendContextMenu = function (entries, actions) {
    // Modify the entries and actions in place, adding any locally defined
    // menu entries.
    var oldActions = [ ];
    for (var i = 0; i < actions.length; i++) {
        oldActions[i] = actions[i];
    }
    for (var node = entries.firstChild, i = 0, j = 0; node;
         node = node.nextSibling) {
        if (node.tagName == 'LI') {
            actions[i++] = oldActions[j++];
            if (node.id == "endconfig") {
                node.id = '';
                if (typeof serverSupportsSSL != 'undefined' && serverSupportsSSL && !(typeof disableSSLMenu != 'undefined' && disableSSLMenu)) {
                    // If the server supports both SSL and plain text connections,
                    // provide a menu entry to switch between the two.
                    var newNode = document.createElement('li');
                    var isSecure;
                    if (document.location.hash != '') {
                        isSecure = !this.nextUrl.match(/\?plain$/);
                    } else {
                        isSecure = this.nextUrl.match(/^https:/);
                    }
                    newNode.innerHTML = (isSecure ? '&#10004; ' : '') + 'Secure';
                    if (node.nextSibling) {
                        entries.insertBefore(newNode, node.nextSibling);
                    } else {
                        entries.appendChild(newNode);
                    }
                    actions[i++] = this.toggleSSL;
                    node = newNode;
                }
                node.id = 'endconfig';
            }
        }
    }

};

ShellInABox.prototype.about = function () {
    alert("Shell In A Box version " + "2.10 (revision 239)" +
        "\nCopyright 2008-2010 by Markus Gutschke\n" +
        "For more information check http://shellinabox.com" +
        "\n\nModified by Jakub Skokan <jakub.skokan@vpsfree.cz> for purposes of vpsFree.cz" +
        (typeof serverSupportsSSL != 'undefined' && serverSupportsSSL ?
            "\n\n" +
                "This product includes software developed by the OpenSSL Project\n" +
                "for use in the OpenSSL Toolkit. (http://www.openssl.org/)\n" +
                "\n" +
                "This product includes cryptographic software written by " +
                "Eric Young\n(eay@cryptsoft.com)" :
            ""));
};

