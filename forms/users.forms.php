<?php

function environment_configs($user_id) {
	global $xtpl, $api;
	
	$cfgs = $api->user($user_id)->environment_config->list(array(
		'meta' => array('includes' => 'environment')
	));
	
	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user_id.'">#'.$user_id.'</a>: '._('Environment configs'));
	
	$xtpl->table_add_category(_('Environment'));
	$xtpl->table_add_category(_('Create VPS'));
	$xtpl->table_add_category(_('Destroy VPS'));
	$xtpl->table_add_category(_('VPS count'));
	$xtpl->table_add_category(_('VPS lifetime'));
	
	if ($_SESSION['is_admin']) {
		$xtpl->table_add_category(_('Default'));
		$xtpl->table_add_category('');
	}
	
	foreach ($cfgs as $c) {
		$vps_count = $api->vps->list(array(
			'limit' => 0,
			'environment' => $c->environment_id,
			'user' => $user_id,
			'meta' => array('count' => true)
		));

		$xtpl->table_td($c->environment->label);
		$xtpl->table_td(boolean_icon($c->can_create_vps));
		$xtpl->table_td(boolean_icon($c->can_destroy_vps));
		$xtpl->table_td(
			$vps_count->getTotalCount() .' / '. $c->max_vps_count,
			false,
			true
		);
		$xtpl->table_td($c->vps_lifetime, false, true);
		
		if ($_SESSION['is_admin']) {
			$xtpl->table_td(boolean_icon($c->default));
			$xtpl->table_td('<a href="?page=adminm&section=members&action=env_cfg_edit&id='.$user_id.'&cfg='.$c->id.'"><img src="template/icons/m_edit.png"  title="'._("Edit").'"></a>');
		}
		
		$xtpl->table_tr();
	}
	
	$xtpl->table_out();
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to user details").'" />'._('Back to user details'), "?page=adminm&section=members&action=edit&id=$user_id");
}

function env_cfg_edit_form($user_id, $cfg_id) {
	global $xtpl, $api;
	
	$cfg = $api->user($user_id)->environment_config->find($cfg_id, array(
		'meta' => array('includes' => 'environment')
	));
	
	$xtpl->title(_('User').' <a href="?page=adminm&action=edit&id='.$user_id.'">#'.$user_id.'</a>: '._('Environment config for').' '.$cfg->environment->label);
	
	$xtpl->form_create("?page=adminm&action=env_cfg_edit&id=$user_id&cfg=$cfg_id");
	
	$xtpl->table_td(_('Environment'));
	$xtpl->table_td($cfg->environment->label);
	$xtpl->table_tr();
	
	api_update_form($cfg);
	
	$xtpl->form_out(_('Save'));
	
	$xtpl->sbar_add('<br><img src="template/icons/m_edit.png"  title="'._("Back to environment configs").'" />'._('Back to user details'), "?page=adminm&section=members&action=env_cfg&id=$user_id");
}
