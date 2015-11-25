(function(element) {
	function countDownTimer(time, step, timeout) {
		var lastTime = new Date().getTime();
		var end = lastTime + time;
		
		var update = function() {
			lastTime = new Date().getTime();
			var remaining = Math.floor((end - lastTime) / 1000);
			
			if (lastTime >= end || remaining === 0) {
				timeout();
				
			} else {
				step(remaining);
				
				var next = new Date();
				next.setMilliseconds(0);
				next.setSeconds( next.getSeconds() + 60 );
				
				setTimeout(update, (next.getTime() - lastTime));
			}
		};
		
		setTimeout(update, 60 * 1000);
	}

	function sessionCountdown(t) {
		document.getElementById(element).innerHTML = Math.floor(t / 60) + '&nbsp;min';
	}

	$(document).ready(function() {
		sessionCountdown(vpsAdmin.sessionLength);
		
		countDownTimer(vpsAdmin.sessionLength * 1000, sessionCountdown, function() {
			clearTimeout(chainTimeout);
			api.logout(function() {
				document.location = '?page=';
			});
		});
		
	});

})('session-countdown');
