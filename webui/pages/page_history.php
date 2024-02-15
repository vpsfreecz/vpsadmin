<?php

if (isLoggedIn()) {

    list_object_history();

} else {
    $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
