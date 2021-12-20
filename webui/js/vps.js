function vpsConfirmAction(action, vpsId, hostname) {
	return confirm(
		"Do you really wish to " + action + " VPS " + vpsId + " " +
		"- " + hostname + "?"
	);
}
