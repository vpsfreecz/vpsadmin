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
		apiClient.vps.vnc_token.create(veid, {
			onReply: function (c, vncToken) {
				if (!vncToken.isOk()) {
					popup.close();
					alert('Unable to open VNC console: ' + vncToken.message());
					return;
				}

				var token = vncToken.client_token;
				var url = server + '/console?client_token=' + encodeURIComponent(token);
				popup.location.href = url;
				popup.focus();
			},
		});
	});
}

$(document).ready(function () {
	$(document).on('click', '.vnc-link, a[href*="page=vnc"]', handleVncLinkClick);
});
