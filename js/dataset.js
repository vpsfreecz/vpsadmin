(function ($) {

	var anchor;

	function showProperties (init) {
		anchor.text('Hide properties').click(switchMode(hideProperties));

		if (init)
			$('.advanced-property').css('display', 'table-row');

		else {
			$('.advanced-property').fadeIn({
				duration: 'slow',
				start: function () { this.style.display = 'table-row'; }
			});
			setState('more');
		}
	}

	function hideProperties (init) {
		anchor.text('Show more properties').click(switchMode(showProperties));
		
		if (init)
			$('.advanced-property').hide();
			
		else {
			setState('less');
			$('.advanced-property').fadeOut();
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

		$('.advanced-property-toggle').append(anchor);

		if (location.hash === '#more')
			showProperties(true);
		else
			hideProperties(true);
	});

})(jQuery);
