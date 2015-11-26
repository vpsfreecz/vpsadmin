(function(elementId) {
	var countdown;

	function countDownTimer(time, step, timeout) {
		this.lastTime = new Date().getTime();
		this.end = this.lastTime + time;
		this.step = step;
		this.timeout = timeout;
		
		var that = this;
		var tmp = function () {
			if (that.update())
				return;

			var next = new Date();
			next.setMilliseconds(0);
			next.setSeconds( next.getSeconds() + 60 );
			
			that.timer = setTimeout(tmp, (next.getTime() - that.lastTime));
		};

		this.timer = setTimeout(tmp, 60 * 1000);
	}

	countDownTimer.prototype.update = function () {
		this.lastTime = new Date().getTime();
		var remaining = Math.floor((this.end - this.lastTime) / 1000);
		
		if (this.lastTime >= this.end || remaining === 0) {
			this.timeout();
			return true;
			
		} else {
			this.step(remaining);
			return false;
		}
	};

	countDownTimer.prototype.stop = function () {
		clearTimeout(this.timer);
	};
	
	countDownTimer.prototype.extend = function (v) {
		this.end += v;
	};

	function sessionCountdown(t) {
		setValue(Math.floor(t / 60) + '&nbsp;min');
	}

	function stopSessionTimer() {
		countdown.stop();
		setValue('∞');
	}

	function setValue(v) {
		document.getElementById(elementId).innerHTML = v;
	}

	$(document).ready(function() {
		sessionCountdown(vpsAdmin.sessionLength);
		
		countdown = new countDownTimer(vpsAdmin.sessionLength * 1000, sessionCountdown, function() {
			clearTimeout(chainTimeout);
			api.logout(function() {
				document.location = '?page=';
			});
		});

		if (root.vpsAdmin.sessionManagement) {
			var el = $('#'+elementId);

			el.css('cursor', 'pointer');
			el.attr('title', 'Left-click - extend timeout; Long left-click - disable timeout');

			el.longclick(1500, function () {
				el.off('click').attr('title', '');
				setValue('disabled');
				setTimeout(stopSessionTimer, 1500);
			}, true);

			el.click(function () {
				countdown.extend(20*60*1000);
				countdown.update();
			});
		}
	});

})('session-countdown');
