function vncPopupFeatures() {
	return 'toolbar=no,menubar=no,location=no,status=no,scrollbars=yes,resizable=yes,width=1200,height=900';
}

function handleVncLinkClick(e) {
	var link = e.currentTarget;
	var veid = link.dataset.vpsId || new URL(link.href, window.location.href).searchParams.get('vps_id') || new URL(link.href, window.location.href).searchParams.get('veid');
	var server =
		(link.dataset.vncServer || new URL(link.href, window.location.href).searchParams.get('vnc_server') || '').replace(
			/\/+$/,
			''
		);

	if (!veid || !server) {
		return true;
	}

	e.preventDefault();

	var popup = window.open('about:blank', 'vpsadmin-vnc-' + veid, vncPopupFeatures());

	if (!popup) {
		return true;
	}

	// Drop reference to opener for safety once we have the handle
	popup.opener = null;

	popup.document.write('<p style="font-family: sans-serif; padding: 1em;">Loading VNC console...</p>');

	apiClient.after('authenticated', function () {
		var authType =
			window.vpsAdmin && window.vpsAdmin.accessToken
				? 'oauth2'
				: window.vpsAdmin && window.vpsAdmin.sessionToken
					? 'token'
					: '';
		var authToken =
			authType === 'oauth2'
				? (window.vpsAdmin ? window.vpsAdmin.accessToken : '')
				: authType === 'token'
					? (window.vpsAdmin ? window.vpsAdmin.sessionToken : '')
					: '';
		var apiUrl = window.vpsAdmin && window.vpsAdmin.api ? window.vpsAdmin.api.url : '';
		var apiVersion = window.vpsAdmin && window.vpsAdmin.api ? window.vpsAdmin.api.version : '';

		var params = new URLSearchParams();
		params.set('vps_id', veid);
		if (authType && authToken) {
			params.set('auth_type', authType);
			params.set('auth_token', authToken);
		}
		if (apiUrl) params.set('api_url', apiUrl);
		if (apiVersion) params.set('api_version', apiVersion);

		var url = server + '/console?' + params.toString();
		popup.location.href = url;
		popup.focus();
	});
}

$(document).ready(function () {
	$(document).on('click', '.vnc-link, a[href*="page=vnc"]', handleVncLinkClick);
});
