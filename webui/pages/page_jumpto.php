<?php

if (isLoggedIn() && isAdmin()) {
	$search = trim($_GET['search']);

	$_SESSION["jumpto"] = $search;

	try {
		$res = $api->cluster->search(array('value' => $search))->getResponse();

		if (count($res) === 1) {
			$v = $res[0];

			switch ($v->resource) {
			case 'User':
				redirect('?page=adminm&action=edit&id='.$v->id);
				break;

			case 'Vps':
				redirect('?page=adminvps&action=info&veid='.$v->id);
				break;
			}
		}

		if (count($res)) {
			$xtpl->title(_('Found these bros'));
			$xtpl->table_add_category(_('Resource'));
			$xtpl->table_add_category(_('ID'));
			$xtpl->table_add_category(_('Attribute'));
			$xtpl->table_add_category(_('Value'));

			foreach ($res as $v) {
				$xtpl->table_td($v->resource);

				$link = null;

				switch ($v->resource) {
				case 'User':
					$link = '?page=adminm&action=edit&id='.$v->id;
					break;

				case 'Vps':
					$link = '?page=adminvps&action=info&veid='.$v->id;
					break;

				case 'Export':
					$link = '?page=export&action=edit&export='.$v->id;
					break;

				case 'TransactionChain':
					$link = '?page=transactions&chain='.$v->id;
					break;
				}

				$xtpl->table_td($link ? '<a href="'.$link.'">'.$v->id.'</a>' : $v->id);
				$xtpl->table_td($v->attribute);
				$xtpl->table_td(preg_replace_callback(
					"/(".preg_quote($search).")/i",
					function ($matches) {
						return "<strong>".htmlspecialchars($matches[0])."</strong>";
					},
					$v->value
				));
				$xtpl->table_tr();
			}

			$xtpl->table_out();

		} else {
			$xtpl->title('Not a bro to be found.');
		}

	} catch (\HaveAPI\Client\Exception\ActionFailed $e) {
		// nothing
	}

} else {
	$xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
}
