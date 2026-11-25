<?php

if (isLoggedIn()) {
    vps_evidence_page();
    $xtpl->sbar_add(_('VPS list'), '?page=adminvps&action=list');
    $xtpl->sbar_out(_('Memory pressure'));
} else {
    $xtpl->perex(_('Access forbidden'), _("You have to log in to be able to access vpsAdmin's functions"));
}
