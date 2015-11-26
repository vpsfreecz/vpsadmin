(function ($) {

	var defaults = {
		duration: 1500,
		immediate: true,
		checkInterval: 100
	};
	
	$.event.special.longclick = {
		add: function (handleObj) {
			opts = $.extend({}, defaults, handleObj.data === undefined ? {} : handleObj.data);

			registerLongClick(
				this,
				opts.duration,
				handleObj.handler,
				opts.immediate,
				opts.checkInterval
			);
		},

		remove: function (handleObj) {
			if (this.removeLongClick !== undefined)
				this.removeLongClick.call();
		}
	};

	$.fn.longclick = function (duration, cb, immediate, checkInterval) {
		return this.on('longclick', {
			duration: duration,
			immediate: immediate,
			checkInterval: checkInterval
		}, cb);
	};

	function registerLongClick(element, duration, cb, immediate, interval) {
		var pressTime;
		var isDown;
		var isLong;
		var timer;
		var called;
		var isImmediate = immediate !== undefined && immediate;
		var j = $(element);

		function checkIsLong () {
			var now = new Date().getTime();
			return (now - pressTime) >= duration;
		}

		function mouseDown () {
			pressTime = new Date().getTime();
			isDown = true;
			isLong = false;
			called = false;

			if (isImmediate) {
				timer = setInterval(function () {
					if (!isDown)
						return;
					
					if (checkIsLong()) {
						isLong = true;
						clearInterval(timer);
						called = true;
						cb.call();
					}
				}, interval);

			} else {
				timer = false;
			}
		};

		function mouseUp () {
			isDown = false;

			if (timer)
				clearInterval(timer);

			if (!isLong && checkIsLong())
				isLong = true;
		};

		function click (e) {
			if (!isLong)
				return;

			e.stopImmediatePropagation();

			if (!called)
				cb.call();
		}

		j.mousedown(mouseDown);
		j.mouseup(mouseUp);
		j.click(click);

		element.removeLongClick = function () {
			j.off('mousedown', mouseDown).off('mouseup', mouseUp).off('click', click);

			if (isDown && isImmediate)
				clearInterval(timer);
		};
	}

})(jQuery);
