(function ($) {

	var anchor;

	function showProperties (init) {
		anchor.text('Hide advanced options').click(switchMode(hideProperties));

		if (init)
			$('.advanced-option').css('display', 'table-row');

		else {
			$('.advanced-option').fadeIn({
				duration: 'slow',
				start: function () { this.style.display = 'table-row'; }
			});
			setState('more');
		}
	}

	function hideProperties (init) {
		anchor.text('Show advanced options').click(switchMode(showProperties));

		if (init)
			$('.advanced-option').hide();

		else {
			setState('less');
			$('.advanced-option').fadeOut();
		}
	}

	function switchMode (fn) {
		return function (e) {
			anchor.off('click');
			e.preventDefault();
			return fn();
		}
	}

	function setState (mode) {
		if (history.replaceState)
			history.replaceState(null, null, '#'+mode);
	}

	$(document).ready(function () {
		anchor = $('<a>').attr('href', '#');

		$('.advanced-option-toggle').append(anchor);

		if (location.hash === '#more')
			showProperties(true);
		else
			hideProperties(true);
	});

})(jQuery);
