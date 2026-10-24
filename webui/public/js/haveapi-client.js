/*! Bundled tslib license:
Copyright (c) Microsoft Corporation.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
*/
;(function(root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof exports === 'object') {
    module.exports = factory();
  } else {
    root.HaveAPI = factory();
  }
}(this, function() {
var haveapiCommonJS = typeof exports === 'object';
var HaveAPI = (function (exports) {

// This file is generated from i18n/haveapi.yml.
// Do not edit it manually; manual changes will be overwritten.
// Update i18n/haveapi.yml and run bundle exec rake i18n:update.

var I18nMessages = {
	  "en": {
	    "authentication": {
	      "callback_failed": "Callback %{callback} failed: %{error}",
	      "callback_invalid_return": "The callback must return an array or 'stop'",
	      "callback_required": "Callback %{callback} must be implemented",
	      "invalid_credentials": "Invalid credentials",
	      "invalid_oauth2_pkce_verifier": "Invalid OAuth2 PKCE verifier",
	      "invalid_oauth2_state": "Invalid OAuth2 state",
	      "mfa_required": "Multi-factor authentication support must be implemented",
	      "multistep_callback_required": "Add a callback to handle multi-step authentication",
	      "oauth2_access_token_required": "The access_token option must be provided",
	      "oauth2_not_configured": "OAuth2 authentication is not configured",
	      "oauth2_revoke_failed": "Unable to revoke access token, HTTP %{status}",
	      "token_request_failed": "Unable to request token: %{message}",
	      "token_revoke_failed": "Unable to revoke token: %{message}",
	      "token_step_failed": "Authentication step '%{action}' failed: %{message}",
	      "unsupported_auth_action": "Unsupported authentication action '%{action}'"
	    },
	    "errors": {
	      "access_forbidden": "Access forbidden.\nBad username or password? Insufficient permissions?",
	      "action_failed": "Action %{action} failed: %{message}",
	      "fatal_api_error": "Fatal API error: %{error}",
	      "input_parameters_not_valid": "Input parameters are not valid",
	      "input_parameters_not_valid_for_action": "Input parameters are not valid for action '%{action}'",
	      "invalid_input_parameters": "Invalid input parameters",
	      "uncancelable_action": "Action with state #%{id} cannot be cancelled",
	      "unresolved_arguments": "Unable to execute action '%{action}': unresolved path arguments"
	    },
	    "validation": {
	      "cannot_be_null": "cannot be null",
	      "invalid_boolean": "not a valid boolean",
	      "invalid_datetime": "not in ISO 8601 format",
	      "invalid_float": "not a valid float",
	      "invalid_input_layout": "invalid input layout",
	      "invalid_integer": "not a valid integer",
	      "invalid_resource_id": "not a valid resource ID",
	      "invalid_string": "not a valid string",
	      "required_parameter_missing": "required parameter is missing",
	      "validation_failed": "validation failed",
	      "validation_failed_with_errors": "validation failed: %{errors}"
	    }
	  },
	  "cs": {
	    "authentication": {
	      "callback_failed": "Callback %{callback} selhal: %{error}",
	      "callback_invalid_return": "Callback musí vrátit pole nebo 'stop'",
	      "callback_required": "Je potřeba implementovat callback %{callback}",
	      "invalid_credentials": "Neplatné přihlašovací údaje",
	      "invalid_oauth2_pkce_verifier": "Neplatný OAuth2 PKCE verifier",
	      "invalid_oauth2_state": "Neplatný parametr OAuth2 state",
	      "mfa_required": "Klient musí implementovat vícefaktorové ověření",
	      "multistep_callback_required": "Je potřeba přidat callback pro zpracování vícefázové autentizace",
	      "oauth2_access_token_required": "Volba access_token musí být zadána",
	      "oauth2_not_configured": "OAuth2 autentizace není nastavena",
	      "oauth2_revoke_failed": "Přístupový token se nepodařilo zneplatnit, HTTP %{status}",
	      "token_request_failed": "Token se nepodařilo vyžádat: %{message}",
	      "token_revoke_failed": "Token se nepodařilo zneplatnit: %{message}",
	      "token_step_failed": "Krok autentizace '%{action}' se nezdařil: %{message}",
	      "unsupported_auth_action": "Nepodporovaná autentizační akce '%{action}'"
	    },
	    "errors": {
	      "access_forbidden": "Přístup odepřen.\nChybné uživatelské jméno nebo heslo? Nedostatečná oprávnění?",
	      "action_failed": "Akce %{action} se nezdařila: %{message}",
	      "fatal_api_error": "Závažná chyba API: %{error}",
	      "input_parameters_not_valid": "Vstupní parametry jsou neplatné",
	      "input_parameters_not_valid_for_action": "Vstupní parametry pro akci '%{action}' jsou neplatné",
	      "invalid_input_parameters": "Neplatné vstupní parametry",
	      "uncancelable_action": "Akci se stavem #%{id} nelze zrušit",
	      "unresolved_arguments": "Akci '%{action}' nelze spustit: chybí argumenty cesty"
	    },
	    "validation": {
	      "cannot_be_null": "nesmí být null",
	      "invalid_boolean": "není platná pravdivostní hodnota",
	      "invalid_datetime": "není ve formátu ISO 8601",
	      "invalid_float": "není platné desetinné číslo",
	      "invalid_input_layout": "neplatná struktura vstupu",
	      "invalid_integer": "není platné celé číslo",
	      "invalid_resource_id": "neplatné ID zdroje",
	      "invalid_string": "není platný řetězec",
	      "required_parameter_missing": "chybí povinný parametr",
	      "validation_failed": "validace selhala",
	      "validation_failed_with_errors": "validace selhala: %{errors}"
	    }
	  }
	};


function normalizeTrustedOrigins(origins, makeError) {
    if (origins === undefined || origins === null)
        return [];
    if (typeof (origins) === 'string')
        origins = [origins];
    if (!Array.isArray(origins))
        throw makeError('Invalid trusted OAuth2 origins');
    return origins.map(function (origin) {
        var parsed;
        if (typeof (origin) !== 'string' || origin.length == 0) {
            throw makeError('Invalid trusted OAuth2 origin');
        }
        if (/[\x00-\x1f\x7f]/.test(origin) || origin.indexOf('\\') != -1) {
            throw makeError('Unsafe trusted OAuth2 origin');
        }
        try {
            parsed = new URL(origin);
        }
        catch (e) {
            throw makeError('Invalid trusted OAuth2 origin');
        }
        if (!parsed.protocol || !parsed.host || parsed.username || parsed.password ||
            (parsed.pathname != '' && parsed.pathname != '/') || parsed.search || parsed.hash) {
            throw makeError('Invalid trusted OAuth2 origin');
        }
        return parsed.origin;
    });
}
function resolveApiUrl(baseUrl, url, opts, makeError) {
    opts = opts || {};
    if (typeof (url) !== 'string' || url.length == 0) {
        throw makeError('Invalid API URL');
    }
    if (/[\x00-\x1f\x7f]/.test(url) || url.indexOf('\\') != -1) {
        throw makeError('Unsafe API URL');
    }
    var base = new URL(baseUrl);
    var resolved;
    if (base.username || base.password) {
        throw makeError('Unsafe API URL origin');
    }
    if (opts.actionPath) {
        if (url[0] != '/' || url[1] == '/' || url.indexOf('@') != -1) {
            throw makeError('Unsafe API action path');
        }
        resolved = new URL((opts.pathMode === 'api' ? baseUrl : base.origin) + url);
    }
    else {
        if (url[0] == '/' && url[1] == '/') {
            throw makeError('Unsafe API URL');
        }
        if (url[0] == '/') {
            resolved = new URL(baseUrl + url);
        }
        else {
            resolved = new URL(url, baseUrl + '/');
        }
    }
    if (resolved.username || resolved.password) {
        throw makeError('Unsafe API URL origin');
    }
    if (resolved.origin != base.origin &&
        (!opts.trustedOrigins || opts.trustedOrigins.indexOf(resolved.origin) == -1)) {
        throw makeError('Unsafe API URL origin');
    }
    return resolved.href;
}
function addParamsToQuery(url, namespace, params, flat, owns) {
    if (!params)
        return url;
    var first = true;
    for (var key in params) {
        if (!(owns ? owns(params, key) : params.hasOwnProperty(key)))
            continue;
        var value = params[key];
        if (value === null) {
            value = '';
        }
        else if (value === undefined) {
            continue;
        }
        if (first) {
            if (url.indexOf('?') == -1)
                url += '?';
            else if (url[url.length - 1] != '&')
                url += '&';
            first = false;
        }
        else
            url += '&';
        url += (flat ? encodeURIComponent(key) : encodeURIComponent(namespace) + '[' + encodeURIComponent(key) + ']') + '=' + encodeURIComponent(value);
    }
    return url;
}

// These four callback-era globals remain observable even when a consumer wraps
// the UMD in strict code. Read their properties live rather than caching values.
// Older browser, worker and Node hosts need no globalThis polyfill.
var legacyGlobals = (typeof globalThis !== 'undefined' ? globalThis :
    typeof window !== 'undefined' ? window :
        typeof self !== 'undefined' ? self : global);

/**
 * @namespace Authentication
 * @memberof HaveAPI.Client
 */
legacyGlobals.Authentication = {
    /**
     * @member {Array} providers An array of registered authentication providers.
     * @memberof HaveAPI.Client.Authentication
     */
    providers: {},
    /**
     * Register authentication providers using this function.
     * @func registerProvider
     * @memberof HaveAPI.Client.Authentication
     * @param {string} name must be the same name as in announced by the API
     * @param {Object} provider class
     */
    registerProvider: function (name, obj) {
        legacyGlobals.Authentication.providers[name] = obj;
    }
};
var authenticationRegistry = legacyGlobals.Authentication;

var I18n = {
    DEFAULT_LOCALE: 'en',
    DEFAULT_LANGUAGE_HEADER: 'Accept-Language',
    translate: function (language, key, values) {
        var message = this.lookup(this.localeFor(language), key) ||
            this.lookup(this.DEFAULT_LOCALE, key) ||
            key;
        values = values || {};
        for (var name in values) {
            if (!values.hasOwnProperty(name))
                continue;
            message = message.replace(new RegExp('%\\{' + name + '\\}', 'g'), String(values[name]));
        }
        return message;
    },
    requestHeaders: function (language, languageHeader) {
        var ret = {};
        if (language === undefined || language === null || String(language) === '')
            return ret;
        languageHeader = languageHeader || this.DEFAULT_LANGUAGE_HEADER;
        this.assertHeaderName(languageHeader);
        this.assertHeaderValue(language);
        ret[languageHeader] = String(language);
        return ret;
    },
    localeFor: function (language) {
        if (language === undefined || language === null || String(language) === '')
            return this.DEFAULT_LOCALE;
        var tags = this.parseAcceptLanguage(String(language));
        for (var i = 0; i < tags.length; i++) {
            var locale = this.normalizeLocale(tags[i]);
            if (locale && I18nMessages.hasOwnProperty(locale))
                return locale;
        }
        return this.DEFAULT_LOCALE;
    },
    assertHeaderName: function (name) {
        if (typeof name !== 'string' || !name.match(/^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/))
            throw new Error('Invalid language HTTP header name');
    },
    assertHeaderValue: function (value) {
        if (typeof value !== 'string' && typeof value !== 'number' && typeof value !== 'boolean')
            throw new Error('Invalid language HTTP header value');
        if (String(value).match(/[\x00\r\n]/))
            throw new Error('Invalid language HTTP header value');
    },
    lookup: function (locale, key) {
        var data = I18nMessages[locale];
        var parts = String(key).replace(/^haveapi_client\./, '').split('.');
        for (var i = 0; i < parts.length; i++) {
            if (!data || typeof data === 'string' || !data.hasOwnProperty(parts[i]))
                return null;
            data = data[parts[i]];
        }
        return typeof data === 'string' ? data : null;
    },
    parseAcceptLanguage: function (header) {
        var ret = [];
        var parts = header.split(',');
        for (var i = 0; i < parts.length; i++) {
            var tokens = parts[i].split(';');
            var tag = tokens.shift().trim();
            var q = 1.0;
            for (var j = 0; j < tokens.length; j++) {
                var qTokens = tokens[j].split('=');
                if (qTokens[0].trim() == 'q')
                    q = parseFloat(qTokens[1]);
            }
            if (tag !== '' && q > 0)
                ret.push([tag, q]);
        }
        ret.sort(function (a, b) {
            return b[1] - a[1];
        });
        return ret.map(function (v) {
            return v[0];
        });
    },
    normalizeLocale: function (tag) {
        var normalized = String(tag).trim().replace(/_/g, '-').replace(/\..*$/, '').toLowerCase();
        if (normalized === '')
            return null;
        return normalized.split('-', 1)[0];
    }
};

/**
 * Create a new client for the API.
 * @class Client
 * @memberof HaveAPI
 * @param {string} url base URL to the API
 * @param {Object} opts
 */
var Client = function Client(url, opts) {
    opts = opts || {};
    var oauth2TrustedOrigins = opts.oauth2TrustedOrigins !== undefined ?
        opts.oauth2TrustedOrigins : opts.oauth2_trusted_origins;
    while (url.length > 0) {
        if (url[url.length - 1] == '/')
            url = url.substr(0, url.length - 1);
        else
            break;
    }
    /**
     * @member {Object} HaveAPI.Client#_private
     * @protected
     */
    this._private = {
        url: url,
        version: (opts !== undefined && opts.version !== undefined) ? opts.version : null,
        description: null,
        attachedResourceNames: Object.create(null),
        debug: (opts !== undefined && opts.debug !== undefined) ? opts.debug : 0,
        oauth2TrustedOrigins: Client.normalizeTrustedOrigins(oauth2TrustedOrigins),
        language: opts.language !== undefined ? opts.language : null,
        languageHeader: opts.languageHeader !== undefined ?
            opts.languageHeader : (opts.language_header || I18n.DEFAULT_LANGUAGE_HEADER),
    };
    I18n.requestHeaders(this._private.language, this._private.languageHeader);
    this._private.hooks = new Client.Hooks(this._private.debug);
    this._private.http = new Client.Http(this._private.debug);
    /**
     * @member {Object} HaveAPI.Client#apiSettings An object containg API settings.
     */
    this.apiSettings = null;
    /**
     * @member {Array} HaveAPI.Client#resources A list of top-level resources attached to the client.
     */
    this.resources = [];
    /**
     * @member {Object} HaveAPI.Client#authProvider Selected authentication provider.
     */
    this.authProvider = new Client.Authentication.Base();
};
/** @constant HaveAPI.Client.Version */
Client.Version = '0.31.1';
/** @constant HaveAPI.Client.ProtocolVersion */
Client.ProtocolVersion = '2.0';
Client.unsafeAttachmentNames = Object.create(null);
Client.unsafeAttachmentNames['__proto__'] = true;
Client.unsafeAttachmentNames['prototype'] = true;
Client.unsafeAttachmentNames['constructor'] = true;
/**
 * @namespace Exceptions
 * @memberof HaveAPI.Client
 */
Client.Exceptions = {};
Client.hasOwn = function (obj, prop) {
    return Object.prototype.hasOwnProperty.call(obj, prop);
};
Client.canAttachDescriptionMember = function (target, name, reservedNames) {
    if (typeof (name) !== 'string')
        return false;
    if (Client.hasOwn(Client.unsafeAttachmentNames, name))
        return false;
    if (reservedNames && Client.hasOwn(reservedNames, name))
        return false;
    return !(name in target);
};
Client.attachDescriptionMember = function (target, name, value, reservedNames) {
    if (!Client.canAttachDescriptionMember(target, name, reservedNames))
        return false;
    target[name] = value;
    return true;
};
Client.findResource = function (root, resourcePath) {
    var current = root;
    var path = [];
    for (var i = 0; i < resourcePath.length; i++) {
        var name = resourcePath[i];
        var found = null;
        path.push(name);
        for (var j = 0; j < current.resources.length; j++) {
            if (current.resources[j].getName() === name) {
                found = current.resources[j];
                break;
            }
        }
        if (found === null) {
            throw new Client.Exceptions.ProtocolError("Associated resource '" + path.join('.') + "' not found");
        }
        current = found;
    }
    return current;
};
Client.normalizeTrustedOrigins = function (origins) {
    return normalizeTrustedOrigins(origins, function (message) { return new Client.Exceptions.ProtocolError(message); });
};
/** Look up canonical names and unambiguous aliases without direct properties. */
Client.findAction = function (resource, name) {
    var index = resource._private.actionIndex;
    if (!index || !Client.hasOwn(index, name))
        throw new Client.Exceptions.ProtocolError("Action '" + name + "' not found or ambiguous");
    return index[name];
};
/**
 * Resolve a URL from an API description and require it to stay on the
 * configured API origin.
 * @method HaveAPI.Client#sameOriginUrl
 * @param {String} url URL or path to resolve
 * @param {Object} opts
 * @return {String} absolute URL
 * @private
 */
Client.prototype.sameOriginUrl = function (url, opts) {
    return resolveApiUrl(this._private.url, url, opts, function (message) { return new Client.Exceptions.ProtocolError(message); });
};
Client.prototype.oauth2Url = function (url) {
    return this.sameOriginUrl(url, {
        trustedOrigins: this._private.oauth2TrustedOrigins
    });
};
/**
 * Set the language sent to the API server.
 * @method HaveAPI.Client#setLanguage
 * @param {String} language value for Accept-Language
 */
Client.prototype.setLanguage = function (language) {
    I18n.requestHeaders(language, this._private.languageHeader);
    this._private.language = language;
};
/**
 * Set the language HTTP header name.
 * @method HaveAPI.Client#setLanguageHeader
 * @param {String} header HTTP header name
 */
Client.prototype.setLanguageHeader = function (header) {
    I18n.assertHeaderName(header);
    this._private.languageHeader = header;
};
Client.prototype.translate = function (key, values) {
    return I18n.translate(this._private.language, key, values);
};
Client.prototype.languageHeaders = function () {
    return I18n.requestHeaders(this._private.language, this._private.languageHeader);
};
Client.prototype.requestHeaders = function (headers) {
    var ret = {};
    var languageHeaders = this.languageHeaders();
    headers = headers || {};
    for (var name in headers) {
        if (headers.hasOwnProperty(name))
            ret[name] = headers[name];
    }
    for (var langName in languageHeaders) {
        if (languageHeaders.hasOwnProperty(langName))
            ret[langName] = languageHeaders[langName];
    }
    return ret;
};
/**
 * @callback HaveAPI.Client~doneCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status true if the task was successful
 */
/**
 * @callback HaveAPI.Client~replyCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 */
/**
 * @callback HaveAPI.Client~versionsCallback
 * @param {HaveAPI.Client} client
 * @param {Boolean} status
 * @param {Object} versions
 */
/**
 * @callback HaveAPI.Client~actionStateCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Response} response
 * @param {HaveAPI.Client.ActionState} state
 */
/**
 * Action call parameters
 * @typedef {Object} HaveAPI.Client~ActionCall
 * @property {Object} params - Input parameters
 * @property {Object} meta - Input meta parameters
 * @property {Boolean} block
 * @property {Integer} blockInterval
 * @property {Integer} blockUpdateIn
 * @property {HaveAPI.Client~replyCallback} onReply - called when the API responds
 * @property {HaveAPI.Client~actionStateCallback} onStateChange - called when the
 *                                                                action's state changes
 * @property {HaveAPI.Client~replyCallback} onDone - called when the blocking action finishes
 */
/**
 * Setup resources and actions as properties and functions.
 * @method HaveAPI.Client#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.setup = function (callback) {
    var that = this;
    this.fetchDescription(function (status, extract) {
        var desc = null;
        try {
            desc = extract.call();
        }
        catch (e) {
            return callback(that, false);
        }
        that._private.description = extract.call();
        that.createSettings();
        that.attachResources();
        callback(that, true);
        that._private.hooks.invoke('after', 'setup', that, true);
    });
};
/**
 * Provide the description and setup the client without asking the API.
 * @method HaveAPI.Client#useDescription
 * @param {Object} description
 */
Client.prototype.useDescription = function (description) {
    this._private.description = description;
    this.createSettings();
    this.attachResources();
};
/**
 * Call a callback with an object with list of available versions
 * and the default one.
 * @method HaveAPI.Client#availableVersions
 * @param {HaveAPI.Client~versionsCallback} callback
 */
Client.prototype.availableVersions = function (callback) {
    var that = this;
    this.fetchDescription(function (status, extract) {
        var versions = null;
        try {
            versions = extract.call();
        }
        catch (e) { }
        callback(that, status && !(versions === null), versions);
    }, '/?describe=versions');
};
/**
 * @callback HaveAPI.Client~isCompatibleCallback
 * @param {mixed} compatible 'compatible', 'imperfect' or false
 */
/**
 * @method HaveAPI.Client#isCompatible
 * @param {HaveAPI.Client~isCompatibleCallback}
 */
Client.prototype.isCompatible = function (callback) {
    var that = this;
    this.fetchDescription(function (status, extract) {
        try {
            extract.call();
            if (that._private.protocolVersion == Client.ProtocolVersion)
                callback('compatible');
            else
                callback('imperfect');
        }
        catch (e) {
            if (e instanceof Client.Exceptions.ProtocolError)
                callback(false);
            else
                throw e;
        }
    }, '/?describe=versions');
};
/**
 * @callback HaveAPI.Client~descriptionCallback
 * @param {Boolean} status true if the description was successfuly fetched
 * @param {function} extract function that attempts to return the description
 */
/**
 * Fetch the description from the API.
 * @method HaveAPI.Client#fetchDescription
 * @private
 * @param {HaveAPI.Client.Http~descriptionCallback} callback
 * @param {String} path server path to query for
 */
Client.prototype.fetchDescription = function (callback, path) {
    var that = this;
    var url = this._private.url;
    if (path === undefined)
        url += (this._private.version ? "/v" + this._private.version + "/" : "/?describe=default");
    else
        url += path;
    this._private.http.request({
        method: 'OPTIONS',
        url: url,
        credentials: this.authProvider.credentials(),
        headers: this.requestHeaders(this.authProvider.headers()),
        queryParameters: this.authProvider.queryParameters(),
        callback: function (status, response) {
            callback(status == 200, function () {
                if (!response)
                    throw new Client.Exceptions.ProtocolError('Failed to fetch the API description');
                if (response.version === undefined) {
                    throw new Client.Exceptions.ProtocolError('Incompatible protocol version: the client uses v' + Client.ProtocolVersion +
                        ' while the API server uses an unspecified version (pre 1.0)');
                }
                that._private.protocolVersion = response.version;
                if (response.version == Client.ProtocolVersion) {
                    return response.response;
                }
                legacyGlobals.v1 = response.version.split('.');
                legacyGlobals.v2 = Client.ProtocolVersion.split('.');
                if (legacyGlobals.v1[0] != legacyGlobals.v2[0]) {
                    throw new Client.Exceptions.ProtocolError('Incompatible protocol version: the client uses v' + Client.ProtocolVersion +
                        ' while the API server uses v' + response.version);
                }
                console.log('WARNING: The client uses protocol v' + Client.ProtocolVersion +
                    ' while the API server uses v' + response.version);
                return response.response;
            });
        }
    });
};
/**
 * Attach API resources from the description to the client.
 * @method HaveAPI.Client#attachResources
 * @private
 */
Client.prototype.attachResources = function () {
    // Detach existing resources
    if (this.resources.length > 0) {
        this.destroyResources();
    }
    this._private.attachedResourceNames = Object.create(null);
    for (var r in this._private.description.resources) {
        if (!Client.hasOwn(this._private.description.resources, r))
            continue;
        if (this._private.debug > 10)
            console.log("Attach resource", r);
        var resource = new Client.Resource(this, null, r, this._private.description.resources[r], []);
        this.resources.push(resource);
        if (Client.attachDescriptionMember(this, r, resource))
            this._private.attachedResourceNames[r] = true;
    }
};
/**
 * Authenticate using selected authentication method.
 * It is possible to avoid calling {@link HaveAPI.Client#setup} before authenticate completely,
 * when it's certain that the client will be used only after it is authenticated. The client
 * will be then set up more efficiently.
 * @method HaveAPI.Client#authenticate
 * @param {string} method name of authentication provider
 * @param {Object} opts a hash of options that is passed to the authentication provider
 * @param {HaveAPI.Client~doneCallback} callback called when the authentication is finished
 * @param {Boolean} reset if false, the client will not be set up again, defaults to true
 */
Client.prototype.authenticate = function (method, opts, callback, reset) {
    var that = this;
    if (reset === undefined)
        reset = true;
    if (!this._private.description) {
        // The client has not yet been setup.
        // Fetch the description, do NOT attach the resources, use it only to authenticate.
        this.fetchDescription(function (status, extract) {
            that._private.description = extract.call();
            that.createSettings();
            that.authenticate(method, opts, callback);
        });
        return;
    }
    this.authProvider = new legacyGlobals.Authentication.providers[method](this, opts, this._private.description.authentication[method]);
    this.authProvider.setup(function (c, status) {
        // Fetch new description, which may be different when authenticated
        if (status && reset) {
            that.setup(function (c2, status2) {
                callback(c2, status2);
                that._private.hooks.invoke('after', 'authenticated', that, true);
            });
        }
        else {
            callback(that, status);
            if (status)
                that._private.hooks.invoke('after', 'authenticated', that, true);
        }
    });
};
/**
 * Logout, destroy the authentication provider.
 * {@link HaveAPI.Client#setup} must be called if you want to use
 * the client again.
 * @method HaveAPI.Client#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.logout = function (callback) {
    var that = this;
    this.authProvider.logout(function () {
        that.authProvider = new Client.Authentication.Base();
        that.destroyResources();
        that._private.description = null;
        if (callback !== undefined)
            callback(that, true);
    });
};
/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#after
 * @param {String} event setup or authenticated
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.after = function (event, callback) {
    this._private.hooks.register('after', event, callback);
};
/**
 * Set member apiSettings.
 * @method HaveAPI.Client#createSettings
 * @private
 */
Client.prototype.createSettings = function () {
    this.apiSettings = {
        meta: this._private.description.meta
    };
};
/**
 * Detach resources from the client.
 * @method HaveAPI.Client#destroyResources
 * @private
 */
Client.prototype.destroyResources = function () {
    while (this.resources.length > 0) {
        var resource = this.resources.shift();
        var name = resource.getName();
        if (this._private.attachedResourceNames[name]
            && this[name] === resource) {
            delete this[name];
        }
    }
    this._private.attachedResourceNames = Object.create(null);
};
/**
 * Return true if the parameters should be sent as a query parameters,
 * which is the case for GET and OPTIONS methods.
 * @method HaveAPI.Client#sendAsQueryParams
 * @param {String} method HTTP method
 * @return {Boolean}
 * @private
 */
Client.prototype.sendAsQueryParams = function (method) {
    return ['GET', 'OPTIONS'].indexOf(method) != -1;
};
/**
 * Add URL encoded parameters to URL.
 * Note that this method does not support object_list or hash_list layouts.
 * @method HaveAPI.Client#addParamsToQuery
 * @param {String} url
 * @param {String} namespace
 * @param {Object} params
 * @private
 */
Client.prototype.addParamsToQuery = function (url, namespace, params, paramDesc) {
    return addParamsToQuery(url, namespace, params);
};

/**
 * @class ActionState
 * @memberof HaveAPI.Client
 */
var ActionState = function ActionState(state) {
    /**
     * @member {Integer} HaveAPI.Client.ActionState#id
     * @readonly
     */
    this.id = state.id;
    /**
     * @member {String} HaveAPI.Client.ActionState#label
     * @readonly
     */
    this.label = state.label;
    /**
     * @member {Boolean} HaveAPI.Client.ActionState#finished
     * @readonly
     */
    this.finished = state.finished;
    /**
     * @member {Boolean} HaveAPI.Client.ActionState#status
     * @readonly
     */
    this.status = state.status;
    /**
     * @member {Date} HaveAPI.Client.ActionState#createdAt
     * @readonly
     */
    this.createdAt = state.created_at && new Date(state.created_at);
    /**
     * @member {Date} HaveAPI.Client.ActionState#updatedAt
     * @readonly
     */
    this.updatedAt = state.updated_at && new Date(state.updated_at);
    /**
     * @member {Boolean} HaveAPI.Client.ActionState#canCancel
     * @readonly
     */
    this.canCancel = state.can_cancel;
    /**
     * @member {HaveAPI.Client.ActionState.Progress} HaveAPI.Client.ActionState#progress
     * @readonly
     */
    this.progress = new ActionState.Progress(state);
};
/**
 * Stop tracking of this action state
 * @method HaveAPI.Client.ActionState#stop
 */
ActionState.prototype.stop = function () {
    this.doStop = true;
};
/**
 * @method HaveAPI.Client.ActionState#shouldStop
 */
ActionState.prototype.shouldStop = function () {
    return this.doStop || false;
};
/**
 * Cancel execution of this action. Action can be cancelled only if
 * {@link HaveAPI.Client.ActionState#canCancel}  is `true`, otherwise exception
 * {@link HaveAPI.Client.Exceptions.UncancelableAction} is thrown.
 *
 * Note that the cancellation can be a blocking action, so you can pass standard callback
 * functions.
 *
 * @method HaveAPI.Client.ActionState#cancel
 * @param {HaveAPI.Client~ActionCall} opts
 */
ActionState.prototype.cancel = function (opts) {
    this.doCancel = true;
    this.cancelOpts = opts;
};
/**
 * @method HaveAPI.Client.ActionState#shouldCancel
 */
ActionState.prototype.shouldCancel = function () {
    return this.doCancel || false;
};
/**
 * @class HaveAPI.Client.ActionState.Progress
 * @memberof HaveAPI.Client.ActionState
 */
ActionState.Progress = function Progress(state) {
    /**
   * @member {Integer} HaveAPI.Client.ActionState.Progress#current
     * @readonly
     */
    this.current = state.current;
    /**
     * @member {Integer} HaveAPI.Client.ActionState.Progress#total
     * @readonly
     */
    this.total = state.total;
    /**
     * @member {String} HaveAPI.Client.ActionState.Progress#unit
     * @readonly
     */
    this.unit = state.unit;
};
/**
 * @method HaveAPI.Client.ActionState.Progress#toString
 * @return {String}
 */
ActionState.Progress.prototype.toString = function () {
    return this.current + "/" + this.total + " " + this.unit;
};

// Constructor/prototype bridges preserve the original callable inheritance model.
/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
var BaseResource = function BaseResource() { };
BaseResource.reservedAttachmentNames = Object.create(null);
BaseResource.reservedAttachmentNames['_private'] = true;
BaseResource.reservedAttachmentNames['resources'] = true;
BaseResource.reservedAttachmentNames['actions'] = true;
BaseResource.reservedAttachmentNames['new'] = true;
/**
 * Attach child resources as properties.
 * @method HaveAPI.Client.BaseResource#attachResources
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachResources = function (description, args) {
    this.resources = [];
    for (var r in description.resources) {
        if (!Client.hasOwn(description.resources, r))
            continue;
        var resource = new Client.Resource(this._private.client, this, r, description.resources[r], args);
        this.resources.push(resource);
        Client.attachDescriptionMember(this, r, resource, BaseResource.reservedAttachmentNames);
    }
};
/**
 * Attach child actions as properties.
 * @method HaveAPI.Client.BaseResource#attachActions
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachActions = function (description, args) {
    this.actions = [];
    var index = Object.create(null);
    var aliases = Object.create(null);
    this._private.actionIndex = index;
    for (var a in description.actions) {
        if (!Client.hasOwn(description.actions, a))
            continue;
        var names = [a].concat(description.actions[a].aliases || []);
        var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);
        index[a] = actionInstance;
        for (var i = 0; i < names.length; i++) {
            Client.attachDescriptionMember(this, names[i], actionInstance, BaseResource.reservedAttachmentNames);
            if (i > 0 && typeof names[i] === 'string') {
                var alias = names[i];
                if (!Client.hasOwn(aliases, alias))
                    aliases[alias] = actionInstance;
                else if (aliases[alias] !== actionInstance)
                    aliases[alias] = null;
            }
        }
        this.actions.push(a);
    }
    for (var alias in aliases) {
        if (!Client.hasOwn(index, alias) && aliases[alias] !== null)
            index[alias] = aliases[alias];
    }
};
/**
 * Return default parameters that are to be sent to the API.
 * Default parameters are overriden by supplied parameters.
 * @method HaveAPI.Client.BaseResource#defaultParams
 * @protected
 * @param {HaveAPI.Client.Action} action
 */
BaseResource.prototype.defaultParams = function (action) {
    return {};
};
/**
 * @method HaveAPI.Client.BaseResource#getName
 * @return {String} resource name
 */
BaseResource.prototype.getName = function () {
    return this._private.name;
};

/**
 * @class ResourceInstance
 * @classdesc Represents an instance of a resource from the API. Attributes
 *            are accessible as properties. Associations are directly accessible.
 * @param {HaveAPI.Client}          client
 * @param {HaveAPI.Client.Action}   action    Action that created this instance.
 * @param {HaveAPI.Client.Response} response  If not provided, the instance is either
 *                                            not resoved or not persistent.
 * @param {Boolean}                 shell     If true, the resource is just a shell,
 *                                            it is to be fetched from the API. Used
 *                                            when accessed as an association from another
 *                                            resource instance.
 * @param {Boolean}                 item      When true, this object was returned in a list,
 *                                            therefore response is not a Response instance,
 *                                            but just an object with parameters.
 * @memberof HaveAPI.Client
 */
var ResourceInstance = function ResourceInstance(client, parent, action, response, shell, item) {
    this._private = {
        client: client,
        parent: parent,
        action: action,
        response: response,
        name: action.resource._private.name,
        description: action.resource._private.description
    };
    if (!response) {
        if (shell !== undefined && shell) { // association that is to be fetched
            this._private.resolved = false;
            this._private.persistent = true;
            var that = this;
            action.directInvoke(function (c, response) {
                var idArgs = ResourceInstance.pathParams(response.meta());
                that.attachResources(that._private.action.resource._private.description, idArgs);
                that.attachActions(that._private.action.resource._private.description, idArgs);
                that.attachAttributes(response.response());
                that._private.resolved = true;
                if (that._private.resolveCallbacks !== undefined) {
                    for (var i = 0; i < that._private.resolveCallbacks.length; i++)
                        that._private.resolveCallbacks[i](that._private.client, that);
                    delete that._private.resolveCallbacks;
                }
            });
        }
        else { // a new, empty instance
            this._private.resolved = true;
            this._private.persistent = false;
            this.attachResources(this._private.action.resource._private.description, action.providedIdArgs);
            this.attachActions(this._private.action.resource._private.description, action.providedIdArgs);
            this.attachStubAttributes();
        }
    }
    else if (item || response.isOk()) {
        this._private.resolved = true;
        this._private.persistent = true;
        var metaNs = client.apiSettings.meta.namespace;
        var idArgs = ResourceInstance.pathParams(item ? response[metaNs] : response.meta());
        this.attachResources(this._private.action.resource._private.description, idArgs);
        this.attachActions(this._private.action.resource._private.description, idArgs);
        this.attachAttributes(item ? response : response.response());
    }
    else ;
};
ResourceInstance.prototype = new BaseResource();
ResourceInstance.pathParams = function (meta) {
    return meta && meta.path_params ? meta.path_params : [];
};
/**
 * @callback HaveAPI.Client.ResourceInstance~resolveCallback
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.ResourceInstance} resource
 */
/**
 * A shortcut to {@link HaveAPI.Client.Response#isOk}.
 * @method HaveAPI.Client.ResourceInstance#isOk
 * @return {Boolean}
 */
ResourceInstance.prototype.isOk = function () {
    return this._private.response.isOk();
};
/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstance#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstance.prototype.apiResponse = function () {
    return this._private.response;
};
/**
 * Save the instance. It calls either an update or a create action,
 * depending on whether the object is persistent or not.
 * @method HaveAPI.Client.ResourceInstance#save
 * @param {HaveAPI.Client~replyCallback} callback
 */
ResourceInstance.prototype.save = function (callback) {
    var that = this;
    function updateAttrs(attrs) {
        for (var attr in attrs) {
            that._private.attributes[attr] = attrs[attr];
        }
    }
    function replyCallback(c, reply) {
        that._private.response = reply;
        updateAttrs(reply);
        if (callback !== undefined)
            callback(c, that);
    }
    if (this._private.persistent) {
        this.update.directInvoke(replyCallback);
    }
    else {
        this.create.directInvoke(function (c, reply) {
            if (reply.isOk())
                that._private.persistent = true;
            replyCallback(c, reply);
        });
    }
};
ResourceInstance.prototype.defaultParams = function (action) {
    legacyGlobals.ret = {};
    for (var attr in this._private.attributes) {
        var desc = action.description.input.parameters[attr];
        if (desc === undefined)
            continue;
        switch (desc.type) {
            case 'Resource':
                legacyGlobals.ret[attr] = this._private.attributes[attr][desc.value_id];
                break;
            default:
                legacyGlobals.ret[attr] = this._private.attributes[attr];
        }
    }
    return legacyGlobals.ret;
};
/**
 * Resolve an associated resource.
 * A shell {@link HaveAPI.Client.ResourceInstance} instance is created
 * and is fetched asynchronously.
 * @method HaveAPI.Client.ResourceInstance#resolveAssociation
 * @private
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstance.prototype.resolveAssociation = function (attr, resourcePath, path) {
    var tmp = Client.findResource(this._private.client, resourcePath);
    var obj = this._private.attributes[attr];
    var metaNs = this._private.client.apiSettings.meta.namespace;
    var meta = (obj[metaNs] || {});
    var action = tmp.show;
    action.provideIdArgs(ResourceInstance.pathParams(meta));
    if (meta.resolved)
        return new Client.ResourceInstance(this._private.client, action.resource._private.parent, action, obj, false, true);
    return new Client.ResourceInstance(this._private.client, action.resource._private.parent, action, null, true);
};
/**
 * Register a callback that will be called then this instance will
 * be fully resolved (fetched from the API).
 * @method HaveAPI.Client.ResourceInstance#whenResolved
 * @param {HaveAPI.Client.ResourceInstance~resolveCallback} callback
 */
ResourceInstance.prototype.whenResolved = function (callback) {
    if (this._private.resolved)
        callback(this._private.client, this);
    else {
        if (this._private.resolveCallbacks === undefined)
            this._private.resolveCallbacks = [];
        this._private.resolveCallbacks.push(callback);
    }
};
/**
 * Attach all attributes as properties.
 * @method HaveAPI.Client.ResourceInstance#attachAttributes
 * @private
 * @param {Object} attrs
 */
ResourceInstance.prototype.attachAttributes = function (attrs) {
    this._private.attributes = attrs;
    this._private.associations = {};
    var metaNs = this._private.client.apiSettings.meta.namespace;
    for (var attr in attrs) {
        if (attr === metaNs)
            continue;
        this.createAttribute(attr, this._private.action.description.output.parameters[attr]);
    }
};
/**
 * Attach all attributes as null properties. Used when creating a new, empty instance.
 * @method HaveAPI.Client.ResourceInstance#attachStubAttributes
 * @private
 */
ResourceInstance.prototype.attachStubAttributes = function () {
    var attrs = {};
    var params = this._private.action.description.input.parameters;
    for (var attr in params) {
        switch (params[attr].type) {
            case 'Resource':
                attrs[attr] = {};
                attrs[attr][params[attr].value_id] = null;
                attrs[attr][params[attr].value_label] = null;
                break;
            default:
                attrs[attr] = null;
        }
    }
    this.attachAttributes(attrs);
};
/**
 * Define getters and setters for an attribute.
 * @method HaveAPI.Client.ResourceInstance#createhAttribute
 * @private
 * @param {String} attr
 * @param {Object} desc
 */
ResourceInstance.prototype.createAttribute = function (attr, desc) {
    var that = this;
    switch (desc.type) {
        case 'Resource':
            Object.defineProperty(this, attr, {
                get: function () {
                    if (that._private.associations.hasOwnProperty(attr))
                        return that._private.associations[attr];
                    return that._private.associations[attr] = that.resolveAssociation(attr, desc.resource, that._private.attributes[attr].path);
                },
                set: function (v) {
                    that._private.attributes[attr][desc.value_id] = v.id;
                    that._private.attributes[attr][desc.value_label] = v[desc.value_label];
                }
            });
            Object.defineProperty(this, attr + '_id', {
                get: function () { return that._private.attributes[attr][desc.value_id]; },
                set: function (v) { that._private.attributes[attr][desc.value_id] = v; }
            });
            break;
        default:
            Object.defineProperty(this, attr, {
                get: function () { return that._private.attributes[attr]; },
                set: function (v) { that._private.attributes[attr] = v; }
            });
    }
};

/**
 * @class Validator
 * @private
 * @param {Function} fn validator function
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 */
var Validator = function Validator(fn, opts, value, params) {
    this.fn = fn;
    this.opts = opts;
    this.value = value;
    this.params = params;
    /**
     * @member {Array} Validator#errors Errors found during the validation.
     */
    this.errors = [];
};
/**
 * @property {Object} Validator.validators Registered validators
 */
Validator.validators = {};
/**
 * Register validator function.
 * @func Validator.register
 * @param {String} name
 * @param {fn} validator function
 */
Validator.register = function (name, fn) {
    Validator.validators[name] = fn;
};
/**
 * Get registered validator using its name.
 * @func Validator.get
 * @param {String} name
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 * @return {Validator}
 */
Validator.get = function (name, opts, value, params) {
    if (!Validator.validators.hasOwnProperty(name))
        return false;
    return new Validator(Validator.validators[name], opts, value, params);
};
/**
 * @method Validator#isValid
 * @return {Boolean}
 */
Validator.prototype.isValid = function () {
    var ret = this.fn(this.opts, this.value, this.params);
    if (ret === true)
        return true;
    if (ret === false) {
        this.errors.push(this.opts.message.replace(/%{value}/g, this.value + ""));
        return false;
    }
    this.errors = this.errors.concat(ret);
    return false;
};

/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
var Parameters = function Parameters(action, params) {
    // Read the optional policy without changing the legacy constructor arity.
    var dictionaryPolicy = arguments[2];
    if (dictionaryPolicy)
        this._dictionaryPolicy = dictionaryPolicy;
    this.action = action;
    this.typeErrors = createDictionary(this);
    this.params = this.coerceParams(params);
    /**
     * @member {Object} Parameters#errors Errors found during the validation.
     */
    this.errors = createDictionary(this);
};
function createDictionary(parameters) {
    return parameters._dictionaryPolicy ? parameters._dictionaryPolicy.create() : {};
}
function owns(parameters, target, key) {
    // Keep receiver-based legacy checks unless this individual operation opts in.
    return parameters._dictionaryPolicy ? parameters._dictionaryPolicy.owns(target, key) : target.hasOwnProperty(key);
}
Parameters.prototype._addTypeError = function (name, msg) {
    if (!owns(this, this.typeErrors, name))
        this.typeErrors[name] = [];
    this.typeErrors[name].push(msg);
};
Parameters.prototype._message = function (key, values) {
    return this.action.client.translate(key, values);
};
function isLeapYear(y) {
    return (y % 4 === 0 && y % 100 !== 0) || (y % 400 === 0);
}
function daysInMonth(y, m) {
    switch (m) {
        case 2:
            return isLeapYear(y) ? 29 : 28;
        case 4:
        case 6:
        case 9:
        case 11:
            return 30;
        default:
            return 31;
    }
}
Parameters.prototype._isIso8601Datetime = function (str) {
    var match = str.match(/^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(?:Z|([+\-])(\d{2}):?(\d{2}))?)?$/);
    if (!match)
        return false;
    var year = parseInt(match[1], 10);
    var month = parseInt(match[2], 10);
    var day = parseInt(match[3], 10);
    if (month < 1 || month > 12)
        return false;
    if (day < 1 || day > daysInMonth(year, month))
        return false;
    if (match[4] !== undefined) {
        var hour = parseInt(match[4], 10);
        var minute = parseInt(match[5], 10);
        var second = match[6] !== undefined ? parseInt(match[6], 10) : 0;
        if (hour < 0 || hour > 23)
            return false;
        if (minute < 0 || minute > 59)
            return false;
        if (second < 0 || second > 59)
            return false;
    }
    if (match[8] !== undefined) {
        var offsetHour = parseInt(match[9], 10);
        var offsetMinute = parseInt(match[10], 10);
        if (offsetHour < 0 || offsetHour > 23)
            return false;
        if (offsetMinute < 0 || offsetMinute > 59)
            return false;
    }
    return true;
};
/**
 * Coerce parameters passed to the action to appropriate types.
 * @method Parameters.coerceParams
 * @param {Object} params
 * @return {Object}
 */
Parameters.prototype.coerceParams = function (params) {
    var ret = createDictionary(this);
    if (this.action.description.input === null)
        return ret;
    var input = this.action.description.input.parameters;
    params = params || {};
    for (var p in params) {
        if (!owns(this, params, p) || !owns(this, input, p))
            continue;
        var v = params[p];
        var desc = input[p];
        if (v === undefined)
            continue;
        if (v === null) {
            if (desc.nullable === true)
                ret[p] = null;
            else
                this._addTypeError(p, this._message('validation.cannot_be_null'));
            continue;
        }
        if (typeof v === 'string' && v.trim() === '' && desc.nullable === true) {
            ret[p] = null;
            continue;
        }
        switch (desc.type) {
            case 'Resource':
                var resourceId = v;
                if (v instanceof ResourceInstance)
                    resourceId = v.id;
                if (typeof resourceId === 'number') {
                    if (isFinite(resourceId) && Math.floor(resourceId) === resourceId)
                        ret[p] = resourceId;
                    else
                        this._addTypeError(p, this._message('validation.invalid_resource_id'));
                }
                else if (typeof resourceId === 'string') {
                    var resourceStr = resourceId.trim();
                    if (resourceStr !== '' && resourceStr.match(/^[+-]?\d+$/))
                        ret[p] = parseInt(resourceStr, 10);
                    else
                        this._addTypeError(p, this._message('validation.invalid_resource_id'));
                }
                else {
                    this._addTypeError(p, this._message('validation.invalid_resource_id'));
                }
                break;
            case 'Integer':
                var intValue;
                if (typeof v === 'number') {
                    if (isFinite(v) && Math.floor(v) === v)
                        intValue = v;
                }
                else if (typeof v === 'string') {
                    var intStr = v.trim();
                    if (intStr !== '' && intStr.match(/^[+-]?\d+$/))
                        intValue = parseInt(intStr, 10);
                }
                if (intValue === undefined)
                    this._addTypeError(p, this._message('validation.invalid_integer'));
                else
                    ret[p] = intValue;
                break;
            case 'Float':
                var floatValue;
                if (typeof v === 'number') {
                    if (isFinite(v))
                        floatValue = v;
                }
                else if (typeof v === 'string') {
                    var floatStr = v.trim();
                    if (floatStr !== '' && floatStr.match(/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/)) {
                        floatValue = parseFloat(floatStr);
                        if (!isFinite(floatValue))
                            floatValue = undefined;
                    }
                }
                if (floatValue === undefined)
                    this._addTypeError(p, this._message('validation.invalid_float'));
                else
                    ret[p] = floatValue;
                break;
            case 'Boolean':
                var boolValue;
                if (typeof v === 'boolean') {
                    boolValue = v;
                }
                else if (typeof v === 'number') {
                    if (v === 0)
                        boolValue = false;
                    else if (v === 1)
                        boolValue = true;
                }
                else if (typeof v === 'string') {
                    var boolStr = v.trim();
                    if (boolStr !== '') {
                        var boolToken = boolStr.toLowerCase();
                        if (boolToken === 'true' || boolToken === 't' || boolToken === 'yes' || boolToken === 'y' || boolToken === '1')
                            boolValue = true;
                        else if (boolToken === 'false' || boolToken === 'f' || boolToken === 'no' || boolToken === 'n' || boolToken === '0')
                            boolValue = false;
                    }
                }
                if (boolValue === undefined)
                    this._addTypeError(p, this._message('validation.invalid_boolean'));
                else
                    ret[p] = boolValue;
                break;
            case 'Datetime':
                var dtValue;
                if (v instanceof Date) {
                    if (!isNaN(v.getTime()))
                        dtValue = v.toISOString();
                }
                else if (typeof v === 'string') {
                    var dtStr = v.trim();
                    if (dtStr !== '' && this._isIso8601Datetime(dtStr))
                        dtValue = dtStr;
                }
                if (dtValue === undefined)
                    this._addTypeError(p, this._message('validation.invalid_datetime'));
                else
                    ret[p] = dtValue;
                break;
            case 'String':
            case 'Text':
                if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean')
                    ret[p] = String(v);
                else
                    this._addTypeError(p, this._message('validation.invalid_string'));
                break;
            default:
                ret[p] = v;
        }
    }
    return ret;
};
/**
 * Validate given input parameters.
 * @method Parameters#validate
 * @return {Boolean}
 */
Parameters.prototype.validate = function () {
    if (this.action.description.input === null)
        return true;
    this.errors = createDictionary(this);
    for (var errName in this.typeErrors) {
        if (!owns(this, this.typeErrors, errName))
            continue;
        this.errors[errName] = this.typeErrors[errName].slice();
    }
    var input = this.action.description.input.parameters;
    for (var name in input) {
        if (!owns(this, input, name))
            continue;
        if (owns(this, this.errors, name))
            continue;
        var p = input[name];
        if (!p.validators)
            continue;
        if (!owns(this, this.params, name) || this.params[name] === undefined || this.params[name] === null) {
            if (p.validators.present)
                this.errors[name] = [this._message('validation.required_parameter_missing')];
            continue;
        }
        for (var validatorName in p.validators) {
            var validator = Validator.get(validatorName, p.validators[validatorName], this.params[name], this.params);
            if (validator === false) {
                console.log("Unsupported validator '" + validatorName + "' for parameter '" + name + "'");
                continue;
            }
            if (!validator.isValid()) {
                if (!owns(this, this.errors, name))
                    this.errors[name] = [];
                this.errors[name] = this.errors[name].concat(validator.errors);
            }
        }
    }
    return Object.keys(this.errors).length ? false : true;
};

/**
 * @class Response
 * @memberof HaveAPI.Client
 */
var Response = function Response(action, response) {
    this.action = action;
    this.envelope = response;
};
/**
 * Returns true if the request was successful.
 * @method HaveAPI.Client.Response#isOk
 * @return {Boolean}
 */
Response.prototype.isOk = function () {
    return this.envelope.status;
};
/**
 * Returns the namespaced response if possible.
 * @method HaveAPI.Client.Response#response
 * @return {Object} response
 */
Response.prototype.response = function () {
    if (!this.action)
        return this.envelope.response;
    if (!this.envelope.response)
        return null;
    switch (this.action.layout('output')) {
        case 'object':
        case 'object_list':
        case 'hash':
        case 'hash_list':
            return this.envelope.response[this.action.namespace('output')];
        default:
            return this.envelope.response;
    }
};
/**
 * Return the error message received from the API.
 * @method HaveAPI.Client.Response#message
 * @return {String}
 */
Response.prototype.message = function () {
    return this.envelope.message;
};
/**
 * Return the global meta data.
 * @method HaveAPI.Client.Response#meta
 * @return {Object}
 */
Response.prototype.meta = function () {
    var metaNs = this.action.client.apiSettings.meta.namespace;
    if (this.envelope.response && this.envelope.response.hasOwnProperty(metaNs))
        return this.envelope.response[metaNs];
    return {};
};

/**
 * @class LocalResponse
 * @memberof HaveAPI.Client
 * @augments HaveAPI.Client.Response
 */
var LocalResponse = function LocalResponse(action, status, message, errors) {
    this.action = action;
    this.envelope = {
        status: status,
        message: message,
        errors: errors,
    };
};
LocalResponse.prototype = new Response();

/**
 * @class Action
 * @memberof HaveAPI.Client
 */
var Action = function Action(client, resource, name, description, args) {
    if (client._private.debug > 10)
        console.log("Attach action", name, "to", resource._private.name);
    this.client = client;
    this.resource = resource;
    this.name = name;
    this.description = description;
    this.args = args || [];
    this.providedIdArgs = [];
    this.preparedPath = null;
    var that = this;
    var fn = function () {
        var new_a = new Action(that.client, that.resource, that.name, that.description, that.args.concat(Array.prototype.slice.call(arguments)));
        return new_a.invoke();
    };
    fn.__proto__ = this;
    return fn;
};
/**
 * Returns action's HTTP method.
 * @method HaveAPI.Client.Action#httpMethod
 * @return {String}
 */
Action.prototype.httpMethod = function () {
    return this.description.method;
};
/**
 * Returns action's namespace.
 * @method HaveAPI.Client.Action#namespace
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.namespace = function (direction) {
    if (this.description[direction])
        return this.description[direction].namespace;
    return null;
};
/**
 * Returns action's layout.
 * @method HaveAPI.Client.Action#layout
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.layout = function (direction) {
    if (this.description[direction])
        return this.description[direction].layout;
    return null;
};
/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#provideIdArgs
 */
Action.prototype.provideIdArgs = function (args) {
    this.providedIdArgs = args || [];
};
/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#providePath
 */
Action.prototype.providePath = function (path) {
    this.preparedPath = path;
};
/**
 * Invoke the action.
 * This method has a variable number of arguments. Arguments are first applied
 * as object IDs in action path. Then there are two ways in which input parameters
 * can and other options be given to the action.
 *
 * The new-style is to pass {@link HaveAPI.Client~ActionCall} object that contains
 * input parameters, meta parameters and callbacks.
 *
 * The old-style, is to pass an object with parameters (meta parameters are passed
 * within this object) and the second argument is {@link HaveAPI.Client~replyCallback}
 * callback function.  The argument with parameters may be omitted if there aren't any,
 * making the callback function the only additional argument.
 *
 * Arguments do not have to be passed to this method specifically. They may
 * be given to the resources above, the only thing that matters is their correct
 * order.
 *
 * @example
 * // Call with parameters and a callback (new-style).
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {
 *   params: {limit: 5},
 *   meta: {count: true},
 *   onReply: function(c, reply) {
 * 		console.log("Got", reply.response());
 *   }
 * });
 *
 * @example
 * // Call with parameters and a callback (old-style).
 * // The first argument '1' is a VPS ID.
 * api.vps.ip_address.list(1, {limit: 5, meta: {count: true}}, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 *
 * @example
 * // Call only with a callback.
 * api.vps.ip_address.list(1, function(c, reply) {
 * 		console.log("Got", reply.response());
 * });
 *
 * @example
 * // Give parameters to resources.
 * api.vps(101).ip_address(33).delete();
 *
 * @method HaveAPI.Client.Action#invoke
 *
 * @example
 * // Calling blocking actions
 * api.vps.restart(101, {
 *   onReply: function (c: Client, reply: Response) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     console.log(
 *       "The action's state has changed, current progress:",
 *       state.progress.toString()
 *     );
 *   },
 *   onDone: function (c: Client, reply: Response) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 * @example
 * // If the API server supports it, blocking actions can be cancelled
 * api.vps.restart(101, {
 *   onReply: function (c: Client, reply: Response) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     if (state.canCancel) {
 *       // Cancel action can be blocking too, depends on the API server
 *       state.cancel({
 *         onReply: function () {},
 *         onStateChange: function () {},
 *         onDone: function () {},
 *       });
 *     }
 *   },
 *   onDone: function (c: Client, reply: Response) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 */
Action.prototype.invoke = function () {
    var prep = this.prepareInvoke(arguments);
    if (!prep.params.validate()) {
        prep.onReply(this.client, new LocalResponse(this, false, this.client.translate('errors.invalid_input_parameters'), prep.params.errors));
        return;
    }
    this.client.invoke(this, Object.assign({}, prep, {
        params: prep.params.params,
    }));
};
/**
 * Same use as {@link HaveAPI.Client.Action#invoke}, except that the callback
 * is always given a {@link HaveAPI.Client.Response} object.
 * @see HaveAPI.Client#directInvoke
 * @method HaveAPI.Client.Action#directInvoke
 */
Action.prototype.directInvoke = function () {
    var prep = this.prepareInvoke(arguments);
    if (!prep.params.validate()) {
        prep.onReply(this.client, new LocalResponse(this, false, this.client.translate('errors.invalid_input_parameters'), prep.params.errors));
        return;
    }
    this.client.directInvoke(this, Object.assign({}, prep, {
        params: prep.params.params
    }));
};
/**
 * Prepare action invocation.
 * @method HaveAPI.Client.Action#prepareInvoke
 * @private
 * @return {Object}
 */
Action.prototype.prepareInvoke = function (new_args) {
    var args = this.args.concat(Array.prototype.slice.call(new_args));
    var rx = /(\{[a-zA-Z0-9\-_]+\})/;
    var preparedPath = this.preparedPath || this.description.path;
    var providedIdArgs = this.providedIdArgs.slice();
    // First, apply ids returned from the API
    for (var i = 0; i < providedIdArgs.length; i++) {
        if (preparedPath.search(rx) == -1)
            break;
        preparedPath = preparedPath.replace(rx, encodeURIComponent(providedIdArgs[i]));
    }
    // Apply ids passed as arguments
    while (args.length > 0) {
        if (preparedPath.search(rx) == -1)
            break;
        var arg = args[0];
        if (typeof (arg) === 'function' || (arg && (arg.params || arg.onReply)))
            break;
        args.shift();
        providedIdArgs.push(arg);
        preparedPath = preparedPath.replace(rx, encodeURIComponent(arg));
    }
    if (preparedPath.search(rx) != -1) {
        console.log("UnresolvedArguments", this.client.translate('errors.unresolved_arguments', { action: this.name }));
        throw new Client.Exceptions.UnresolvedArguments(this);
    }
    var that = this;
    var params = this.prepareParams(args);
    // Add default parameters from object instance
    if (this.layout('input') === 'object') {
        var defaults = this.resource.defaultParams(this);
        for (var param in this.description.input.parameters) {
            if (defaults.hasOwnProperty(param) && (!params.params || (params.params && !params.params.hasOwnProperty(param)))) {
                if (!params.params)
                    params.params = {};
                params.params[param] = defaults[param];
            }
        }
    }
    return Object.assign({}, params, {
        path: preparedPath,
        params: new Parameters(this, params.params),
        onReply: function (c, response) {
            that.preparedPath = null;
            if (params.onReply)
                params.onReply(c, response);
        },
    });
};
/**
 * Determine what kind of a call type was used and return parameters
 * in a unified object.
 * @private
 * @method HaveAPI.Client.Action#prepareParams
 * @param {Array} mix of input parameters and callbacks
 * @return {Object}
 */
Action.prototype.prepareParams = function (args) {
    if (!args.length)
        return {};
    if (args.length == 1 && (args[0].params || args[0].onReply)) {
        // Parameters passed in an object
        return args[0];
    }
    // One parameter is passed, it can be old-style hash of parameters or a callback
    if (args.length == 1) {
        if (typeof (args[0]) === 'function') {
            // The one parameter is a callback -- no input parameters given
            return { onReply: args[0] };
        }
        var params = this.separateMetaParams(args[0]);
        return {
            params: params.params,
            meta: params.meta
        };
    }
    // Two or more parameters are passed. The first is a hash of parameters, the second
    // is a callback. The rest is ignored.
    var params = this.separateMetaParams(args[0]);
    return {
        params: params.params,
        meta: params.meta,
        onReply: args[1]
    };
};
/**
 * Extract meta parameters from `params` and return and object with keys
 * `params` (action's input parameters) and `meta` (action's input meta parameters).
 *
 * @private
 * @method HaveAPI.Client.Action#separateMetaParams
 * @param {Object} action's input parameters, meta parameters may be present
 * @return {Object}
 */
Action.prototype.separateMetaParams = function (params) {
    var ret = {};
    for (var k in params) {
        if (!params.hasOwnProperty(k))
            continue;
        if (k === 'meta') {
            ret.meta = params[k];
        }
        else {
            if (!ret.params)
                ret.params = {};
            ret.params[k] = params[k];
        }
    }
    return ret;
};
/**
 * @function HaveAPI.Client.Action.waitForCompletion
 * @memberof HaveAPI.Client.Action
 * @static
 * @param {Object} opts
 */
Action.waitForCompletion = function (opts) {
    var interval = opts.blockInterval || 15;
    var updateIn = opts.blockUpdateIn || 3;
    var updateState = function (state) {
        if (!opts.onStateChange)
            return;
        opts.onStateChange(opts.client, opts.reply, state);
    };
    var callOnDone = function (reply) {
        if (!opts.onDone)
            return;
        opts.onDone(opts.client, reply || opts.reply);
    };
    var onPoll = function (c, reply) {
        if (!reply.isOk())
            return callOnDone(reply);
        var state = new ActionState(reply.response());
        updateState(state);
        if (state.finished)
            return callOnDone();
        if (state.shouldStop())
            return;
        if (state.shouldCancel()) {
            if (!state.canCancel)
                throw new Client.Exceptions.UncancelableAction(opts.id, opts.client);
            return opts.client.action_state.cancel(opts.id, Object.assign({}, opts, state.cancelOpts));
        }
        opts.client.action_state.poll(opts.id, {
            params: {
                timeout: interval,
                update_in: updateIn,
                current: state.progress.current,
                total: state.progress.total,
                status: state.status
            },
            onReply: onPoll
        });
    };
    opts.client.action_state.show(opts.id, onPoll);
};

/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
var Base = function Base(client, opts, description) { };
authenticationRegistry.Base = Base;
/**
 * Setup the authentication provider and call the callback.
 * @method HaveAPI.Client.Authentication.Base#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Base.prototype.setup = function (callback) { };
/**
 * Logout, destroy all resources and call the callback.
 * @method HaveAPI.Client.Authentication.Base#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Base.prototype.logout = function (callback) {
    callback(this.client, true);
};
/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Base#credentials
 * @return {Object} credentials
 */
Base.prototype.credentials = function () { };
/**
 * Returns an object with HTTP headers to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#headers
 * @return {Object} HTTP headers
 */
Base.prototype.headers = function () { };
/**
 * Returns an object with query parameters to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#queryParameters
 * @return {Object} query parameters
 */
Base.prototype.queryParameters = function () { };

/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
var Basic = function Basic(client, opts, description) {
    this.client = client;
    this.opts = opts;
};
authenticationRegistry.Basic = Basic;
Basic.prototype = new authenticationRegistry.Base();
/**
 * @method HaveAPI.Client.Authentication.Basic#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Basic.prototype.setup = function (callback) {
    if (callback !== undefined)
        callback(this.client, true);
};
/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Basic#credentials
 * @return {Object} credentials
 */
Basic.prototype.credentials = function () {
    return this.opts;
};

// Keep the existing browser/CommonJS selection. The dependency remains inside
// this branch so browser script loading never requires a module loader.
var XMLHttpRequest;
if (haveapiCommonJS && (typeof window === 'undefined' || !window.XMLHttpRequest)) {
    XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest;
}
else {
    XMLHttpRequest = window.XMLHttpRequest;
}

/**
 * @class OAuth2
 * @classdesc OAuth2 authentication provider.
 *            This provider can only use existing access tokens, it does not have
 *            the ability to request authorization on its own.
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.OAuth2~Options} opts
 * @param {Object} description
 * @memberof HaveAPI.Client.Authentication
 */
var OAuth2 = function OAuth2(client, opts, description) {
    this.client = client;
    this.opts = opts;
    this.description = description;
    /**
     * @member {String} HaveAPI.Client.Authentication.OAuth2#access_token Access and refresh tokens
     */
    this.access_token = null;
};
authenticationRegistry.OAuth2 = OAuth2;
OAuth2.prototype = new authenticationRegistry.Base();
/**
 * OAuth2 authentication options
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~Options
 * @property {HaveAPI.Client.Authentication.OAuth2~AccessTopen} access_token
 */
/**
 * Access token
 *
 * @typedef {Object} HaveAPI.Client.Authentication.OAuth2~AccessToken
 * @property {String} access_token
 * @property {String} refresh_token
 * @property {Integer} expires
 */
/**
 * @method HaveAPI.Client.Authentication.OAuth2#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
OAuth2.prototype.setup = function (callback) {
    if (this.opts.hasOwnProperty('access_token')) {
        this.access_token = this.opts.access_token;
        if (callback !== undefined)
            callback(this.client, true);
    }
    else {
        throw this.client.translate('authentication.oauth2_access_token_required');
    }
};
/**
 * @method HaveAPI.Client.Authentication.OAuth2#headers
 */
OAuth2.prototype.headers = function () {
    var ret = {};
    // We send the token through the HaveAPI-speficic HTTP header, because
    // the Authorization header is not allowed by the server's CORS policy.
    ret[this.description.http_header] = this.access_token.access_token;
    return ret;
};
/**
 * @method HaveAPI.Client.Authentication.OAuth2#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
OAuth2.prototype.logout = function (callback) {
    var http = new XMLHttpRequest();
    var that = this;
    var revokeUrl = this.client.oauth2Url(this.description.revoke_url);
    http.open('POST', revokeUrl, true);
    http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
    var headers = this.client.requestHeaders({});
    for (var name in headers) {
        if (headers.hasOwnProperty(name))
            http.setRequestHeader(name, headers[name]);
    }
    http.onreadystatechange = function () {
        if (http.readyState == 4) {
            callback(that.client, http.status == 200);
        }
    };
    http.send("token=" + encodeURIComponent(this.access_token.access_token));
};

/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.Token~Options} opts
 * @param {Object} description
 */
var Token = function Token(client, opts, description) {
    this.client = client;
    this.opts = opts;
    this.description = description;
    this.configured = false;
    /**
     * @member {String} HaveAPI.Client.Authentication.Token#token The token received from the API.
     */
    this.token = null;
};
authenticationRegistry.Token = Token;
Token.prototype = new authenticationRegistry.Base();
/**
 * Token authentication options
 *
 * In addition to the options below, it accepts also input credentials
 * based on the API server the client is connected to, i.e. usually `user`
 * and `password`.
 * @typedef {Object} HaveAPI.Client.Authentication.Token~Options
 * @property {String} lifetime
 * @property {Integer} interval
 * @property {HaveAPI.Client.Authentication.Token~authenticationCallback} callback
 */
/**
 * This callback is invoked if the API server requires multi-step authentication
 * process. The function has to return input parameters for the next
 * authentication action, or invoke a callback passed as an argument.
 * @callback HaveAPI.Client.Authentication.Token~authenticationCallback
 * @param {String} action action name
 * @param {Object} params input parameters and their description
 * @param {HaveAPI.Client.Authentication.Token~continueCallback} cont
 * @return {Object} input parameters to send to the API
 * @return {null} the callback function will be invoked
 */
/**
 * @callback HaveAPI.Client.Authentication.Token~continueCallback
 * @param {Object} input input parameters to send to the API
 */
/**
 * @method HaveAPI.Client.Authentication.Token#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.setup = function (callback) {
    this.resource = new Client.Resource(this.client, null, 'token', this.description.resources.token, []);
    if (this.opts.hasOwnProperty('token')) {
        this.token = this.opts.token;
        this.validTo = this.opts.validTo;
        this.configured = true;
        if (callback !== undefined)
            callback(this.client, true);
    }
    else {
        this.requestToken(callback);
    }
};
/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.requestToken = function (callback) {
    var that = this;
    var input = {
        lifetime: this.opts.lifetime || 'renewable_auto'
    };
    if (this.opts.interval !== undefined)
        input.interval = this.opts.interval;
    this.getRequestCredentials().forEach(function (param) {
        if (that.opts[param] !== undefined)
            input[param] = that.opts[param];
    });
    this.authenticationStep('request', input, callback);
};
/**
 * @method HaveAPI.Client.Authentication.Token#authenticationStep
 * @param {String} action action name
 * @param {Object} input input parameters
 * @param {HaveAPI.Client~doneCallback} callback
 * @private
 */
Token.prototype.authenticationStep = function (action, input, callback) {
    var that = this;
    this.resource[action](input, function (c, response) {
        if (response.isOk()) {
            var t = response.response();
            if (t.complete) {
                that.token = t.token;
                that.validTo = t.valid_to;
                that.configured = true;
                if (callback !== undefined)
                    callback(that.client, true);
            }
            else {
                if (that.opts.callback === undefined)
                    throw that.client.translate('authentication.mfa_required');
                var cont = function (input) {
                    that.authenticationStep(t.next_action, Object.assign({}, input, { token: t.token }), callback);
                };
                var ret = that.opts.callback(t.next_action, that.getCustomActionCredentials(t.next_action), cont);
                if (typeof ret === 'object' && ret !== null)
                    cont(ret);
            }
        }
        else {
            if (callback !== undefined)
                callback(that.client, false);
        }
    });
};
/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.renewToken = function (callback) {
    var that = this;
    this.resource.renew(function (c, response) {
        if (response.isOk()) {
            var t = response.response();
            that.validTo = t.valid_to;
            if (callback !== undefined)
                callback(that.client, true);
        }
        else {
            if (callback !== undefined)
                callback(that.client, false);
        }
    });
};
/**
 * @method HaveAPI.Client.Authentication.Token#headers
 */
Token.prototype.headers = function () {
    if (!this.configured)
        return;
    var ret = {};
    ret[this.description.http_header] = this.token;
    return ret;
};
/**
 * @method HaveAPI.Client.Authentication.Token#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Token.prototype.logout = function (callback) {
    this.resource.revoke(null, function (c, reply) {
        // Keep the callback's original unbound receiver semantics.
        callback(this.client, reply.isOk());
    });
};
/**
 * Return names of parameters used as credentials for custom authentication
 * @method HaveAPI.Client.Authentication.Token#getRequestCredentials
 * @private
 * @return {Array}
 */
Token.prototype.getRequestCredentials = function () {
    var ret = [];
    for (var param in this.resource.request.description.input.parameters) {
        if (param != "lifetime" && param != "interval")
            ret.push(param);
    }
    return ret;
};
/**
 * Return names of parameters used as credentials for custom authentication
 * action
 * @method HaveAPI.Client.Authentication.Token#getCustomActionCredentials
 * @private
 * @return {Array}
 */
Token.prototype.getCustomActionCredentials = function (action) {
    var ret = {};
    var desc = this.resource[action].description.input.parameters;
    for (var param in desc) {
        if (param != "token")
            ret[param] = desc[param];
    }
    return ret;
};

/**
 * @class Hooks
 * @memberof HaveAPI.Client
 */
var Hooks = function Hooks(debug) {
    this.debug = debug;
    this.hooks = {};
};
/**
 * Register a callback for particular event.
 * @method HaveAPI.Client.Hooks#register
 * @param {String} type
 * @param {String} event
 * @param {HaveAPI.Client~doneCallback} callback
 */
Hooks.prototype.register = function (type, event, callback) {
    if (this.debug > 9)
        console.log("Register callback", type, event);
    if (this.hooks[type] === undefined)
        this.hooks[type] = {};
    if (this.hooks[type][event] === undefined) {
        if (this.debug > 9)
            console.log("The event has not occurred yet");
        this.hooks[type][event] = {
            done: false,
            arguments: [],
            callables: [callback]
        };
        return;
    }
    if (this.hooks[type][event].done) {
        if (this.debug > 9)
            console.log("The event has already happened, invoking now");
        // Legacy apply uses the saved array as receiver, with no callback arguments.
        callback.apply(this.hooks[type][event].arguments);
        return;
    }
    if (this.debug > 9)
        console.log("The event has not occurred yet, enqueue");
    this.hooks[type][event].callables.push(callback);
};
/**
 * Invoke registered callbacks for a particular event. Callback arguments
 * follow after the two stationary arguments.
 * @method HaveAPI.Client.Hooks#invoke
 * @param {String} type
 * @param {String} event
 */
Hooks.prototype.invoke = function (type, event) {
    var callbackArgs = [];
    if (arguments.length > 2) {
        for (var i = 2; i < arguments.length; i++)
            callbackArgs.push(arguments[i]);
    }
    if (this.debug > 9)
        console.log("Invoke callback", type, event, callbackArgs);
    if (this.hooks[type] === undefined)
        this.hooks[type] = {};
    if (this.hooks[type][event] === undefined) {
        this.hooks[type][event] = {
            done: true,
            arguments: callbackArgs,
            callables: []
        };
        return;
    }
    this.hooks[type][event].done = true;
    var callables = this.hooks[type][event].callables;
    for (var i = 0; i < callables.length;) {
        callables.shift().apply(callbackArgs);
    }
};

/** No Promise or new error policy is imposed on the callback transport. */
function openRequest(opts) {
    var request = new XMLHttpRequest();
    if (opts.credentials === undefined)
        request.open(opts.method, opts.url);
    else
        request.open(opts.method, opts.url, true, opts.credentials.user, opts.credentials.password);
    for (var header in opts.headers)
        request.setRequestHeader(header, opts.headers[header]);
    if (opts.params !== undefined)
        request.setRequestHeader('Content-Type', 'application/json; charset=utf-8');
    return request;
}
function sendRequest(request, opts) {
    if (opts.params !== undefined)
        request.send(JSON.stringify(opts.params));
    else
        request.send();
}

/**
 * @class Http
 * @memberof HaveAPI.Client
 */
var Http = function Http(debug) {
    this.debug = debug;
};
/**
 * @callback HaveAPI.Client.Http~replyCallback
 * @param {Integer} status received HTTP status code
 * @param {Object} response received response
 */
/**
 * @method HaveAPI.Client.Http#request
 */
Http.prototype.request = function (opts) {
    if (this.debug > 5)
        console.log("Request to " + opts.method + " " + opts.url);
    var r = openRequest(opts);
    r.onreadystatechange = function () {
        var state = r.readyState;
        if (this.debug > 6)
            console.log('Request state is ' + state);
        if (state == 4 && opts.callback !== undefined) {
            var json = null;
            try {
                json = JSON.parse(r.responseText);
            }
            catch (e) {
                console.log('JSON.parse failed', e);
            }
            if (json)
                opts.callback(r.status, json);
            else
                opts.callback(false, undefined);
        }
    };
    sendRequest(r, opts);
};

/**
 * @class Resource
 * @memberof HaveAPI.Client
 */
var Resource = function Resource(client, parent, name, description, args) {
    this._private = {
        client: client,
        parent: parent,
        name: name,
        description: description,
        args: args
    };
    this.attachResources(description, args);
    this.attachActions(description, args);
    var that = this;
    var fn = function () {
        return new Resource(that._private.client, that._private.parent, that._private.name, that._private.description, that._private.args.concat(Array.prototype.slice.call(arguments)));
    };
    fn.__proto__ = this;
    return fn;
};
Resource.prototype = new BaseResource();
// Unused
Resource.prototype.applyArguments = function (args) {
    for (var i = 0; i < args.length; i++) {
        this._private.args.push(args[i]);
    }
    return this;
};
/**
 * Return a new, empty resource instance.
 * @method HaveAPI.Client.Resource#new
 * @return {HaveAPI.Client.ResourceInstance} resource instance
 */
Resource.prototype.new = function () {
    // Preserve the legacy helper's direct-property lookup, including absent fields.
    var legacy = this;
    return new Client.ResourceInstance(legacy.client, legacy.parent, legacy.create, null, false);
};

/**
 * Arguments are the same as for {@link HaveAPI.Client.ResourceInstance}.
 * @class ResourceInstanceList
 * @classdesc Represents a list of {@link HaveAPI.Client.ResourceInstance} objects.
 * @see {@link HaveAPI.Client.ResourceInstance}
 * @memberof HaveAPI.Client
 */
var ResourceInstanceList = function ResourceInstanceList(client, action, response) {
    this.response = response;
    /**
     * @member {Array} HaveAPI.Client.ResourceInstanceList#items An array containg all items.
     */
    this.items = [];
    var ret = response.response();
    /**
     * @member {integer} HaveAPI.Client.ResourceInstanceList#length Number of items in the list.
     */
    this.length = ret ? ret.length : 0;
    /**
     * @member {integer} HaveAPI.Client.ResourceInstanceList#totalCount Total number of items available.
     */
    this.totalCount = response.meta().total_count;
    for (var i = 0; i < this.length; i++)
        this.items.push(new Client.ResourceInstance(client, action.resource._private.parent, action, ret[i], false, true));
};
/**
 * @callback HaveAPI.Client.ResourceInstanceList~iteratorCallback
 * @param {HaveAPI.Client.ResourceInstance} object
 */
/**
 * A shortcut to {@link HaveAPI.Client.Response#isOk}.
 * @method HaveAPI.Client.ResourceInstanceList#isOk
 * @return {Boolean}
 */
ResourceInstanceList.prototype.isOk = function () {
    return this.response.isOk();
};
/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstanceList#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstanceList.prototype.apiResponse = function () {
    return this.response;
};
/**
 * Call fn for every item in the list.
 * @param {HaveAPI.Client.ResourceInstanceList~iteratorCallback} fn
 * @method HaveAPI.Client.ResourceInstanceList#each
 */
ResourceInstanceList.prototype.each = function (fn) {
    for (var i = 0; i < this.length; i++)
        fn(this.items[i]);
};
/**
 * Return item at index.
 * @method HaveAPI.Client.ResourceInstanceList#itemAt
 * @param {Integer} index
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.itemAt = function (index) {
    return this.items[index];
};
/**
 * Return first item.
 * @method HaveAPI.Client.ResourceInstanceList#first
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.first = function () {
    if (this.length == 0)
        return null;
    return this.items[0];
};
/**
 * Return last item.
 * @method HaveAPI.Client.ResourceInstanceList#last
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.last = function () {
    if (this.length == 0)
        return null;
    return this.items[this.length - 1];
};

/**
 * Always calls the callback with {@link HaveAPI.Client.Response} object. It does
 * not interpret the response.
 * @method HaveAPI.Client#directInvoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.directInvoke = function (action, opts) {
    var path = opts.path === undefined ? action.preparedPath : opts.path;
    if (this._private.debug > 5)
        console.log("Executing", action, "with opts", opts, "at", path);
    var that = this;
    opts.block === undefined ? true : opts.block;
    var url = this.sameOriginUrl(path, { actionPath: true });
    var httpOpts = {
        method: action.httpMethod(),
        url: url,
        credentials: this.authProvider.credentials(),
        headers: this.requestHeaders(this.authProvider.headers()),
        queryParameters: this.authProvider.queryParameters(),
        callback: function (status, response) {
            var res = new Client.Response(action, response);
            if (opts.onReply !== undefined)
                opts.onReply(that, res);
            if (action.description.blocking && res.meta().action_state_id && opts.block) {
                if (opts.onStateChange || opts.onDone) {
                    Action.waitForCompletion({
                        id: res.meta().action_state_id,
                        client: that,
                        reply: res,
                        blockInterval: opts.blockInterval,
                        blockUpdateIn: opts.blockUpdateIn,
                        onStateChange: opts.onStateChange,
                        onDone: opts.onDone
                    });
                }
            }
        }
    };
    var paramsInQuery = this.sendAsQueryParams(httpOpts.method);
    var metaNs = this.apiSettings.meta.namespace;
    if (paramsInQuery) {
        httpOpts.url = this.addParamsToQuery(httpOpts.url, action.namespace('input'), opts.params, action.description.input ? action.description.input.parameters : null);
        if (opts.meta) {
            httpOpts.url = this.addParamsToQuery(httpOpts.url, metaNs, opts.meta);
        }
    }
    else {
        var scopedParams = {};
        var ns = action.namespace('input');
        if (ns)
            scopedParams[ns] = opts.params;
        if (opts.meta)
            scopedParams[metaNs] = opts.meta;
        httpOpts.params = scopedParams;
    }
    try {
        this._private.http.request(httpOpts);
    }
    finally {
        action.preparedPath = null;
    }
};
/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#invoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.invoke = function (action, opts) {
    var that = this;
    var origOnReply = opts.onReply;
    var origOnBlock = opts.block === undefined ? true : opts.block;
    opts.onReply = function (status, response) {
        if (!origOnReply && (!action.description.blocking || (!opts.onStateUpdate && !opts.onDone)))
            return;
        var responseObject;
        switch (action.layout('output')) {
            case 'object':
                responseObject = new Client.ResourceInstance(that, action.resource._private.parent, action, response);
                break;
            case 'object_list':
                responseObject = new Client.ResourceInstanceList(that, action, response);
                break;
            default:
                responseObject = response;
        }
        if (origOnReply)
            origOnReply(that, responseObject);
        if (action.description.blocking && response.meta().action_state_id && origOnBlock) {
            if (opts.onStateChange || opts.onDone) {
                Action.waitForCompletion({
                    id: response.meta().action_state_id,
                    client: that,
                    reply: responseObject,
                    blockInterval: opts.blockInterval,
                    blockUpdateIn: opts.blockUpdateIn,
                    onStateChange: opts.onStateChange,
                    onDone: opts.onDone
                });
            }
        }
    };
    opts.block = false;
    this.directInvoke(action, opts);
};

/** These intentionally retain the legacy plain exception prototypes. */
Client.Exceptions.ProtocolError = function (msg) {
    this.name = 'ProtocolError';
    this.message = msg;
};
Client.Exceptions.UnresolvedArguments = function (action) {
    this.name = 'UnresolvedArguments';
    this.message = action.client.translate('errors.unresolved_arguments', {
        action: action.name
    });
};
Client.Exceptions.UncancelableAction = function (stateId, client) {
    this.name = 'UncancelableAction';
    this.message = client.translate('errors.uncancelable_action', { id: stateId });
};

Validator.validators.accept = function (opts, value) {
    return opts.value === value;
};

Validator.validators.confirm = function (opts, value, params) {
    var cond = value === params[opts.parameter];
    return opts.equal ? cond : !cond;
};

Validator.validators.custom = function () {
    return true;
};

Validator.validators.exclude = function (opts, value) {
    if (opts.values instanceof Array)
        return opts.values.indexOf(value) === -1;
    return !opts.values.hasOwnProperty(value);
};

Validator.validators.format = function (opts, value) {
    if (typeof value != 'string')
        return false;
    var rx = new RegExp(opts.rx);
    if (opts.match)
        return value.match(rx) ? true : false;
    return value.match(rx) ? false : true;
};

Validator.validators.include = function (opts, value) {
    if (opts.values instanceof Array)
        return !(opts.values.indexOf(value) === -1);
    return opts.values.hasOwnProperty(value);
};

Validator.validators.length = function (opts, value) {
    if (typeof value != 'string')
        return false;
    var len = value.length;
    if (typeof opts.equals === 'number')
        return len === opts.equals;
    if (typeof opts.min === 'number' && !(typeof opts.max === 'number'))
        return len >= opts.min;
    if (!(typeof opts.min === 'number') && typeof opts.max === 'number')
        return len <= opts.max;
    return len >= opts.min && len <= opts.max;
};

Validator.validators.number = function (opts, value) {
    var v = (typeof value === 'string') ? parseInt(value) : value;
    if (typeof opts.min === 'number' && v < opts.min)
        return false;
    if (typeof opts.max === 'number' && v > opts.max)
        return false;
    if (typeof opts.step === 'number') {
        if ((v - (typeof opts.min === 'number' ? opts.min : 0)) % opts.step > 0)
            return false;
    }
    if (typeof opts.mod === 'number' && !(v % opts.mod === 0))
        return false;
    if (typeof opts.odd === 'number' && v % 2 === 0)
        return false;
    if (typeof opts.even === 'number' && v % 2 > 0)
        return false;
    return true;
};

Validator.validators.present = function (opts, value) {
    if (value === undefined)
        return false;
    if (!opts.empty && typeof value === 'string' && !value.trim().length)
        return false;
    return true;
};

/******************************************************************************
Copyright (c) Microsoft Corporation.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
***************************************************************************** */
/* global Reflect, Promise, SuppressedError, Symbol, Iterator */

var extendStatics = function(d, b) {
  extendStatics = Object.setPrototypeOf ||
      ({ __proto__: [] } instanceof Array && function (d, b) { d.__proto__ = b; }) ||
      function (d, b) { for (var p in b) if (Object.prototype.hasOwnProperty.call(b, p)) d[p] = b[p]; };
  return extendStatics(d, b);
};

function __extends(d, b) {
  if (typeof b !== "function" && b !== null)
      throw new TypeError("Class extends value " + String(b) + " is not a constructor or null");
  extendStatics(d, b);
  function __() { this.constructor = d; }
  d.prototype = b === null ? Object.create(b) : (__.prototype = b.prototype, new __());
}

var __assign = function() {
  __assign = Object.assign || function __assign(t) {
      for (var s, i = 1, n = arguments.length; i < n; i++) {
          s = arguments[i];
          for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p)) t[p] = s[p];
      }
      return t;
  };
  return __assign.apply(this, arguments);
};

function __awaiter(thisArg, _arguments, P, generator) {
  function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
  return new (P || (P = Promise))(function (resolve, reject) {
      function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
      function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
      function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
      step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
}

function __generator(thisArg, body) {
  var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g = Object.create((typeof Iterator === "function" ? Iterator : Object).prototype);
  return g.next = verb(0), g["throw"] = verb(1), g["return"] = verb(2), typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
  function verb(n) { return function (v) { return step([n, v]); }; }
  function step(op) {
      if (f) throw new TypeError("Generator is already executing.");
      while (g && (g = 0, op[0] && (_ = 0)), _) try {
          if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
          if (y = 0, t) op = [op[0] & 2, t.value];
          switch (op[0]) {
              case 0: case 1: t = op; break;
              case 4: _.label++; return { value: op[1], done: false };
              case 5: _.label++; y = op[1]; op = [0]; continue;
              case 7: op = _.ops.pop(); _.trys.pop(); continue;
              default:
                  if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                  if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                  if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                  if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                  if (t[2]) _.ops.pop();
                  _.trys.pop(); continue;
          }
          op = body.call(thisArg, _);
      } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
      if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
  }
}

typeof SuppressedError === "function" ? SuppressedError : function (error, suppressed, message) {
  var e = new Error(message);
  return e.name = "SuppressedError", e.error = error, e.suppressed = suppressed, e;
};

var AsyncError = /** @class */ (function (_super) {
    __extends(AsyncError, _super);
    function AsyncError(kind, message, details) {
        if (details === void 0) { details = {}; }
        var _this = _super.call(this, message) || this;
        Object.setPrototypeOf(_this, AsyncError.prototype);
        _this.name = kind === 'aborted' ? 'AbortError' : 'AsyncError';
        _this.kind = kind;
        // Only supported diagnostic fields are copied; request credentials never are.
        ['httpStatus', 'response', 'envelope', 'errors', 'state', 'cause', 'reason'].forEach(function (key) {
            if (Object.prototype.hasOwnProperty.call(details, key))
                Object.defineProperty(_this, key, { value: details[key], writable: true, enumerable: true, configurable: true });
        });
        return _this;
    }
    return AsyncError;
}(Error));
function asAsyncError(error, kind) {
    if (kind === void 0) { kind = 'protocol'; }
    return error instanceof AsyncError ? error : new AsyncError(kind, error instanceof Error ? error.message : String(error), { cause: error });
}

function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function own(value, key) {
    return Object.prototype.hasOwnProperty.call(value, key);
}
function isApiErrors(value) {
    return isRecord(value) && Object.keys(value).every(function (key) {
        var errors = value[key];
        return Array.isArray(errors) ? errors.every(function (message) { return typeof message === 'string'; }) : isApiErrors(errors);
    });
}
function mergeHeaders() {
    var sources = [];
    for (var _i = 0; _i < arguments.length; _i++) {
        sources[_i] = arguments[_i];
    }
    var result = Object.create(null);
    sources.forEach(function (source) { return Object.keys(source || {}).forEach(function (name) {
        I18n.assertHeaderName(name);
        var value = source[name];
        I18n.assertHeaderValue(value);
        Object.keys(result).forEach(function (previous) {
            if (previous.toLowerCase() === name.toLowerCase())
                delete result[previous];
        });
        result[name] = String(value);
    }); });
    return result;
}
function prepare(spec, context) {
    var _a;
    if (!spec || typeof spec.method !== 'string' || !/^[A-Za-z]+$/.test(spec.method))
        throw new AsyncError('validation', 'Invalid HTTP method');
    if (spec.timeoutMs !== undefined && (!Number.isFinite(spec.timeoutMs) || spec.timeoutMs <= 0))
        throw new AsyncError('validation', 'Request timeout must be positive');
    if (spec.params !== undefined && !isRecord(spec.params) || spec.meta !== undefined && !isRecord(spec.meta))
        throw new AsyncError('validation', 'Request parameters and metadata must be objects');
    var method = spec.method.toUpperCase();
    var metaNamespace = spec.metaNamespace === undefined ? context.metaNamespace : spec.metaNamespace;
    if (typeof metaNamespace !== 'string' || !metaNamespace ||
        (spec.inputNamespace != null && (typeof spec.inputNamespace !== 'string' || !spec.inputNamespace)) ||
        (spec.outputNamespace != null && (typeof spec.outputNamespace !== 'string' || !spec.outputNamespace)))
        throw new AsyncError('validation', 'Invalid parameter namespace');
    var url = resolveApiUrl(context.baseUrl, spec.path, { actionPath: true, pathMode: context.pathMode || 'api' }, function (message) { return new AsyncError('protocol', message); });
    var headers;
    try {
        headers = mergeHeaders({ Accept: 'application/json' }, context.headers, I18n.requestHeaders(context.language, context.languageHeader), spec.headers);
    }
    catch (cause) {
        throw new AsyncError('validation', 'Invalid HTTP header', { cause: cause });
    }
    var http = {
        method: method,
        url: url,
        credentials: context.credentials,
        headers: headers
    };
    if (method === 'GET' || method === 'OPTIONS') {
        url = addParamsToQuery(url, spec.inputNamespace || null, spec.params, spec.inputNamespace == null, own);
        if (spec.meta)
            url = addParamsToQuery(url, metaNamespace, spec.meta, false, own);
        http.url = url;
    }
    else {
        var body = spec.inputNamespace == null ? Object.assign(Object.create(null), spec.params) : (_a = {}, _a[spec.inputNamespace] = spec.params || {}, _a);
        if (spec.meta)
            body[metaNamespace] = spec.meta;
        http.params = body;
    }
    return { http: http, metaNamespace: metaNamespace };
}
function decode(status, text, namespace, metaNamespace) {
    var parsed;
    try {
        parsed = JSON.parse(text);
    }
    catch (cause) {
        throw new AsyncError('protocol', 'Invalid JSON response', { httpStatus: status, cause: cause });
    }
    if (!isRecord(parsed) || typeof parsed.status !== 'boolean' ||
        (parsed.message != null && typeof parsed.message !== 'string') ||
        (parsed.errors != null && !isApiErrors(parsed.errors)))
        throw new AsyncError('protocol', 'Invalid API response envelope', { httpStatus: status });
    var envelope = parsed;
    var data = envelope.response;
    var meta = {};
    // Keep the validated envelope receipt even if its payload cannot be decoded.
    var result = { data: data, meta: meta, envelope: envelope, httpStatus: status };
    if (isRecord(data) && own(data, metaNamespace)) {
        if (!isRecord(data[metaNamespace]))
            throw new AsyncError('protocol', 'Invalid response metadata', { httpStatus: status, envelope: envelope, response: result });
        meta = data[metaNamespace];
        result.meta = meta;
    }
    if (status < 200 || status >= 300 || !envelope.status)
        throw new AsyncError('api', envelope.message || 'API request failed', __assign({ httpStatus: status, envelope: envelope, response: result }, (envelope.errors ? { errors: envelope.errors } : {})));
    if (!own(envelope, 'response'))
        throw new AsyncError('protocol', 'Missing response payload', { httpStatus: status, envelope: envelope, response: result });
    if (namespace != null) {
        if (!isRecord(data) || !own(data, namespace))
            throw new AsyncError('protocol', 'Missing response namespace', { httpStatus: status, envelope: envelope, response: result });
        data = data[namespace];
    }
    return { data: data, meta: meta, envelope: envelope, httpStatus: status };
}
/** One transport pipeline for both path requests and described async actions. */
function request(spec, context) {
    return new Promise(function (resolve, reject) {
        var xhr;
        var timer;
        var settled = false;
        var signal = spec && spec.signal;
        var finish = function (error, result) {
            if (settled)
                return;
            settled = true;
            if (timer !== undefined)
                clearTimeout(timer);
            if (signal)
                signal.removeEventListener('abort', abort);
            if (xhr)
                xhr.onreadystatechange = xhr.onerror = xhr.onabort = xhr.ontimeout = null;
            if (error !== undefined)
                reject(asAsyncError(error));
            else
                resolve(result);
        };
        var cancel = function (kind) {
            finish(new AsyncError(kind, kind === 'aborted' ? 'Request aborted' : 'Request timed out'));
            if (xhr && xhr.abort) {
                try {
                    xhr.abort();
                }
                catch (_) { /* Already settled locally. */ }
            }
        };
        var abort = function () { return cancel('aborted'); };
        try {
            if (signal && signal.aborted)
                return abort();
            var prepared_1 = prepare(spec, context);
            var outputNamespace_1 = spec.outputNamespace;
            var timeoutMs = spec.timeoutMs;
            xhr = openRequest(prepared_1.http);
            var active_1 = xhr;
            xhr.onreadystatechange = function () {
                if (active_1.readyState !== 4 || settled)
                    return;
                if (active_1.status === 0)
                    return finish(new AsyncError('transport', 'Network request failed', { httpStatus: 0 }));
                try {
                    finish(undefined, decode(active_1.status, active_1.responseText, outputNamespace_1, prepared_1.metaNamespace));
                }
                catch (error) {
                    finish(error);
                }
            };
            xhr.onerror = function () { return finish(new AsyncError('transport', 'Network request failed')); };
            xhr.onabort = function () { return finish(new AsyncError('aborted', 'Request aborted')); };
            xhr.ontimeout = function () { return finish(new AsyncError('timeout', 'Request timed out')); };
            if (signal) {
                signal.addEventListener('abort', abort);
                if (signal.aborted)
                    return abort();
            }
            if (timeoutMs !== undefined)
                timer = setTimeout(function () { return cancel('timeout'); }, timeoutMs);
            sendRequest(xhr, prepared_1.http);
        }
        catch (error) {
            finish(asAsyncError(error, 'transport'));
        }
    });
}

var dictionaries = {
    create: function () { return Object.create(null); },
    owns: function (target, key) { return Object.prototype.hasOwnProperty.call(target, key); }
};
function validateParams(action, params, language) {
    if (params !== undefined && !isRecord(params))
        throw new AsyncError('validation', 'Action parameters must be an object');
    var prepared = new Parameters({ description: action, client: { translate: function (key, values) { return I18n.translate(language, key, values); } } }, undefined, dictionaries);
    var input = action.input;
    if (input && params) {
        for (var _i = 0, _a = Object.keys(params); _i < _a.length; _i++) {
            var name_1 = _a[_i];
            if (!own(input.parameters, name_1))
                continue;
            var entry = dictionaries.create();
            entry[name_1] = params[name_1];
            // Fresh coercion locals per field; validators still see the complete map.
            Object.assign(prepared.params, prepared.coerceParams(entry));
        }
    }
    if (!prepared.validate())
        throw new AsyncError('validation', I18n.translate(language, 'errors.invalid_input_parameters'), { errors: prepared.errors });
    return prepared.params;
}
function validLayout(layout) {
    if (layout === null)
        return true;
    return isRecord(layout) && ['object', 'object_list', 'hash', 'hash_list'].indexOf(String(layout.layout)) !== -1 &&
        typeof layout.namespace === 'string' && layout.namespace.length > 0 && isRecord(layout.parameters) &&
        Object.keys(layout.parameters).every(function (name) { return isRecord(layout.parameters[name]) &&
            typeof layout.parameters[name].type === 'string'; });
}
function validateResources(resources, baseUrl) {
    if (!isRecord(resources))
        throw new AsyncError('protocol', 'Invalid resource description');
    Object.keys(resources).forEach(function (name) {
        var resource = resources[name];
        if (!isRecord(resource) || !isRecord(resource.actions) || !isRecord(resource.resources))
            throw new AsyncError('protocol', 'Invalid resource description');
        Object.keys(resource.actions).forEach(function (actionName) {
            var action = resource.actions[actionName];
            if (!isRecord(action) || typeof action.method !== 'string' || !/^[A-Za-z]+$/.test(action.method) ||
                typeof action.path !== 'string' || !validLayout(action.input) || !validLayout(action.output) ||
                (action.aliases !== undefined && (!Array.isArray(action.aliases) || action.aliases.some(function (alias) { return typeof alias !== 'string'; }))) ||
                (action.blocking !== undefined && typeof action.blocking !== 'boolean'))
                throw new AsyncError('protocol', 'Invalid action description');
            resolveApiUrl(baseUrl, action.path, { actionPath: true }, function (message) { return new AsyncError('protocol', message); });
        });
        validateResources(resource.resources, baseUrl);
    });
}
function freeze(value) {
    if (value && typeof value === 'object') {
        Object.keys(value).forEach(function (key) { return freeze(value[key]); });
        Object.freeze(value);
    }
}
function descriptionSnapshot(value, baseUrl) {
    try {
        if (!isRecord(value) || !isRecord(value.authentication) || !isRecord(value.meta) ||
            typeof value.meta.namespace !== 'string' || !value.meta.namespace)
            throw new AsyncError('protocol', 'Invalid API description');
        validateResources(value.resources, baseUrl);
        Object.keys(value.authentication).forEach(function (method) {
            var provider = value.authentication[method];
            if (!isRecord(provider))
                throw new AsyncError('protocol', 'Invalid authentication description');
            if (provider.resources !== undefined)
                validateResources(provider.resources, baseUrl);
        });
        var snapshot = JSON.parse(JSON.stringify(value));
        freeze(snapshot);
        return snapshot;
    }
    catch (error) {
        throw asAsyncError(error);
    }
}
function checkProtocol(result) {
    if (typeof result.envelope.version !== 'string' || !/^2\.\d+$/.test(result.envelope.version))
        throw new AsyncError('protocol', 'Incompatible API protocol version', { httpStatus: result.httpStatus, envelope: result.envelope, response: result });
}
function authenticationHeader(description, token) {
    var _a;
    if (typeof description.http_header !== 'string' || !description.http_header)
        throw new AsyncError('protocol', 'Missing authentication HTTP header');
    try {
        I18n.assertHeaderName(description.http_header);
        I18n.assertHeaderValue(token);
    }
    catch (error) {
        throw asAsyncError(error);
    }
    return _a = {}, _a[description.http_header] = token, _a;
}
function authenticate(method, options, description, send, language) {
    return __awaiter(this, void 0, void 0, function () {
        var provider, resource, actionName, input, initialAction, _loop_1, state_1;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    if (!isRecord(options) || !own(description.authentication, method))
                        throw new AsyncError('authentication', 'Unsupported authentication provider');
                    provider = description.authentication[method];
                    if (method === 'basic')
                        return [2 /*return*/, { headers: {}, credentials: { user: options.user, password: options.password } }];
                    if (method === 'oauth2') {
                        if (!isRecord(options.access_token) || typeof options.access_token.access_token !== 'string')
                            throw new AsyncError('authentication', 'An OAuth2 access token is required');
                        return [2 /*return*/, { headers: authenticationHeader(provider, options.access_token.access_token) }];
                    }
                    if (method !== 'token')
                        throw new AsyncError('authentication', 'Unsupported authentication provider');
                    if (own(options, 'token')) {
                        if (typeof options.token !== 'string')
                            throw new AsyncError('authentication', 'Invalid authentication token');
                        return [2 /*return*/, { headers: authenticationHeader(provider, options.token) }];
                    }
                    resource = provider.resources && own(provider.resources, 'token') ? provider.resources.token : undefined;
                    if (!resource)
                        throw new AsyncError('protocol', 'Missing token authentication resource');
                    actionName = 'request';
                    input = { lifetime: options.lifetime || 'renewable_auto' };
                    if (options.interval !== undefined)
                        input.interval = options.interval;
                    initialAction = resource.actions.request;
                    if (!initialAction || !initialAction.input)
                        throw new AsyncError('protocol', 'Missing token request action');
                    Object.keys(initialAction.input.parameters).forEach(function (name) {
                        if (name !== 'lifetime' && name !== 'interval' && options[name] !== undefined)
                            input[name] = options[name];
                    });
                    _loop_1 = function () {
                        var action, result, data, challenge, parameters, answer, cause_1;
                        return __generator(this, function (_b) {
                            switch (_b.label) {
                                case 0:
                                    if (!own(resource.actions, actionName))
                                        throw new AsyncError('protocol', 'Missing authentication action');
                                    action = resource.actions[actionName];
                                    return [4 /*yield*/, send({ method: action.method, path: action.path,
                                            inputNamespace: action.input && action.input.namespace, outputNamespace: action.output && action.output.namespace,
                                            metaNamespace: description.meta.namespace, params: validateParams(action, input, language) }, { headers: {} })];
                                case 1:
                                    result = _b.sent();
                                    data = result.data;
                                    if (!isRecord(data) || typeof data.token !== 'string' || typeof data.complete !== 'boolean')
                                        throw new AsyncError('protocol', 'Invalid token authentication response', { response: result, envelope: result.envelope });
                                    if (data.complete)
                                        return [2 /*return*/, { value: { headers: authenticationHeader(provider, data.token) } }];
                                    if (typeof data.next_action !== 'string' || !own(resource.actions, data.next_action))
                                        throw new AsyncError('protocol', 'Missing authentication challenge action', { response: result, envelope: result.envelope });
                                    if (typeof options.onChallenge !== 'function')
                                        throw new AsyncError('authentication', 'An authentication challenge handler is required', { response: result, envelope: result.envelope });
                                    challenge = resource.actions[data.next_action];
                                    parameters = {};
                                    Object.keys(challenge.input ? challenge.input.parameters : {}).forEach(function (name) {
                                        if (name !== 'token')
                                            parameters[name] = challenge.input.parameters[name];
                                    });
                                    answer = void 0;
                                    _b.label = 2;
                                case 2:
                                    _b.trys.push([2, 4, , 5]);
                                    return [4 /*yield*/, options.onChallenge(data.next_action, parameters)];
                                case 3:
                                    answer = _b.sent();
                                    return [3 /*break*/, 5];
                                case 4:
                                    cause_1 = _b.sent();
                                    throw new AsyncError('authentication', 'Authentication challenge failed', { cause: cause_1 });
                                case 5:
                                    if (!isRecord(answer))
                                        throw new AsyncError('authentication', 'Authentication challenge must return an object');
                                    input = Object.assign(Object.create(null), answer, { token: data.token });
                                    actionName = data.next_action;
                                    return [2 /*return*/];
                            }
                        });
                    };
                    _a.label = 1;
                case 1: return [5 /*yield**/, _loop_1()];
                case 2:
                    state_1 = _a.sent();
                    if (typeof state_1 === "object")
                        return [2 /*return*/, state_1.value];
                    _a.label = 3;
                case 3: return [3 /*break*/, 1];
                case 4: return [2 /*return*/];
            }
        });
    });
}

function stateSnapshot(data) {
    if (!isRecord(data) || typeof data.id !== 'number' || !Number.isInteger(data.id) ||
        typeof data.finished !== 'boolean' || typeof data.status !== 'boolean' ||
        typeof data.current !== 'number' || !Number.isFinite(data.current) ||
        typeof data.total !== 'number' || !Number.isFinite(data.total) || typeof data.can_cancel !== 'boolean')
        throw new AsyncError('protocol', 'Invalid action state');
    return __assign(__assign(__assign(__assign({ id: data.id, finished: data.finished, status: data.status, canCancel: data.can_cancel }, (typeof data.label === 'string' ? { label: data.label } : {})), { progress: __assign({ current: data.current, total: data.total }, (typeof data.unit === 'string' ? { unit: data.unit } : {})) }), (typeof data.created_at === 'string' || data.created_at === null ? { createdAt: data.created_at } : {})), (typeof data.updated_at === 'string' || data.updated_at === null ? { updatedAt: data.updated_at } : {}));
}
function actionPath(action, id) {
    var remaining = true;
    var path = action.path.replace(/\{[a-zA-Z0-9_-]+\}/g, function () {
        if (!remaining)
            throw new AsyncError('protocol', 'Unresolved action-state path');
        remaining = false;
        return encodeURIComponent(String(id));
    });
    return path;
}
function waitForCompletion(result, record, options) {
    return __awaiter(this, void 0, void 0, function () {
        var resources, resource, controller, timedOut, state, abort, timer, started, action, remaining, params, reply, error_1, failure;
        return __generator(this, function (_a) {
            switch (_a.label) {
                case 0:
                    if (!record)
                        throw new AsyncError('protocol', 'Unknown action invocation');
                    if (!record.action.blocking || record.stateId === undefined || record.stateId === null)
                        return [2 /*return*/, { value: result.value, response: result.response, state: null }];
                    if (!options || !Number.isFinite(options.timeoutMs) || options.timeoutMs <= 0)
                        throw new AsyncError('validation', 'Completion timeout must be positive', { response: result.response });
                    if (typeof record.stateId !== 'number' || !Number.isInteger(record.stateId) || record.stateId < 0)
                        throw new AsyncError('protocol', 'Invalid action-state identifier', { response: result.response });
                    resources = record.context.description.resources;
                    resource = own(resources, 'action_state') ? resources.action_state : undefined;
                    if (!resource || !own(resource.actions, 'show') || !own(resource.actions, 'poll'))
                        throw new AsyncError('protocol', 'Missing action-state resource', { response: result.response });
                    controller = new AbortController();
                    timedOut = false;
                    abort = function () { return controller.abort(); };
                    if (options.signal) {
                        options.signal.addEventListener('abort', abort);
                        if (options.signal.aborted)
                            abort();
                    }
                    timer = setTimeout(function () { timedOut = true; controller.abort(); }, options.timeoutMs);
                    started = Date.now();
                    _a.label = 1;
                case 1:
                    _a.trys.push([1, 6, 7, 8]);
                    action = resource.actions.show;
                    _a.label = 2;
                case 2:
                    remaining = options.timeoutMs - (Date.now() - started);
                    if (remaining <= 0)
                        throw new AsyncError('timeout', 'Completion wait timed out');
                    if (controller.signal.aborted)
                        throw new AsyncError(timedOut ? 'timeout' : 'aborted', 'Completion wait stopped');
                    params = state ? {
                        timeout: Math.min(options.blockInterval === undefined ? 15 : options.blockInterval, remaining / 1000, 30),
                        update_in: options.blockUpdateIn === undefined ? 3 : options.blockUpdateIn,
                        current: state.progress.current, total: state.progress.total, status: state.status
                    } : undefined;
                    return [4 /*yield*/, record.context.request({ method: action.method, path: actionPath(action, record.stateId),
                            inputNamespace: action.input && action.input.namespace, outputNamespace: action.output && action.output.namespace,
                            params: record.context.validateParams(action, params), signal: controller.signal, timeoutMs: remaining })];
                case 3:
                    reply = _a.sent();
                    state = stateSnapshot(reply.data);
                    if (state.id !== record.stateId)
                        throw new AsyncError('protocol', 'Unexpected action-state identifier');
                    if (options.onStateChange)
                        options.onStateChange(state);
                    if (state.finished) {
                        if (!state.status)
                            throw new AsyncError('action-failed', 'Server action failed');
                        return [2 /*return*/, { value: result.value, response: result.response, state: state }];
                    }
                    action = resource.actions.poll;
                    _a.label = 4;
                case 4: return [3 /*break*/, 2];
                case 5: return [3 /*break*/, 8];
                case 6:
                    error_1 = _a.sent();
                    failure = timedOut ? new AsyncError('timeout', 'Completion wait timed out', { cause: error_1 }) : asAsyncError(error_1);
                    failure.response = result.response;
                    if (!failure.envelope)
                        failure.envelope = result.response.envelope;
                    if (state)
                        failure.state = state;
                    throw failure;
                case 7:
                    clearTimeout(timer);
                    if (options.signal)
                        options.signal.removeEventListener('abort', abort);
                    return [7 /*endfinally*/];
                case 8: return [2 /*return*/];
            }
        });
    });
}

function hasOwn(value, name) {
    return Object.prototype.hasOwnProperty.call(value, name);
}
function nonThenable(value) {
    Object.defineProperty(value, 'then', { value: undefined, enumerable: false, writable: false, configurable: false });
}
/** Description names never replace helpers, prototypes or Promise assimilation. */
function attachMember(value, name, member) {
    if (name === '__proto__' || name === 'constructor' || name === 'prototype' || name in value)
        return;
    Object.defineProperty(value, name, { value: member, enumerable: true, configurable: true });
}
function lookupResource(context, path) {
    var resources = context.description.resources;
    var description;
    for (var _i = 0, path_1 = path; _i < path_1.length; _i++) {
        var name_1 = path_1[_i];
        if (!hasOwn(resources, name_1))
            throw context.makeError('protocol', 'Unknown resource ' + path.join('.'));
        description = resources[name_1];
        resources = description.resources;
    }
    if (!description)
        throw context.makeError('protocol', 'A resource path is required');
    return description;
}
function lookupAction(context, path, name) {
    var actions = lookupResource(context, path).actions;
    if (hasOwn(actions, name))
        return actions[name];
    for (var _i = 0, _a = Object.keys(actions); _i < _a.length; _i++) {
        var key = _a[_i];
        if ((actions[key].aliases || []).indexOf(name) !== -1)
            return actions[key];
    }
    throw context.makeError('protocol', 'Unknown action ' + path.concat(name).join('.'));
}
function copyValue(context, value, parents, localAttributes) {
    if (localAttributes === void 0) { localAttributes = false; }
    if (!value || typeof value !== 'object')
        return value;
    // Local fields may refer to another async entity. Request/meta snapshots must
    // still copy ordinary data, after described Resource inputs become scalar IDs.
    if (localAttributes && value instanceof AsyncResourceInstance)
        return value;
    if (value instanceof Date)
        return new Date(value.getTime());
    if (parents.indexOf(value) !== -1)
        throw context.makeError('protocol', 'Circular action parameters');
    var next = parents.concat(value);
    if (Array.isArray(value))
        return value.map(function (item) { return copyValue(context, item, next, localAttributes); });
    var result = Object.create(null);
    for (var _i = 0, _a = Object.keys(value); _i < _a.length; _i++) {
        var key = _a[_i];
        Object.defineProperty(result, key, { value: copyValue(context, value[key], next, localAttributes), writable: true, enumerable: true, configurable: true });
    }
    return result;
}
function snapshotValues(context, value) {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        throw context.makeError('protocol', 'Action parameters must be an object');
    return copyValue(context, value, []);
}
/** Local attribute copies preserve entity references without changing wire snapshots. */
function snapshotAttributes(context, value) {
    if (!value || typeof value !== 'object' || Array.isArray(value))
        throw context.makeError('protocol', 'Resource attributes must be an object');
    return copyValue(context, value, [], true);
}
/** Omitted identity is distinct from an explicit empty or invalid replacement. */
function pathParams(context, meta) {
    if (!hasOwn(meta, 'path_params'))
        return undefined;
    if (!Array.isArray(meta.path_params) || meta.path_params.some(function (id) { return (typeof id !== 'string' && typeof id !== 'number') || (typeof id === 'number' && !isFinite(id)); }))
        throw context.makeError('protocol', 'Malformed resource path_params');
    return Object.freeze(meta.path_params.slice());
}
function resolvePath(context, pattern, ids) {
    var position = 0;
    var resolved = pattern.replace(/\{[a-zA-Z0-9_-]+\}/g, function () {
        if (position >= ids.length)
            throw context.makeError('protocol', 'Unresolved action path arguments');
        var id = ids[position++];
        if ((typeof id !== 'string' && typeof id !== 'number') || (typeof id === 'number' && !isFinite(id)))
            throw context.makeError('protocol', 'Invalid action path argument');
        return encodeURIComponent(id);
    });
    return resolved;
}
function prepareOptions(context, args) {
    var ids = [];
    var options = {};
    var _loop_1 = function (i) {
        var argument = args[i];
        if (argument && typeof argument === 'object' && !Array.isArray(argument)) {
            if (i !== args.length - 1)
                throw context.makeError('protocol', 'Action options must be the last argument');
            var supplied = argument;
            var allowed_1 = ['params', 'meta', 'headers', 'signal', 'timeoutMs'];
            if (Object.keys(supplied).some(function (key) { return allowed_1.indexOf(key) === -1; }))
                throw context.makeError('protocol', 'Async actions accept params/meta options without callbacks');
            for (var _i = 0, _a = ['params', 'meta', 'headers']; _i < _a.length; _i++) {
                var key = _a[_i];
                if (hasOwn(supplied, key) && (!supplied[key] || typeof supplied[key] !== 'object' || Array.isArray(supplied[key])))
                    throw context.makeError('protocol', 'Malformed action ' + key);
            }
            options = __assign({}, supplied);
        }
        else {
            if (typeof argument !== 'string' && typeof argument !== 'number')
                throw context.makeError('protocol', 'Async actions do not accept callbacks or invalid IDs');
            ids.push(argument);
        }
    };
    for (var i = 0; i < args.length; i++) {
        _loop_1(i);
    }
    return { ids: ids, options: options };
}
function normalizeParams(context, action, params) {
    if (!params)
        return params;
    var normalized = Object.create(null);
    for (var _i = 0, _a = Object.keys(params); _i < _a.length; _i++) {
        var name_2 = _a[_i];
        var value = params[name_2];
        var parameter = action.input && action.input.parameters[name_2];
        if (parameter && parameter.type === 'Resource' && value && typeof value === 'object' && !Array.isArray(value)) {
            var identifier = parameter.value_id || 'id';
            if (value instanceof AsyncResourceInstance)
                value = value.get(identifier);
            else
                value = hasOwn(value, identifier) ? value[identifier] : undefined;
            // Undefined would be silently omitted by Parameters; a missing/invalid
            // association identifier must instead reject this submitted Resource.
            if (value == null || (typeof value !== 'string' && typeof value !== 'number')) {
                var errors = Object.create(null);
                errors[name_2] = ['Resource value must contain an identifier'];
                throw context.makeError('validation', 'Invalid resource identifier for parameter ' + name_2, { errors: errors });
            }
        }
        normalized[name_2] = value;
    }
    return snapshotValues(context, normalized);
}
function protocolFailure(context, error, response) {
    if (error instanceof Error && typeof error.kind === 'string') {
        if (response) {
            var details = error;
            if (!details.response)
                details.response = response;
            if (!details.envelope)
                details.envelope = response.envelope;
            if (details.httpStatus === undefined)
                details.httpStatus = response.httpStatus;
        }
        return error;
    }
    return context.makeError('protocol', error instanceof Error ? error.message : 'Unable to materialize action response', { cause: error, response: response });
}
function materialize(context, path, action, response) {
    switch (action.output && action.output.layout) {
        case 'object':
            return new AsyncResourceInstance(context, path, response.data, pathParams(context, response.meta) || [], true);
        case 'object_list':
            return new AsyncResourceList(context, path, response);
        default:
            return response.data;
    }
}
function createAction(context, path, name, ids) {
    if (ids === void 0) { ids = []; }
    var resourcePath = Object.freeze(path.slice());
    var boundIds = Object.freeze(ids.slice());
    var description = lookupAction(context, resourcePath, name);
    var invoke = function () {
        var args = [];
        for (var _i = 0; _i < arguments.length; _i++) {
            args[_i] = arguments[_i];
        }
        try {
            var prepared = prepareOptions(context, args);
            var options = prepared.options;
            var placeholders = (description.path.match(/\{[a-zA-Z0-9_-]+\}/g) || []).length;
            // Resource identity can include IDs unused by a collection-level action.
            var inherited = boundIds.slice(0, placeholders);
            if (prepared.ids.length > placeholders - inherited.length)
                throw context.makeError('protocol', 'Unexpected action path arguments');
            var spec = {
                method: description.method,
                path: resolvePath(context, description.path, inherited.concat(prepared.ids)),
                inputNamespace: description.input && description.input.namespace,
                outputNamespace: description.output && description.output.namespace,
                metaNamespace: context.metaNamespace,
                params: context.validateParams(description, normalizeParams(context, description, options.params)),
                meta: options.meta ? snapshotValues(context, options.meta) : undefined,
                headers: options.headers ? __assign({}, options.headers) : undefined,
                signal: options.signal,
                timeoutMs: options.timeoutMs,
            };
            return context.request(spec).then(function (response) {
                try {
                    return context.recordInvocation(materialize(context, resourcePath, description, response), response, description);
                }
                catch (error) {
                    throw protocolFailure(context, error, response);
                }
            });
        }
        catch (error) {
            return Promise.reject(protocolFailure(context, error));
        }
    };
    var callable = invoke;
    nonThenable(callable);
    Object.defineProperty(callable, 'invoke', { value: invoke });
    return callable;
}
function createResource(context, path, ids) {
    if (ids === void 0) { ids = []; }
    var resourcePath = Object.freeze(path.slice());
    var boundIds = Object.freeze(ids.slice());
    var description = lookupResource(context, resourcePath);
    var callable = function () {
        var moreIds = [];
        for (var _i = 0; _i < arguments.length; _i++) {
            moreIds[_i] = arguments[_i];
        }
        return createResource(context, resourcePath, boundIds.concat(moreIds));
    };
    nonThenable(callable);
    Object.defineProperties(callable, {
        getName: { value: function () { return resourcePath[resourcePath.length - 1]; } },
        resource: { value: function (name) { return createResource(context, resourcePath.concat(name), boundIds); } },
        action: { value: function (name) { return createAction(context, resourcePath, name, boundIds); } },
        new: { value: function (attributes) {
                if (attributes === void 0) { attributes = {}; }
                return new AsyncResourceInstance(context, resourcePath, attributes, boundIds, false);
            } },
    });
    for (var _i = 0, _a = Object.keys(description.resources); _i < _a.length; _i++) {
        var child = _a[_i];
        attachMember(callable, child, createResource(context, resourcePath.concat(child), boundIds));
    }
    for (var _b = 0, _c = Object.keys(description.actions); _b < _c.length; _b++) {
        var name_3 = _c[_b];
        var action = createAction(context, resourcePath, name_3, boundIds);
        for (var _d = 0, _e = [name_3].concat(description.actions[name_3].aliases || []); _d < _e.length; _d++) {
            var alias = _e[_d];
            attachMember(callable, alias, action);
        }
    }
    return callable;
}
/** Fields are local. Association I/O is available only through loadAssociation. */
var AsyncResourceInstance = /** @class */ (function () {
    function AsyncResourceInstance(context, path, attributes, ids, persistent) {
        if (ids === void 0) { ids = []; }
        if (persistent === void 0) { persistent = true; }
        this.associations = Object.create(null);
        this.attributeNames = Object.create(null);
        this.installedNames = Object.create(null);
        this.saving = false;
        this.context = context;
        this.resourcePath = Object.freeze(path.slice());
        this.description = lookupResource(context, this.resourcePath);
        this.attributes = snapshotAttributes(context, attributes);
        this.ids = Object.freeze(ids.slice());
        this.persistent = persistent;
        nonThenable(this);
        this.installMembers();
    }
    AsyncResourceInstance.prototype.getName = function () { return this.resourcePath[this.resourcePath.length - 1]; };
    AsyncResourceInstance.prototype.get = function (name) { return this.attributes[name]; };
    AsyncResourceInstance.prototype.set = function (name, value) {
        Object.defineProperty(this.attributes, name, { value: value, writable: true, enumerable: true, configurable: true });
        delete this.associations[name];
        this.installAttribute(name);
    };
    AsyncResourceInstance.prototype.isPersistent = function () { return this.persistent; };
    AsyncResourceInstance.prototype.action = function (name) { return createAction(this.context, this.resourcePath, name, this.ids); };
    AsyncResourceInstance.prototype.resource = function (name) { return createResource(this.context, this.resourcePath.concat(name), this.ids); };
    AsyncResourceInstance.prototype.installAttribute = function (name) {
        var _this = this;
        if (name === this.context.metaNamespace || hasOwn(this.attributeNames, name))
            return;
        if (name === '__proto__' || name === 'constructor' || name === 'prototype' || name in this)
            return;
        this.attributeNames[name] = true;
        Object.defineProperty(this, name, { enumerable: true, configurable: true,
            get: function () { return _this.attributes[name]; }, set: function (value) { return _this.set(name, value); } });
    };
    AsyncResourceInstance.prototype.installMembers = function () {
        for (var _i = 0, _a = Object.keys(this.installedNames); _i < _a.length; _i++) {
            var name_4 = _a[_i];
            delete this[name_4];
            delete this.installedNames[name_4];
        }
        for (var _b = 0, _c = Object.keys(this.description.resources); _b < _c.length; _b++) {
            var name_5 = _c[_b];
            if (!(name_5 in this) && name_5 !== '__proto__' && name_5 !== 'prototype') {
                attachMember(this, name_5, this.resource(name_5));
                this.installedNames[name_5] = true;
            }
        }
        for (var _d = 0, _e = Object.keys(this.description.actions); _d < _e.length; _d++) {
            var name_6 = _e[_d];
            var action = this.action(name_6);
            for (var _f = 0, _g = [name_6].concat(this.description.actions[name_6].aliases || []); _f < _g.length; _f++) {
                var alias = _g[_f];
                if (!(alias in this) && alias !== '__proto__' && alias !== 'prototype') {
                    attachMember(this, alias, action);
                    this.installedNames[alias] = true;
                }
            }
        }
        for (var _h = 0, _j = Object.keys(this.attributes); _h < _j.length; _h++) {
            var name_7 = _j[_h];
            this.installAttribute(name_7);
        }
    };
    AsyncResourceInstance.prototype.submittedParams = function (action) {
        var params = Object.create(null);
        if (action.input) {
            for (var _i = 0, _a = Object.keys(action.input.parameters); _i < _a.length; _i++) {
                var name_8 = _a[_i];
                if (hasOwn(this.attributes, name_8))
                    params[name_8] = this.attributes[name_8];
            }
        }
        // The action synchronously converts described Resource values and then
        // snapshots the submitted payload before validation or request dispatch.
        return params;
    };
    AsyncResourceInstance.prototype.save = function (options) {
        var _this = this;
        if (options === void 0) { options = {}; }
        if (this.acceptedUnbound)
            return Promise.reject(this.acceptedUnbound);
        if (this.saving)
            return Promise.reject(this.context.makeError('protocol', 'A save is already in progress'));
        this.saving = true;
        try {
            var name_9 = this.persistent ? 'update' : 'create';
            var action_1 = lookupAction(this.context, this.resourcePath, name_9);
            var params = this.submittedParams(action_1);
            return this.action(name_9)(__assign(__assign({}, options), { params: params })).then(function (result) {
                var saved = result.value;
                if (!(saved instanceof AsyncResourceInstance))
                    throw _this.context.makeError('protocol', 'Save requires an object response', { response: result.response });
                // Validate identity and member binding before publishing any state.
                var returned = pathParams(_this.context, result.response.meta);
                var ids = returned === undefined && _this.persistent ? _this.ids : returned || [];
                var update = _this.description.actions.update;
                if (update) {
                    try {
                        resolvePath(_this.context, update.path, ids);
                    }
                    catch (error) {
                        throw protocolFailure(_this.context, error, result.response);
                    }
                }
                _this.attributes = snapshotAttributes(_this.context, saved.attributes);
                _this.ids = Object.freeze(ids.slice());
                _this.persistent = true;
                for (var _i = 0, _a = Object.keys(_this.associations); _i < _a.length; _i++) {
                    var name_10 = _a[_i];
                    delete _this.associations[name_10];
                }
                _this.installMembers();
                return _this.context.recordInvocation(_this, result.response, action_1);
            }).then(function (result) { _this.saving = false; return result; }, function (error) {
                _this.saving = false;
                var failure = protocolFailure(_this.context, error);
                var response = failure.response;
                if (!_this.persistent && response && response.envelope.status === true && response.httpStatus >= 200 && response.httpStatus < 300) {
                    _this.acceptedUnbound = _this.context.makeError('protocol', 'Create succeeded, but its response is unusable. Fetch the created resource before further writes.', { response: response, envelope: response.envelope, httpStatus: response.httpStatus, cause: failure, reason: 'accepted-unbound' });
                    throw _this.acceptedUnbound;
                }
                throw failure;
            });
        }
        catch (error) {
            this.saving = false;
            return Promise.reject(protocolFailure(this.context, error));
        }
    };
    AsyncResourceInstance.prototype.associationDescription = function (name) {
        for (var _i = 0, _a = Object.keys(this.description.actions); _i < _a.length; _i++) {
            var action = _a[_i];
            var output = this.description.actions[action].output;
            if (output && hasOwn(output.parameters, name) && output.parameters[name].type === 'Resource')
                return output.parameters[name];
        }
        throw this.context.makeError('protocol', 'Unknown association ' + name);
    };
    AsyncResourceInstance.prototype.loadAssociation = function (name, options) {
        var _this = this;
        if (options === void 0) { options = {}; }
        try {
            var description = this.associationDescription(name);
            if (!description.resource)
                throw this.context.makeError('protocol', 'Association has no resource path');
            if (hasOwn(this.associations, name))
                return Promise.resolve({ value: this.associations[name], response: null });
            var raw_1 = this.attributes[name];
            if (!raw_1 || typeof raw_1 !== 'object' || Array.isArray(raw_1))
                throw this.context.makeError('protocol', 'Malformed association value');
            var value = raw_1;
            var meta = value[this.context.metaNamespace] || {};
            if (typeof meta !== 'object' || Array.isArray(meta))
                throw this.context.makeError('protocol', 'Malformed association metadata');
            var ids = pathParams(this.context, meta) || [];
            if (meta.resolved === true) {
                var associated = new AsyncResourceInstance(this.context, description.resource, value, ids, true);
                this.associations[name] = associated;
                return Promise.resolve({ value: associated, response: null });
            }
            return createAction(this.context, description.resource, 'show', ids)(options).then(function (result) {
                if (!(result.value instanceof AsyncResourceInstance))
                    throw _this.context.makeError('protocol', 'Association load requires an object response', { response: result.response });
                // A field replaced while the request was in flight owns its newer value.
                if (_this.attributes[name] === raw_1)
                    _this.associations[name] = result.value;
                return { value: result.value, response: result.response };
            });
        }
        catch (error) {
            return Promise.reject(protocolFailure(this.context, error));
        }
    };
    return AsyncResourceInstance;
}());
/** Local list operations never issue a request or return callback-owned objects. */
var AsyncResourceList = /** @class */ (function () {
    function AsyncResourceList(context, path, response) {
        var _this = this;
        if (!Array.isArray(response.data))
            throw context.makeError('protocol', 'Expected an object-list response', { response: response });
        var items = response.data.map(function (value) {
            if (!value || typeof value !== 'object' || Array.isArray(value))
                throw context.makeError('protocol', 'Malformed object-list item', { response: response });
            var data = snapshotValues(context, value);
            var meta = hasOwn(data, context.metaNamespace) ? data[context.metaNamespace] : {};
            if (!meta || typeof meta !== 'object' || Array.isArray(meta))
                throw context.makeError('protocol', 'Malformed object metadata', { response: response });
            return new AsyncResourceInstance(context, path, data, pathParams(context, meta) || [], true);
        });
        this.items = Object.freeze(items);
        this.length = items.length;
        items.forEach(function (item, index) { return Object.defineProperty(_this, String(index), { value: item, enumerable: true }); });
        this.totalCount = response.meta.total_count;
        nonThenable(this);
        // Resolve Symbol only when an async list is constructed. Legacy-only
        // bundle loading retains its original runtime requirements.
        Object.defineProperty(this, Symbol.iterator, { value: function () { return _this.items[Symbol.iterator](); } });
    }
    AsyncResourceList.prototype.itemAt = function (index) { return this.items[index]; };
    AsyncResourceList.prototype.first = function () { return this.items[0] || null; };
    AsyncResourceList.prototype.last = function () { return this.items[this.length - 1] || null; };
    AsyncResourceList.prototype.each = function (fn) { this.items.forEach(fn); };
    return AsyncResourceList;
}());

var AsyncClient = /** @class */ (function () {
    function AsyncClient(url, options) {
        if (options === void 0) { options = {}; }
        this.then = undefined;
        this.resources = [];
        this.generation = 0;
        this.authentication = { headers: {} };
        this.roots = Object.create(null);
        this.attached = Object.create(null);
        this.invocations = new WeakMap();
        while (url.length > 0 && url[url.length - 1] === '/')
            url = url.slice(0, -1);
        var parsed = new URL(url);
        if (!/^https?:$/.test(parsed.protocol) || parsed.username || parsed.password)
            throw new AsyncError('protocol', 'Invalid API base URL');
        this.baseUrl = url;
        this.version = options.version === undefined ? null : options.version;
        this.language = options.language === undefined ? null : options.language;
        this.languageHeader = options.languageHeader === undefined ? options.language_header || I18n.DEFAULT_LANGUAGE_HEADER : options.languageHeader;
        I18n.requestHeaders(this.language, this.languageHeader);
    }
    AsyncClient.prototype.setLanguage = function (language) {
        I18n.requestHeaders(language, this.languageHeader);
        this.language = language;
    };
    AsyncClient.prototype.setLanguageHeader = function (header) {
        I18n.assertHeaderName(header);
        this.languageHeader = header;
    };
    AsyncClient.prototype.requestContext = function (auth, metaNamespace, pathMode) {
        if (pathMode === void 0) { pathMode = 'api'; }
        return __assign({ baseUrl: this.baseUrl, pathMode: pathMode, metaNamespace: metaNamespace, language: this.language, languageHeader: this.languageHeader, headers: Object.assign({}, auth.headers) }, (auth.credentials ? { credentials: Object.assign({}, auth.credentials) } : {}));
    };
    /** Explicit per-request headers override configured auth/language headers. */
    AsyncClient.prototype.request = function (spec) {
        if (arguments.length !== 1)
            return Promise.reject(new AsyncError('validation', 'request does not accept callbacks'));
        return request(spec, this.requestContext(this.authentication, this.description ? this.description.meta.namespace : '_meta'));
    };
    AsyncClient.prototype.enqueue = function (operation) {
        var result = (this.transitions || Promise.resolve()).then(operation).catch(function (error) { throw asAsyncError(error); });
        this.transitions = result.then(function () { return undefined; }, function () { return undefined; });
        return result;
    };
    AsyncClient.prototype.fetchDescription = function (auth) {
        return __awaiter(this, void 0, void 0, function () {
            var path, result;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        path = this.version == null ? '/?describe=default' : '/v' + encodeURIComponent(String(this.version)) + '/';
                        return [4 /*yield*/, request({ method: 'OPTIONS', path: path }, this.requestContext(auth, '_meta'))];
                    case 1:
                        result = _a.sent();
                        checkProtocol(result);
                        return [2 /*return*/, descriptionSnapshot(result.data, this.baseUrl)];
                }
            });
        });
    };
    AsyncClient.prototype.publish = function (description, auth, expectedGeneration) {
        var _this = this;
        if (this.generation !== expectedGeneration)
            throw new AsyncError('protocol', 'Lifecycle result belongs to an older client state', { reason: 'stale-binding' });
        var generation = this.generation + 1;
        var context = {
            description: description,
            metaNamespace: description.meta.namespace,
            generation: generation,
            request: function (spec) {
                if (_this.generation !== generation)
                    return Promise.reject(new AsyncError('protocol', 'Resource binding belongs to an older client state', { reason: 'stale-binding' }));
                return request(Object.assign({}, spec, { metaNamespace: description.meta.namespace }), _this.requestContext(auth, description.meta.namespace, 'descriptor'));
            },
            validateParams: function (action, params) { return validateParams(action, params, _this.language); },
            makeError: function (kind, message, details) { return new AsyncError(kind, message, details); },
            recordInvocation: function (value, response, action) {
                var receipt = { value: value, response: response };
                _this.invocations.set(receipt, { context: context, action: action, stateId: response.meta.action_state_id });
                return receipt;
            }
        };
        var roots = Object.create(null);
        var resources = Object.keys(description.resources).map(function (name) {
            var resource = createResource(context, [name]);
            roots[name] = resource;
            return resource;
        });
        // Build everything before replacing any public registry or auth state.
        Object.keys(this.attached).forEach(function (name) {
            if (_this[name] === _this.attached[name])
                delete _this[name];
        });
        this.attached = Object.create(null);
        this.description = description;
        this.authentication = auth;
        this.generation = generation;
        this.roots = roots;
        this.resources = resources;
        Object.keys(roots).forEach(function (name) {
            if (name !== '__proto__' && name !== 'prototype' && name !== 'constructor' && !(name in _this)) {
                Object.defineProperty(_this, name, { value: roots[name], configurable: true, enumerable: true });
                _this.attached[name] = roots[name];
            }
        });
    };
    AsyncClient.prototype.useDescription = function (description) {
        try {
            this.publish(descriptionSnapshot(description, this.baseUrl), this.authentication, this.generation);
        }
        catch (error) {
            throw asAsyncError(error);
        }
    };
    AsyncClient.prototype.setup = function () {
        var _this = this;
        if (arguments.length !== 0)
            return Promise.reject(new AsyncError('validation', 'setup does not accept callbacks'));
        return this.enqueue(function () { return __awaiter(_this, void 0, void 0, function () {
            var generation, description;
            return __generator(this, function (_a) {
                switch (_a.label) {
                    case 0:
                        generation = this.generation;
                        return [4 /*yield*/, this.fetchDescription(this.authentication)];
                    case 1:
                        description = _a.sent();
                        this.publish(description, this.authentication, generation);
                        return [2 /*return*/];
                }
            });
        }); });
    };
    AsyncClient.prototype.authenticate = function (method, options) {
        var _this = this;
        if (arguments.length !== 2 || options && Object.prototype.hasOwnProperty.call(options, 'callback'))
            return Promise.reject(new AsyncError('validation', 'authenticate does not accept callbacks'));
        var snapshot;
        try {
            snapshot = Object.assign(Object.create(null), options);
            if (options && options.access_token)
                snapshot.access_token = Object.assign({}, options.access_token);
        }
        catch (error) {
            return Promise.reject(asAsyncError(error, 'authentication'));
        }
        return this.enqueue(function () { return __awaiter(_this, void 0, void 0, function () {
            var generation, description, _a, candidate, authorized;
            var _this = this;
            return __generator(this, function (_b) {
                switch (_b.label) {
                    case 0:
                        generation = this.generation;
                        _a = this.description;
                        if (_a) return [3 /*break*/, 2];
                        return [4 /*yield*/, this.fetchDescription(this.authentication)];
                    case 1:
                        _a = (_b.sent());
                        _b.label = 2;
                    case 2:
                        description = _a;
                        return [4 /*yield*/, authenticate(method, snapshot, description, function (spec, state) { return request(spec, _this.requestContext(state, description.meta.namespace, 'descriptor')); }, this.language)];
                    case 3:
                        candidate = _b.sent();
                        return [4 /*yield*/, this.fetchDescription(candidate)];
                    case 4:
                        authorized = _b.sent();
                        this.publish(authorized, candidate, generation);
                        return [2 /*return*/];
                }
            });
        }); });
    };
    AsyncClient.prototype.availableVersions = function () {
        if (arguments.length !== 0)
            return Promise.reject(new AsyncError('validation', 'availableVersions does not accept callbacks'));
        return this.request({ method: 'OPTIONS', path: '/?describe=versions' }).then(function (result) {
            checkProtocol(result);
            var data = result.data;
            if (!data || !Array.isArray(data.versions) || data.versions.some(function (version) { return typeof version !== 'string' && typeof version !== 'number'; }) ||
                (typeof data.default !== 'string' && typeof data.default !== 'number'))
                throw new AsyncError('protocol', 'Invalid API version list', { response: result, envelope: result.envelope });
            return data;
        });
    };
    AsyncClient.prototype.resource = function (name) {
        if (!Object.prototype.hasOwnProperty.call(this.roots, name))
            throw new AsyncError('protocol', 'Resource not found');
        return this.roots[name];
    };
    AsyncClient.prototype.waitForCompletion = function (result, options) {
        if (arguments.length !== 2 || !options || typeof options !== 'object')
            return Promise.reject(new AsyncError('validation', 'Completion options are required'));
        return waitForCompletion(result, this.invocations.get(result), options);
    };
    return AsyncClient;
}());

// Keep public constructor/provider registration separate from module type cycles.
authenticationRegistry.registerProvider('basic', Basic);
authenticationRegistry.registerProvider('oauth2', OAuth2);
authenticationRegistry.registerProvider('token', Token);
Client.Action = Action;
Client.ActionState = ActionState;
Client.Authentication = authenticationRegistry;
Client.BaseResource = BaseResource;
Client.Hooks = Hooks;
Client.Http = Http;
Client.Resource = Resource;
Client.ResourceInstance = ResourceInstance;
Client.ResourceInstanceList = ResourceInstanceList;
Client.Response = Response;
Client.LocalResponse = LocalResponse;

exports.AsyncClient = AsyncClient;
exports.AsyncError = AsyncError;
exports.AsyncResourceInstance = AsyncResourceInstance;
exports.AsyncResourceList = AsyncResourceList;
exports.CallbackClient = Client;
exports.Client = Client;

return exports;

})({});

return HaveAPI;
}));
