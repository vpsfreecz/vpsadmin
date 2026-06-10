(function(root, $) {
	if (!$) {
		return;
	}

	function validTimeZoneMap(timeZones) {
		var ret = {};

		for (var i = 0; i < timeZones.length; i++) {
			ret[timeZones[i]] = true;
		}

		return ret;
	}

	function browserTimeZone() {
		if (!root.Intl || !root.Intl.DateTimeFormat) {
			return null;
		}

		var opts = root.Intl.DateTimeFormat().resolvedOptions();

		return opts && opts.timeZone ? opts.timeZone : null;
	}

	function responseMessage(response, fallback) {
		if (response && response.message && response.message()) {
			return response.message();
		}

		return fallback;
	}

	function setSaving($tip, saving) {
		$tip.toggleClass('webui-tip-saving', saving);
		$tip.find('button').prop('disabled', saving);
	}

	function showError($tip, message) {
		$tip.find('.webui-tip-error')
			.text(message)
			.addClass('webui-tip-error-visible');
	}

	function clearError($tip) {
		$tip.find('.webui-tip-error')
			.text('')
			.removeClass('webui-tip-error-visible');
	}

	function rememberTip(api, $tip, value, onSuccess, onFailure) {
		var namespace = $tip.attr('data-webui-tip-namespace');
		var key = $tip.attr('data-webui-tip-id');

		api.webui_user_setting.set.directInvoke(namespace, key, {
			value: value
		}, function(_client, response) {
			if (response.isOk()) {
				onSuccess();
				return;
			}

			onFailure(response);
		});
	}

	function syncSessionTimeZone(timeZone, onSuccess, onFailure) {
		var http = new XMLHttpRequest();
		var body = [
			'csrf_token=' + encodeURIComponent(root.vpsAdmin.csrf.sessionTimeZone),
			'time_zone=' + encodeURIComponent(timeZone || '')
		].join('&');

		http.open('POST', root.vpsAdmin.webui.url + '/session-time-zone.php', true);
		http.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');

		http.onreadystatechange = function() {
			var payload;

			if (http.readyState !== 4) {
				return;
			}

			if (http.status >= 200 && http.status < 300) {
				root.vpsAdmin.user.timeZone = timeZone || null;
				onSuccess();
				return;
			}

			try {
				payload = JSON.parse(http.responseText);
			} catch (_e) {
				payload = {};
			}

			onFailure(payload.message || root.vpsAdminTips.messages.syncTimeZoneFailed);
		};

		http.send(body);
	}

	function tipValue(action, browserZone, serverZone) {
		return {
			action: action,
			browser_time_zone: browserZone,
			server_time_zone: serverZone,
			dismissed_at: new Date().toISOString()
		};
	}

	function dismissTip(api, $tip, browserZone, serverZone) {
		clearError($tip);
		setSaving($tip, true);

		rememberTip(
			api,
			$tip,
			tipValue('dismiss', browserZone, serverZone),
			function() {
				$tip.addClass('webui-tip-hidden');
			},
			function(response) {
				setSaving($tip, false);
				showError(
					$tip,
					responseMessage(response, root.vpsAdminTips.messages.saveTipFailed)
				);
			}
		);
	}

	function useBrowserTimeZone(api, $tip, browserZone, serverZone) {
		clearError($tip);
		setSaving($tip, true);

		api.user.update.directInvoke(root.vpsAdmin.user.id, {
			time_zone: browserZone
		}, function(_client, response) {
			if (!response.isOk()) {
				setSaving($tip, false);
				showError(
					$tip,
					responseMessage(response, root.vpsAdminTips.messages.saveTimeZoneFailed)
				);
				return;
			}

			syncSessionTimeZone(
				browserZone,
				function() {
					rememberTip(
						api,
						$tip,
						tipValue('use_browser_time_zone', browserZone, serverZone),
						function() {
							root.location.reload();
						},
						function() {
							root.location.reload();
						}
					);
				},
				function(message) {
					setSaving($tip, false);
					showError($tip, message);
				}
			);
		});
	}

	function initTimeZoneTip(api, validTimeZones, serverEquivalentTimeZones) {
		var $tip = $('.webui-tip[data-webui-tip-id="time_zone_settings_v1"]');

		if (!$tip.length) {
			return;
		}

		var serverZone = $tip.attr('data-server-time-zone');
		var zone = browserTimeZone();

		if (
			!zone
			|| !validTimeZones[zone]
			|| zone === serverZone
			|| serverEquivalentTimeZones[zone]
		) {
			return;
		}

		if (
			!api.user
			|| !api.user.update
			|| !api.webui_user_setting
			|| !api.webui_user_setting.set
			|| !root.vpsAdmin.csrf
			|| !root.vpsAdmin.csrf.sessionTimeZone
		) {
			return;
		}

		$tip.find('.webui-tip-browser-time-zone').text(zone);
		$tip.removeClass('webui-tip-hidden');

		$tip.find('[data-webui-tip-action="dismiss"]').on('click', function(event) {
			event.preventDefault();
			dismissTip(api, $tip, zone, serverZone);
		});

		$tip.find('[data-webui-tip-action="use-browser-time-zone"]').on('click', function(event) {
			event.preventDefault();
			useBrowserTimeZone(api, $tip, zone, serverZone);
		});
	}

	$(function() {
		if (!root.vpsAdminTips || !root.vpsAdmin || !root.apiClient) {
			return;
		}

		initTimeZoneTip(
			root.apiClient,
			validTimeZoneMap(root.vpsAdminTips.validTimeZones || []),
			validTimeZoneMap(root.vpsAdminTips.serverEquivalentTimeZones || [])
		);
	});
})(window, window.jQuery);
