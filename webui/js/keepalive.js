(function() {
	var interval = 5*60*1000;

	function keepAlive() {
		var http = new XMLHttpRequest();

		http.open('GET', vpsAdmin.webui.url + "/keepalive.php", true);

		http.onreadystatechange = function() {
			if (http.readyState == 4) {
				scheduleKeepAlive();
			}
		}

		http.send();
	}

	function scheduleKeepAlive() {
		setTimeout(function() {
			keepAlive();
		}, interval);
	}

	api.after('authenticated', function() {
		scheduleKeepAlive();
	});
})();
