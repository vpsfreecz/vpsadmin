<?php

if (isset($_SESSION["logged_in"]) && $_SESSION["logged_in"]) {

	list_object_history();

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
