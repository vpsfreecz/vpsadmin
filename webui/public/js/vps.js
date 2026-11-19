function vpsConfirmAction(action, vpsId, hostname) {
	return confirm(
		"Do you really wish to " + action + " VPS " + vpsId + " " +
		"- " + hostname + "?"
	);
}

function toggleUserDataRows() {
	$('.user-data').hide();

	let selected = $('input[name="user_data_type"]:checked').val();

	if (selected === 'saved') $('.user-data.saved').fadeIn();
	if (selected === 'custom') $('.user-data.custom').fadeIn();
}

$(document).ready(function() {
	$('input[name="user_data_type"]').on('change', toggleUserDataRows);

	toggleUserDataRows();
});

function incidentLimitUnit(input) {
    const unit = input.siblings('[data-incident-unit]');
    // The supported EN/CS report units distinguish only one from other numbers.
    unit.text(unit.attr(input.val() === '1' ? 'data-one' : 'data-other'));
}

$(document).on('input', 'form[name^="incident-policy-"] input[type="number"]', function() {
    incidentLimitUnit($(this));
});
