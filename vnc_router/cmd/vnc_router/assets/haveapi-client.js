;(function(root, factory) {
  if (typeof define === 'function' && define.amd) {
    define([], factory);
  } else if (typeof exports === 'object') {
    module.exports = factory();
  } else {
    root.HaveAPI = factory();
  }
}(this, function() {
/**
 * Create a new client for the API.
 * @class Client
 * @memberof HaveAPI
 * @param {string} url base URL to the API
 * @param {Object} opts
 */
function Client(url, opts) {
	while (url.length > 0) {
		if (url[ url.length - 1 ] == '/')
			url = url.substr(0, url.length - 1);

		else break;
	}

	/**
	 * @member {Object} HaveAPI.Client#_private
	 * @protected
	 */
	this._private = {
		url: url,
		version: (opts !== undefined && opts.version !== undefined) ? opts.version : null,
		description: null,
		debug: (opts !== undefined && opts.debug !== undefined) ? opts.debug : 0,
	};

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
}

/** @constant HaveAPI.Client.Version */
Client.Version = '0.19.1';

/** @constant HaveAPI.Client.ProtocolVersion */
Client.ProtocolVersion = '2.0';

/**
 * @namespace Exceptions
 * @memberof HaveAPI.Client
 */
Client.Exceptions = {};

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
Client.prototype.setup = function(callback) {
	var that = this;

	this.fetchDescription(function(status, extract) {
		var desc = null;

		try {
			desc = extract.call();

		} catch (e) {
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
Client.prototype.useDescription = function(description) {
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
Client.prototype.availableVersions = function(callback) {
	var that = this;

	this.fetchDescription(function (status, extract) {
		var versions = null;

		try {
			versions = extract.call();
		} catch (e) {}

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
Client.prototype.isCompatible = function(callback) {
	var that = this;

	this.fetchDescription(function (status, extract) {

		try {
			extract.call();

			if (that._private.protocolVersion == Client.ProtocolVersion)
				callback('compatible');

			else
				callback('imperfect');

		} catch (e) {
			if (e instanceof Client.Exceptions.ProtocolError)
				callback(false);

			else
				throw e;
		}

	}, '/?describe=versions');
}

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
Client.prototype.fetchDescription = function(callback, path) {
	var that = this;
	var url = this._private.url;

	if (path === undefined)
		url += (this._private.version ? "/v"+ this._private.version +"/" : "/?describe=default");
	else
		url += path;

	this._private.http.request({
		method: 'OPTIONS',
		url: url,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		callback: function (status, response) {
			callback(status == 200, function () {
				if (!response)
					throw new Client.Exceptions.ProtocolError('Failed to fetch the API description');

				if (response.version === undefined) {
					throw new Client.Exceptions.ProtocolError(
						'Incompatible protocol version: the client uses v'+ Client.ProtocolVersion +
						' while the API server uses an unspecified version (pre 1.0)'
					);
				}

				that._private.protocolVersion = response.version;

				if (response.version == Client.ProtocolVersion) {
					return response.response;
				}

				v1 = response.version.split('.');
				v2 = Client.ProtocolVersion.split('.');

				if (v1[0] != v2[0]) {
					throw new Client.Exceptions.ProtocolError(
						'Incompatible protocol version: the client uses v'+ Client.ProtocolVersion +
						' while the API server uses v'+ response.version
					);
				}

				console.log(
					'WARNING: The client uses protocol v'+ Client.ProtocolVersion +
					' while the API server uses v'+ response.version
				);

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
Client.prototype.attachResources = function() {
	// Detach existing resources
	if (this.resources.length > 0) {
		this.destroyResources();
	}

	for(var r in this._private.description.resources) {
		if (this._private.debug > 10)
			console.log("Attach resource", r);

		this[r] = new Client.Resource(
			this,
			null,
			r,
			this._private.description.resources[r],
			[]
		);

		this.resources.push(this[r]);
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
Client.prototype.authenticate = function(method, opts, callback, reset) {
	var that = this;

	if (reset === undefined) reset = true;

	if (!this._private.description) {
		// The client has not yet been setup.
		// Fetch the description, do NOT attach the resources, use it only to authenticate.

		this.fetchDescription(function(status, extract) {
			that._private.description = extract.call();
			that.createSettings();
			that.authenticate(method, opts, callback);
		});

		return;
	}

	this.authProvider = new Authentication.providers[method](this, opts, this._private.description.authentication[method]);

	this.authProvider.setup(function(c, status) {
		// Fetch new description, which may be different when authenticated
		if (status && reset) {
			that.setup(function(c2, status2) {
				callback(c2, status2);
				that._private.hooks.invoke('after', 'authenticated', that, true);
			});

		} else {
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
Client.prototype.logout = function(callback) {
	var that = this;

	this.authProvider.logout(function() {
		that.authProvider = new Client.Authentication.Base();
		that.destroyResources();
		that._private.description = null;

		if (callback !== undefined)
			callback(that, true);
	});
};

/**
 * Always calls the callback with {@link HaveAPI.Client.Response} object. It does
 * not interpret the response.
 * @method HaveAPI.Client#directInvoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.directInvoke = function(action, opts) {
	if (this._private.debug > 5)
		console.log("Executing", action, "with opts", opts, "at", action.preparedPath);

	var that = this;
	var block = opts.block === undefined ? true : opts.block;

	var httpOpts = {
		method: action.httpMethod(),
		url: this._private.url + action.preparedPath,
		credentials: this.authProvider.credentials(),
		headers: this.authProvider.headers(),
		queryParameters: this.authProvider.queryParameters(),
		callback: function(status, response) {
			var res = new Client.Response(action, response);

			if(opts.onReply !== undefined)
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
		httpOpts.url = this.addParamsToQuery(
			httpOpts.url,
			action.namespace('input'),
			opts.params
		);

		if (opts.meta) {
			httpOpts.url = this.addParamsToQuery(
				httpOpts.url,
				metaNs,
				opts.meta
			);
		}

	} else {
		var scopedParams = {};
		var ns = action.namespace('input');

		if (ns)
			scopedParams[ns] = opts.params;

		if (opts.meta)
			scopedParams[metaNs] = opts.meta;

		httpOpts.params = scopedParams;
	}

	this._private.http.request(httpOpts);
};

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#invoke
 * @param {HaveAPI.Client.Action} action
 * @param {HaveAPI.Client~ActionCall} opts
 */
Client.prototype.invoke = function(action, opts) {
	var that = this;
	var origOnReply = opts.onReply;
	var origOnBlock = opts.block === undefined ? true : opts.block;

	opts.onReply = function (status, response) {
		if (!origOnReply && (!action.description.blocking || (!opts.onStateUpdate && !opts.onDone)))
			return;

		var responseObject;

		switch (action.layout('output')) {
			case 'object':
				responseObject = new Client.ResourceInstance(
					that,
					action.resource._private.parent,
					action,
					response
				);
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

/**
 * The response is interpreted and if the layout is object or object_list, ResourceInstance
 * or ResourceInstanceList is returned with the callback.
 * @method HaveAPI.Client#after
 * @param {String} event setup or authenticated
 * @param {HaveAPI.Client~doneCallback} callback
 */
Client.prototype.after = function(event, callback) {
	this._private.hooks.register('after', event, callback);
}

/**
 * Set member apiSettings.
 * @method HaveAPI.Client#createSettings
 * @private
 */
Client.prototype.createSettings = function() {
	this.apiSettings = {
		meta: this._private.description.meta
	};
}

/**
 * Detach resources from the client.
 * @method HaveAPI.Client#destroyResources
 * @private
 */
Client.prototype.destroyResources = function() {
	while (this.resources.length > 0) {
		delete this[ this.resources.shift().getName() ];
	}
};

/**
 * Return true if the parameters should be sent as a query parameters,
 * which is the case for GET and OPTIONS methods.
 * @method HaveAPI.Client#sendAsQueryParams
 * @param {String} method HTTP method
 * @return {Boolean}
 * @private
 */
Client.prototype.sendAsQueryParams = function(method) {
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
Client.prototype.addParamsToQuery = function(url, namespace, params) {
	var first = true;

	for (var key in params) {
		if (first) {
			if (url.indexOf('?') == -1)
				url += '?';

			else if (url[ url.length - 1 ] != '&')
				url += '&';

			first = false;

		} else url += '&';

		url += encodeURI(namespace) + '[' + encodeURI(key) + ']=' + encodeURI(params[key]);
	}

	return url;
};

/**
 * @class Hooks
 * @memberof HaveAPI.Client
 */
function Hooks (debug) {
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
Hooks.prototype.register = function(type, event, callback) {
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
Hooks.prototype.invoke = function(type, event) {
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

/**
 * @class Http
 * @memberof HaveAPI.Client
 */
function Http (debug) {
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
Http.prototype.request = function(opts) {
	if (this.debug > 5)
		console.log("Request to " + opts.method + " " + opts.url);

	var r = new XMLHttpRequest();

	if (opts.credentials === undefined)
		r.open(opts.method, opts.url);
	else
		r.open(opts.method, opts.url, true, opts.credentials.user, opts.credentials.password);

	for (var h in opts.headers) {
		r.setRequestHeader(h, opts.headers[h]);
	}

	if (opts.params !== undefined)
		r.setRequestHeader('Content-Type', 'application/json; charset=utf-8');

	r.onreadystatechange = function() {
		var state = r.readyState;

		if (this.debug > 6)
			console.log('Request state is ' + state);

		if (state == 4 && opts.callback !== undefined) {
			var json = null;

			try {
				json = JSON.parse(r.responseText);

			} catch (e) {
				console.log('JSON.parse failed', e);
			}

			if (json)
				opts.callback(r.status, json);

			else
				opts.callback(false, undefined);
		}
	};

	if (opts.params !== undefined) {
		r.send(JSON.stringify( opts.params ));

	} else {
		r.send();
	}
};

/**
 * @namespace Authentication
 * @memberof HaveAPI.Client
 */
Authentication = {
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
	registerProvider: function(name, obj) {
		Authentication.providers[name] = obj;
	}
};

/**
 * @class Base
 * @classdesc Base class for all authentication providers. They do not have to inherit
 *            it directly, but must implement all necessary methods.
 * @memberof HaveAPI.Client.Authentication
 */
Authentication.Base = function (client, opts, description){};

/**
 * Setup the authentication provider and call the callback.
 * @method HaveAPI.Client.Authentication.Base#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Base.prototype.setup = function(callback){};

/**
 * Logout, destroy all resources and call the callback.
 * @method HaveAPI.Client.Authentication.Base#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Base.prototype.logout = function(callback) {
	callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Base#credentials
 * @return {Object} credentials
 */
Authentication.Base.prototype.credentials = function(){};

/**
 * Returns an object with HTTP headers to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#headers
 * @return {Object} HTTP headers
 */
Authentication.Base.prototype.headers = function(){};

/**
 * Returns an object with query parameters to be sent with the request.
 * @method HaveAPI.Client.Authentication.Base#queryParameters
 * @return {Object} query parameters
 */
Authentication.Base.prototype.queryParameters = function(){};

/**
 * @class Basic
 * @classdesc Authentication provider for HTTP basic auth.
 *            Unfortunately, this provider probably won't work in most browsers
 *            because of their security considerations.
 * @memberof HaveAPI.Client.Authentication
 */
Authentication.Basic = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
};
Authentication.Basic.prototype = new Authentication.Base();

/**
 * @method HaveAPI.Client.Authentication.Basic#setup
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Basic.prototype.setup = function(callback) {
	if(callback !== undefined)
		callback(this.client, true);
};

/**
 * Returns an object with keys 'user' and 'password' that are used
 * for HTTP basic auth.
 * @method HaveAPI.Client.Authentication.Basic#credentials
 * @return {Object} credentials
 */
Authentication.Basic.prototype.credentials = function() {
	return this.opts;
};

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
Authentication.OAuth2 = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
	this.description = description;

	/**
	 * @member {String} HaveAPI.Client.Authentication.OAuth2#access_token Access and refresh tokens
	 */
	this.access_token = null;
};
Authentication.OAuth2.prototype = new Authentication.Base();

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
Authentication.OAuth2.prototype.setup = function(callback) {
	if (this.opts.hasOwnProperty('access_token')) {
		this.access_token = this.opts.access_token;

		if (callback !== undefined)
			callback(this.client, true);
	} else {
		throw "Option access_token must be provided";
	}
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#headers
 */
Authentication.OAuth2.prototype.headers = function() {
	var ret = {};

	// We send the token through the HaveAPI-speficic HTTP header, because
	// the Authorization header is not allowed by the server's CORS policy.
	ret[ this.description.http_header ] = this.access_token.access_token;

	return ret;
};

/**
 * @method HaveAPI.Client.Authentication.OAuth2#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.OAuth2.prototype.logout = function(callback) {
	var http = new XMLHttpRequest();
	var that = this;

	http.open('POST', this.description.revoke_url, true);
	http.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');

	http.onreadystatechange = function() {
		if (http.readyState == 4) {
			callback(that.client, http.status == 200);
		}
	}

	http.send("token=" + this.access_token.access_token);
};

/**
 * @class Token
 * @classdesc Token authentication provider.
 * @memberof HaveAPI.Client.Authentication
 * @param {HaveAPI.Client} client
 * @param {HaveAPI.Client.Authentication.Token~Options} opts
 * @param {Object} description
 */
Authentication.Token = function(client, opts, description) {
	this.client = client;
	this.opts = opts;
	this.description = description;
	this.configured = false;

	/**
	 * @member {String} HaveAPI.Client.Authentication.Token#token The token received from the API.
	 */
	this.token = null;
};
Authentication.Token.prototype = new Authentication.Base();

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
Authentication.Token.prototype.setup = function(callback) {
	this.resource = new Client.Resource(
		this.client,
		null,
		'token',
		this.description.resources.token,
		[]
	);

	if (this.opts.hasOwnProperty('token')) {
		this.token = this.opts.token;
		this.validTo = this.opts.validTo;
		this.configured = true;

		if(callback !== undefined)
			callback(this.client, true);

	} else {
		this.requestToken(callback);
	}
};

/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Token.prototype.requestToken = function(callback) {
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
Authentication.Token.prototype.authenticationStep = function(action, input, callback) {
	var that = this;

	this.resource[action](input, function(c, response) {
		if (response.isOk()) {
			var t = response.response();

			if (t.complete) {
				that.token = t.token;
				that.validTo = t.valid_to;
				that.configured = true;

				if (callback !== undefined)
					callback(that.client, true);
			} else {
				if (that.opts.callback === undefined)
					throw "implement multi-factor authentication";

				var cont = function (input) {
					that.authenticationStep(
						t.next_action,
						Object.assign({}, input, {token: t.token}),
						callback
					);
				}

				var ret = that.opts.callback(
					t.next_action,
					that.getCustomActionCredentials(t.next_action),
					cont
				);

				if (typeof ret === 'object' && ret !== null)
					cont(ret);
			}

		} else {
			if (callback !== undefined)
				callback(that.client, false);
		}
	});
};
/**
 * @method HaveAPI.Client.Authentication.Token#requestToken
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Token.prototype.renewToken = function(callback) {
	var that = this;

	this.resource.renew(function(c, response) {
		if (response.isOk()) {
			var t = response.response();

			that.validTo = t.valid_to;

			if(callback !== undefined)
				callback(that.client, true);

		} else {
			if(callback !== undefined)
				callback(that.client, false);
		}
	});
};

/**
 * @method HaveAPI.Client.Authentication.Token#headers
 */
Authentication.Token.prototype.headers = function(){
	if(!this.configured)
		return;

	var ret = {};
	ret[ this.description.http_header ] = this.token;

	return ret;
};

/**
 * @method HaveAPI.Client.Authentication.Token#logout
 * @param {HaveAPI.Client~doneCallback} callback
 */
Authentication.Token.prototype.logout = function(callback) {
	this.resource.revoke(null, function(c, reply) {
		callback(this.client, reply.isOk());
	});
};

/**
 * Return names of parameters used as credentials for custom authentication
 * @method HaveAPI.Client.Authentication.Token#getRequestCredentials
 * @private
 * @return {Array}
 */
Authentication.Token.prototype.getRequestCredentials = function() {
	var ret = [];

	for (var param in this.resource.request.description.input.parameters) {
		if (param != "lifetime" && param != "interval")
			ret.push(param);
	}

	return ret;
}

/**
 * Return names of parameters used as credentials for custom authentication
 * action
 * @method HaveAPI.Client.Authentication.Token#getCustomActionCredentials
 * @private
 * @return {Array}
 */
Authentication.Token.prototype.getCustomActionCredentials = function(action) {
	var ret = {};
	var desc = this.resource[action].description.input.parameters;

	for (var param in desc) {
		if (param != "token")
			ret[param] = desc[param];
	}

	return ret;
}

/**
 * @class BaseResource
 * @classdesc Base class for {@link HaveAPI.Client.Resource}
 * and {@link HaveAPI.Client.ResourceInstance}. Implements shared methods.
 * @memberof HaveAPI.Client
 */
function BaseResource (){};

/**
 * Attach child resources as properties.
 * @method HaveAPI.Client.BaseResource#attachResources
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachResources = function(description, args) {
	this.resources = [];

	for(var r in description.resources) {
		this[r] = new Client.Resource(this._private.client, this, r, description.resources[r], args);
		this.resources.push(this[r]);
	}
};

/**
 * Attach child actions as properties.
 * @method HaveAPI.Client.BaseResource#attachActions
 * @protected
 * @param {Object} description
 * @param {Array} args
 */
BaseResource.prototype.attachActions = function(description, args) {
	this.actions = [];

	for(var a in description.actions) {
		var names = [a].concat(description.actions[a].aliases);
		var actionInstance = new Client.Action(this._private.client, this, a, description.actions[a], args);

		for(var i = 0; i < names.length; i++) {
			if (names[i] == 'new')
				continue;

			this[names[i]] = actionInstance;
		}

		this.actions.push(a);
	}
};

/**
 * Return default parameters that are to be sent to the API.
 * Default parameters are overriden by supplied parameters.
 * @method HaveAPI.Client.BaseResource#defaultParams
 * @protected
 * @param {HaveAPI.Client.Action} action
 */
BaseResource.prototype.defaultParams = function(action) {
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
 * @class Resource
 * @memberof HaveAPI.Client
 */
function Resource (client, parent, name, description, args) {
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
	var fn = function() {
		return new Resource(
			that._private.client,
			that._private.parent,
			that._private.name,
			that._private.description,
			that._private.args.concat(Array.prototype.slice.call(arguments))
		);
	};
	fn.__proto__ = this;

	return fn;
};

Resource.prototype = new BaseResource();

// Unused
Resource.prototype.applyArguments = function(args) {
	for(var i = 0; i < args.length; i++) {
		this._private.args.push(args[i]);
	}

	return this;
};

/**
 * Return a new, empty resource instance.
 * @method HaveAPI.Client.Resource#new
 * @return {HaveAPI.Client.ResourceInstance} resource instance
 */
Resource.prototype.new = function() {
	return new Client.ResourceInstance(this.client, this.parent, this.create, null, false);
};

/**
 * @class Action
 * @memberof HaveAPI.Client
 */
function Action (client, resource, name, description, args) {
	if (client._private.debug > 10)
		console.log("Attach action", name, "to", resource._private.name);

	this.client = client;
	this.resource = resource;
	this.name = name;
	this.description = description;
	this.args = args;
	this.providedIdArgs = [];
	this.preparedPath = null;

	var that = this;
	var fn = function() {
		var new_a = new Action(
			that.client,
			that.resource,
			that.name,
			that.description,
			that.args.concat(Array.prototype.slice.call(arguments))
		);
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
Action.prototype.httpMethod = function() {
	return this.description.method;
};

/**
 * Returns action's namespace.
 * @method HaveAPI.Client.Action#namespace
 * @param {String} direction input/output
 * @return {String}
 */
Action.prototype.namespace = function(direction) {
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
Action.prototype.layout = function(direction) {
	if (this.description[direction])
		return this.description[direction].layout;

	return null;
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#provideIdArgs
 */
Action.prototype.provideIdArgs = function(args) {
	this.providedIdArgs = args;
};

/**
 * Set action path. This method should be used to set fully resolved
 * path.
 * @method HaveAPI.Client.Action#providePath
 */
Action.prototype.providePath = function(path) {
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
 *   onReply: function (c, reply) {
 *     console.log('The server has returned a response, the action is being executed.');
 *   },
 *   onStateChange: function  (c, reply, state) {
 *     console.log(
 *       "The action's state has changed, current progress:",
 *       state.progress.toString()
 *     );
 *   },
 *   onDone: function (c, reply) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 * @example
 * // If the API server supports it, blocking actions can be cancelled
 * api.vps.restart(101, {
 *   onReply: function (c, reply) {
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
 *   onDone: function (c, reply) {
 *     console.log('The action is finished');
 *   }
 * });
 *
 */
Action.prototype.invoke = function() {
	var prep = this.prepareInvoke(arguments);

	if (!prep.params.validate()) {
		prep.onReply(this.client, new LocalResponse(
			this,
			false,
			'invalid input parameters',
			prep.params.errors
		));
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
Action.prototype.directInvoke = function() {
	var prep = this.prepareInvoke(arguments);

	if (!prep.params.validate()) {
		prep.onReply(this.client, new LocalResponse(
			this,
			false,
			'invalid input parameters',
			prep.params.errors
		));
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
Action.prototype.prepareInvoke = function(new_args) {
	var args = this.args.concat(Array.prototype.slice.call(new_args));
	var rx = /(\{[a-zA-Z0-9\-_]+\})/;

	if (!this.preparedPath)
		this.preparedPath = this.description.path;

	// First, apply ids returned from the API
	for (var i = 0; i < this.providedIdArgs.length; i++) {
		if (this.preparedPath.search(rx) == -1)
			break;

		this.preparedPath = this.preparedPath.replace(rx, this.providedIdArgs[i]);
	}

	// Apply ids passed as arguments
	while (args.length > 0) {
		if (this.preparedPath.search(rx) == -1)
			break;

		var arg = args.shift();
		this.providedIdArgs.push(arg);

		this.preparedPath = this.preparedPath.replace(rx, arg);
	}

	if (args.length == 0 && this.preparedPath.search(rx) != -1) {
		console.log("UnresolvedArguments", "Unable to execute action '"+ this.name +"': unresolved arguments");

		throw new Client.Exceptions.UnresolvedArguments(this);
	}

	var that = this;
	var params = this.prepareParams(args);

	// Add default parameters from object instance
	if (this.layout('input') === 'object') {
		var defaults = this.resource.defaultParams(this);

		for (var param in this.description.input.parameters) {
			if ( defaults.hasOwnProperty(param) && (
					 !params.params || (params.params && !params.params.hasOwnProperty(param))
				 )) {
				if (!params.params)
					params.params = {};

				params.params[ param ] = defaults[ param ];
			}
		}
	}

	return Object.assign({}, params, {
		params: new Parameters(this, params.params),
		onReply: function(c, response) {
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
		if (typeof(args[0]) === 'function') {
			// The one parameter is a callback -- no input parameters given
			return {onReply: args[0]};
		}

		var params = this.separateMetaParams(args[0]);

		return {
			params: params.params,
			meta: params.meta
		};

		var ret = {};

		if (opts.meta) {
			ret.meta = opts.meta;
			delete opts.meta;
		}

		ret.params = opts;

		return ret;
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

		} else {
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
				throw new Client.Exceptions.UncancelableAction(opts.id);

			return opts.client.action_state.cancel(
				opts.id,
				Object.assign({}, opts, state.cancelOpts)
			);
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
 * @class ActionState
 * @memberof HaveAPI.Client
 */
function ActionState (state) {
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
ActionState.Progress = function (state) {
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

/**
 * @class Response
 * @memberof HaveAPI.Client
 */
function Response (action, response) {
	this.action = action;
	this.envelope = response;
};

/**
 * Returns true if the request was successful.
 * @method HaveAPI.Client.Response#isOk
 * @return {Boolean}
 */
Response.prototype.isOk = function() {
	return this.envelope.status;
};

/**
 * Returns the namespaced response if possible.
 * @method HaveAPI.Client.Response#response
 * @return {Object} response
 */
Response.prototype.response = function() {
	if(!this.action)
		return this.envelope.response;

        if (!this.envelope.response)
            return null;

	switch (this.action.layout('output')) {
		case 'object':
		case 'object_list':
		case 'hash':
		case 'hash_list':
			return this.envelope.response[ this.action.namespace('output') ];

		default:
			return this.envelope.response;
	}
};

/**
 * Return the error message received from the API.
 * @method HaveAPI.Client.Response#message
 * @return {String}
 */
Response.prototype.message = function() {
	return this.envelope.message;
};

/**
 * Return the global meta data.
 * @method HaveAPI.Client.Response#meta
 * @return {Object}
 */
Response.prototype.meta = function() {
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
function LocalResponse (action, status, message, errors) {
	this.action = action;
	this.envelope = {
		status: status,
		message: message,
		errors: errors,
	};
};

LocalResponse.prototype = new Response();

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
function ResourceInstance (client, parent, action, response, shell, item) {
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

			action.directInvoke(function(c, response) {
				that.attachResources(that._private.action.resource._private.description, response.meta().path_params);
				that.attachActions(that._private.action.resource._private.description, response.meta().path_params);
				that.attachAttributes(response.response());

				that._private.resolved = true;

				if (that._private.resolveCallbacks !== undefined) {
					for (var i = 0; i < that._private.resolveCallbacks.length; i++)
						that._private.resolveCallbacks[i](that._private.client, that);

					delete that._private.resolveCallbacks;
				}
			});

		} else { // a new, empty instance
			this._private.resolved = true;
			this._private.persistent = false;

			this.attachResources(this._private.action.resource._private.description, action.providedIdArgs);
			this.attachActions(this._private.action.resource._private.description, action.providedIdArgs);
			this.attachStubAttributes();
		}

	} else if (item || response.isOk()) {
		this._private.resolved = true;
		this._private.persistent = true;

		var metaNs = client.apiSettings.meta.namespace;
		var idArgs = item ? response[metaNs].path_params : response.meta().path_params;

		this.attachResources(this._private.action.resource._private.description, idArgs);
		this.attachActions(this._private.action.resource._private.description, idArgs);
		this.attachAttributes(item ? response : response.response());

	} else {
		// FIXME
	}
};

ResourceInstance.prototype = new BaseResource();

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
ResourceInstance.prototype.isOk = function() {
	return this._private.response.isOk();
};

/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstance#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstance.prototype.apiResponse = function() {
	return this._private.response;
};

/**
 * Save the instance. It calls either an update or a create action,
 * depending on whether the object is persistent or not.
 * @method HaveAPI.Client.ResourceInstance#save
 * @param {HaveAPI.Client~replyCallback} callback
 */
ResourceInstance.prototype.save = function(callback) {
	var that = this;

	function updateAttrs(attrs) {
		for (var attr in attrs) {
			that._private.attributes[ attr ] = attrs[ attr ];
		}
	};

	function replyCallback(c, reply) {
		that._private.response = reply;
		updateAttrs(reply);

		if (callback !== undefined)
			callback(c, that);
	}

	if (this._private.persistent) {
		this.update.directInvoke(replyCallback);

	} else {
		this.create.directInvoke(function(c, reply) {
			if (reply.isOk())
				that._private.persistent = true;

			replyCallback(c, reply);
		});
	}
};

ResourceInstance.prototype.defaultParams = function(action) {
	ret = {}

	for (var attr in this._private.attributes) {
		var desc = action.description.input.parameters[ attr ];

		if (desc === undefined)
			continue;

		switch (desc.type) {
			case 'Resource':
				ret[ attr ] = this._private.attributes[ attr ][ desc.value_id ];
				break;

			default:
				ret[ attr ] = this._private.attributes[ attr ];
		}
	}

	return ret;
};

/**
 * Resolve an associated resource.
 * A shell {@link HaveAPI.Client.ResourceInstance} instance is created
 * and is fetched asynchronously.
 * @method HaveAPI.Client.ResourceInstance#resolveAssociation
 * @private
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstance.prototype.resolveAssociation = function(attr, resourcePath, path) {
	var tmp = this._private.client;

	for(var i = 0; i < resourcePath.length; i++) {
		tmp = tmp[ resourcePath[i] ];
	}

	var obj = this._private.attributes[ attr ];
	var metaNs = this._private.client.apiSettings.meta.namespace;
	var action = tmp.show;
	action.provideIdArgs(obj[metaNs].path_params);

	if (obj[metaNs].resolved)
		return new Client.ResourceInstance(
			this._private.client,
			action.resource._private.parent,
			action,
			obj,
			false,
			true
		);

	return new Client.ResourceInstance(
		this._private.client,
		action.resource._private.parent,
		action,
		null,
		true
	);
};

/**
 * Register a callback that will be called then this instance will
 * be fully resolved (fetched from the API).
 * @method HaveAPI.Client.ResourceInstance#whenResolved
 * @param {HaveAPI.Client.ResourceInstance~resolveCallback} callback
 */
ResourceInstance.prototype.whenResolved = function(callback) {
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
ResourceInstance.prototype.attachAttributes = function(attrs) {
	this._private.attributes = attrs;
	this._private.associations = {};

	var metaNs = this._private.client.apiSettings.meta.namespace;

	for (var attr in attrs) {
		if (attr === metaNs)
			continue;

		this.createAttribute(attr, this._private.action.description.output.parameters[ attr ]);
	}
};

/**
 * Attach all attributes as null properties. Used when creating a new, empty instance.
 * @method HaveAPI.Client.ResourceInstance#attachStubAttributes
 * @private
 */
ResourceInstance.prototype.attachStubAttributes = function() {
	var attrs = {};
	var params = this._private.action.description.input.parameters;

	for (var attr in params) {
		switch (params[ attr ].type) {
			case 'Resource':
				attrs[ attr ] = {};
				attrs[ attr ][ params[attr].value_id ] = null;
				attrs[ attr ][ params[attr].value_label ] = null;
				break;

			default:
				attrs[ attr ] = null;
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
ResourceInstance.prototype.createAttribute = function(attr, desc) {
	var that = this;

	switch (desc.type) {
		case 'Resource':
			Object.defineProperty(this, attr, {
				get: function() {
						if (that._private.associations.hasOwnProperty(attr))
							return that._private.associations[ attr ];

						return that._private.associations[ attr ] = that.resolveAssociation(
							attr,
							desc.resource,
							that._private.attributes[ attr ].path
						);
					},
				set: function(v) {
						that._private.attributes[ attr ][ desc.value_id ]    = v.id;
						that._private.attributes[ attr ][ desc.value_label ] = v[ desc.value_label ];
					}
			});

			Object.defineProperty(this, attr + '_id', {
				get: function()  { return that._private.attributes[ attr ][ desc.value_id ];  },
				set: function(v) { that._private.attributes[ attr ][ desc.value_id ] = v;     }
			});

			break;

		default:
			Object.defineProperty(this, attr, {
				get: function()  { return that._private.attributes[ attr ];  },
				set: function(v) { that._private.attributes[ attr ] = v;     }
			});
	}
};

/**
 * Arguments are the same as for {@link HaveAPI.Client.ResourceInstance}.
 * @class ResourceInstanceList
 * @classdesc Represents a list of {@link HaveAPI.Client.ResourceInstance} objects.
 * @see {@link HaveAPI.Client.ResourceInstance}
 * @memberof HaveAPI.Client
 */
function ResourceInstanceList (client, action, response) {
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
		this.items.push(new Client.ResourceInstance(
			client,
			action.resource._private.parent,
			action,
			ret[i],
			false,
			true
		));
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
ResourceInstanceList.prototype.isOk = function() {
	return this.response.isOk();
};

/**
 * Return the response that this instance is created from.
 * @method HaveAPI.Client.ResourceInstanceList#apiResponse
 * @return {HaveAPI.Client.Response}
 */
ResourceInstanceList.prototype.apiResponse = function() {
	return this.response;
};

/**
 * Call fn for every item in the list.
 * @param {HaveAPI.Client.ResourceInstanceList~iteratorCallback} fn
 * @method HaveAPI.Client.ResourceInstanceList#each
 */
ResourceInstanceList.prototype.each = function(fn) {
	for (var i = 0; i < this.length; i++)
		fn( this.items[ i ] );
};

/**
 * Return item at index.
 * @method HaveAPI.Client.ResourceInstanceList#itemAt
 * @param {Integer} index
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.itemAt = function(index) {
	return this.items[ index ];
};

/**
 * Return first item.
 * @method HaveAPI.Client.ResourceInstanceList#first
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.first = function() {
	if (this.length == 0)
		return null;

	return this.items[0];
};

/**
 * Return last item.
 * @method HaveAPI.Client.ResourceInstanceList#last
 * @return {HaveAPI.Client.ResourceInstance}
 */
ResourceInstanceList.prototype.last = function() {
	if (this.length == 0)
		return null;

	return this.items[ this.length - 1 ]
};

/**
 * @class Parameters
 * @private
 * @param {HaveAPI.Client.Action} action
 * @param {Object} input parameters
 */
function Parameters (action, params) {
	this.action = action;
	this.params = this.coerceParams(params);

	/**
	 * @member {Object} Parameters#errors Errors found during the validation.
	 */
	this.errors = {};
}

/**
 * Coerce parameters passed to the action to appropriate types.
 * @method Parameters.coerceParams
 * @param {Object} params
 * @return {Object}
 */
Parameters.prototype.coerceParams = function (params) {
	var ret = {};

	if (this.action.description.input === null)
		return ret;

	var input = this.action.description.input.parameters;

	for (var p in params) {
		if (!params.hasOwnProperty(p) || !input.hasOwnProperty(p))
			continue;

		var v = params[p];

		switch (input[p].type) {
			case 'Resource':
				if (params[p] instanceof ResourceInstance)
					ret[p] = v.id;

				else
					ret[p] = v;

				break;

			case 'Integer':
				ret[p] = parseInt(v);
				break;

			case 'Float':
				ret[p] = parseFloat(v);
				break;

			case 'Boolean':
				switch (typeof v) {
					case 'boolean':
						ret[p] = v;
						break;

					case 'string':
						if (v.match(/^(t|true|yes|y)$/i))
							ret[p] = true;

						else if (v.match(/^(f|false|no|n)$/i))
							ret[p] = false;

						else
							ret[p] = undefined;

						break;

					case 'number':
						if (v === 0)
							ret[p] = false;

						else if (v >= 1)
							ret[p] = true;

						else
							ret[p] = undefined;

						break;

					default:
						ret[p] = undefined;
				}

				break;

			case 'Datetime':
				if (v instanceof Date)
					ret[p] = v.toISOString();

				else
					ret[p] = v;

				break;

			case 'String':
			case 'Text':
				ret[p] = v + "";

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

	var input = this.action.description.input.parameters;

	for (var name in input) {
		if (!input.hasOwnProperty(name))
			continue;

		var p = input[name];

		if (!p.validators)
			continue;

		if (!this.params.hasOwnProperty(name) || this.params[name] === undefined) {
			if (p.validators.present)
				this.errors[name] = ['required parameter missing'];

			continue;
		}

		for (var validatorName in p.validators) {
			var validator = Validator.get(
				validatorName,
				p.validators[validatorName],
				this.params[name],
				this.params
			);

			if (validator === false) {
				console.log("Unsupported validator '"+ validatorName +"' for parameter '"+ name +"'");
				continue;
			}

			if (!validator.isValid()) {
				if (!this.errors.hasOwnProperty(name))
					this.errors[name] = [];

				this.errors[name] = this.errors[name].concat(validator.errors);
			}
		}
	}

	return Object.keys(this.errors).length ? false : true;
};

/**
 * @class Validator
 * @private
 * @param {Function} fn validator function
 * @param {Object} opts validator options from API description
 * @param value the value to validate
 * @param {Object} params object with all parameters
 */
function Validator (fn, opts, value, params) {
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

Validator.validators.accept = function (opts, value) {
	return opts.value === value;
};

Validator.validators.confirm = function (opts, value, params) {
	var cond = value === params[ opts.parameter ];

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
		if ( (v - (typeof opts.min === 'number' ? opts.min : 0)) % opts.step > 0 )
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

/**
 * Thrown when protocol error/incompatibility occurs.
 * @class ProtocolError
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.ProtocolError = function (msg) {
	this.name = 'ProtocolError';
	this.message = msg;
}

/**
 * Thrown when calling an action and some arguments are left unresolved.
 * @class UnresolvedArguments
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.UnresolvedArguments = function (action) {
	this.name = 'UnresolvedArguments';
	this.message = "Unable to execute action '"+ action.name +"': unresolved arguments";
}

/**
 * Thrown when trying to cancel an action that cannot be cancelled.
 * @class UncancelableAction
 * @memberof HaveAPI.Client.Exceptions
 */
Client.Exceptions.UncancelableAction = function (stateId) {
	this.name = 'UncancelableAction';
	this.message = "Action state #"+ stateId +" cannot be cancelled";
}

/**
 * @namespace HaveAPI
 * @author Jakub Skokan <jakub.skokan@vpsfree.cz>
 **/

var XMLHttpRequest;

if (typeof exports === 'object' && (typeof window === 'undefined' || !window.XMLHttpRequest)) {
	XMLHttpRequest = require('xmlhttprequest').XMLHttpRequest;

} else {
	XMLHttpRequest = window.XMLHttpRequest;
}

// Register built-in providers
Authentication.registerProvider('basic', Authentication.Basic);
Authentication.registerProvider('oauth2', Authentication.OAuth2);
Authentication.registerProvider('token', Authentication.Token);

var classes = [
	'Action',
	'ActionState',
	'Authentication',
	'BaseResource',
	'Hooks',
	'Http',
	'Resource',
	'ResourceInstance',
	'ResourceInstanceList',
	'Response',
	'LocalResponse',
];

for (var i = 0; i < classes.length; i++)
	Client[ classes[i] ] = eval(classes[i]);

var HaveAPI = {
	Client: Client
};

return HaveAPI;
}));
