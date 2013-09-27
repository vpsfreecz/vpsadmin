<?php
/*
    ./pages/page_adminm.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
function print_newm() {
	global $xtpl, $cfg_privlevel, $cluster_cfg;

	$xtpl->title(_("Add a member"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=new2', 'post');
	$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', '', _("A-Z, a-z, dot, dash"), 63);
	$xtpl->form_add_select(_("Privileges").':', 'm_level', $cfg_privlevel, '2',  ' ');

	$m_pass_uid  = $xtpl->form_add_input(_("Password").':', 'password', '30', 'm_pass', '', '', -5);
	$m_pass2_uid = $xtpl->form_add_input(_("Repeat password").':', 'password', '30', 'm_pass2', '', ' ');

	$xtpl->form_add_input('', 'button', '', 'g_pass', _("Generate password"), '', '', 'onClick="javascript:formSubmit()"');
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'm_name', '', _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'm_mail', '', ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'm_address', '', ' ');

	if ($cluster_cfg->get("payments_enabled")) {
		$xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', '300', ' ');
	}

	if ($cluster_cfg->get("mailer_enabled")) {
		$xtpl->form_add_checkbox(_("Enable vpsAdmin mailer").':', 'm_mailer_enable', '1', true, $hint = '');
	}
	
	$xtpl->form_add_checkbox(_("Enable playground VPS").':', 'm_playground_enable', '1', true, $hint = '');
	$xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', '', _("Note for administrators"));
	$xtpl->form_out(_("Add"));

	$xtpl->assign('SCRIPT', '
		<script type="text/javascript">
			<!--
				function randomPassword() {
					var length = 10;
					var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890";
  					var pass = "";

  					for(x=0; x<length; x++) {
  						i = Math.floor(Math.random() * 62);
    					pass += chars.charAt(i);
    				}

  					return pass;
				}

				function formSubmit() {
					var randpwd = randomPassword(8);
  					$("#'.$m_pass_uid.'").val(randpwd);
  					$("#'.$m_pass2_uid.'").val(randpwd);

  					return false;
				}
			-->
		</script>
	');
}

function print_editm($member) {
	global $xtpl, $cfg_privlevel, $cluster_cfg;

	$xtpl->title(_("Manage members"));
	
	$xtpl->table_add_category(_("Member"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=edit_member&id='.$_GET["id"], 'post');

	if ($member->m["m_created"]) {
	    $xtpl->table_td("Created".':');
	    $xtpl->table_td(strftime("%Y-%m-%d %H:%M", $member->m["m_created"]));
	    $xtpl->table_tr();
	}

	if ($_SESSION["is_admin"]) {
		$xtpl->table_add_category('&nbsp;');
		
		$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', $member->m["m_nick"], _("A-Z, a-z, dot, dash"), 63);
		$xtpl->form_add_select(_("Privileges").':', 'm_level', $cfg_privlevel, $member->m["m_level"],  '');
		
	} else {
		$xtpl->table_td(_("Nickname").':');
		$xtpl->table_td($member->m["m_nick"]);
		$xtpl->table_tr();

		$xtpl->table_td(_("Privileges").':');
		$xtpl->table_td($cfg_privlevel[$member->m["m_level"]]);
		$xtpl->table_tr();
	}
	
	if ($cluster_cfg->get("payments_enabled")) {
		$xtpl->table_td(_("Paid until").':');

		$paid = $member->has_paid_now();

		if ($_SESSION["is_admin"]) {

			if ($paid == (-1)) {

				$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
								. $member->mid
								. '">' . _("info. missing") . '</a>', '#FF8C00');

			} elseif ($paid == 0) {

				$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
								. $member->mid
								. '"><b>' . _("not paid!") . '</b></a>', '#B22222');
			} else {

				$paid_until = date('Y-m-d', $member->m["m_paid_until"]);

				if (($member->m["m_paid_until"] - time()) >= 604800) {
						$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
										. $member->mid
										. '">' . _("->") . ' ' . $paid_until . '</a>', '#66FF66');
				} else {
						$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='
										. $member->mid
										. '">' . _("->") . ' ' . $paid_until . '</a>', '#FFA500');
				}
			}
		} else {

			if ($paid == (-1)) {

				$xtpl->table_td(_("info. missing"), '#FF8C00');

			} elseif ($paid == 0) {

				$xtpl->table_td('<b>'._("not paid!").'</b>', '#B22222');

			} else {

				$paid_until = date('Y-m-d', $member->m["m_paid_until"]);

				if (($member->m["m_paid_until"] - time()) >= 604800) {

					$xtpl->table_td(_("->").' '.$paid_until, '#66FF66');

				} else {

					$xtpl->table_td(_("->").' '.$paid_until, '#FFA500');
				}
			}
		}
	}
	$xtpl->table_tr();
	
	if ($_SESSION["is_admin"]) {
		$xtpl->table_td(_("VPS count").':');
		$xtpl->table_td("<a href='?page=adminvps&m_nick=".$member->m["m_nick"]."'>".$member->get_vps_count()."</a>");
		$xtpl->table_tr();
	}

	if ($cluster_cfg->get("mailer_enabled")) {
		$xtpl->form_add_checkbox(_("Enable mail notifications from vpsAdmin").':', 'm_mailer_enable', '1', $member->m["m_mailer_enable"], $hint = '');
	}

	if ($_SESSION["is_admin"]) {
	    $xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', $member->m["m_monthly_payment"], ' ');
	    $xtpl->form_add_checkbox(_("Enable playground VPS").':', 'm_playground_enable', '1', $member->m["m_playground_enable"], $hint = '');
	    $xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', $member->m["m_info"], _("Note for administrators"));
	}
	
	$xtpl->form_out(_("Save"));
	
	$xtpl->table_add_category(_("Change password"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=passwd&id='.$_GET["id"], 'post');
	$xtpl->form_add_input(_("Password").':', 'password', '30', 'm_pass', '', '', -5);
	$xtpl->form_add_input(_("Repeat password").':', 'password', '30', 'm_pass2', '', '', -5);
	$xtpl->form_out(_("Save"));
	
	$xtpl->table_add_category(_("Personal information"));
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->form_create('?page=adminm&section=members&action=edit_personal&id='.$_GET["id"], 'post');
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'm_name', $_POST["m_name"] ? $_POST["m_name"] : $member->m["m_name"], _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'm_mail', $_POST["m_mail"] ? $_POST["m_mail"] : $member->m["m_mail"], ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'm_address', $_POST["m_address"] ? $_POST["m_address"] : $member->m["m_address"], ' ');

	if(!$_SESSION["is_admin"]) {
		$xtpl->form_add_input(_("Reason for change").':', 'text', '50', 'reason');
		$xtpl->table_td(_("Request for change will be sent to administrators for approval.".
		                  "Changes will not take effect immediately. You will be informed about the result."), false, false, 3);
		$xtpl->table_tr();
	}
	
	$xtpl->form_out($_SESSION["is_admin"] ? _("Save") : _("Request change"));
	
	if ($_SESSION["is_admin"] && $cluster_cfg->get("payments_enabled")) {
		if ($member->m["m_state"] == "active") {
			$xtpl->table_title(_("Suspend account"));
			$xtpl->table_add_category('&nbsp;');
			$xtpl->table_add_category('&nbsp;');
			$xtpl->form_create('?page=adminm&section=members&action=suspend&id='.$_GET["id"], 'post');
			$xtpl->form_add_input(_("Reason").':', 'text', '30', 'reason');
			$xtpl->form_add_checkbox(_("Stop all VPSes").':', 'stop_all_vpses', '1', true);
			$xtpl->form_add_checkbox(_("Notify member").':', 'notify', '1', true);
			$xtpl->form_out(_("Suspend"));
		} else {
			$xtpl->table_title(_("Account is suspended"));
			$xtpl->table_add_category('&nbsp;');
			$xtpl->table_add_category('&nbsp;');
			$xtpl->form_create('?page=adminm&section=members&action=restore&id='.$_GET["id"], 'post');
			$xtpl->table_td(_('Reason').':');
			$xtpl->table_td($member->m["m_suspend_reason"]);
			$xtpl->table_tr();
			$xtpl->form_add_checkbox(_("Start all VPSes").':', 'start_all_vpses', '1', true);
			$xtpl->form_add_checkbox(_("Notify member").':', 'notify', '1', true);
			$xtpl->form_out(_("Restore"));
		}
	}
	
	if ($_SESSION["is_admin"])
		print_deletem($member);
}

function print_deletem($member) {
	global $db, $xtpl;
	
	$xtpl->table_title(_("Delete member"));
	$xtpl->table_td(_("Full name").':');
	$xtpl->table_td($member->m["m_name"]);
	$xtpl->table_tr();
	$xtpl->form_create('?page=adminm&section=members&action=delete2&id='.$_GET["id"], 'post');
	$xtpl->table_td(_("VPSes to be deleted").':');
	
	$vpses = '';
	
	while ($vps = $db->findByColumn("vps", "m_id", $member->m["m_id"]))
		$vpses .= '<a href="?page=adminvps&action=info&veid='.$vps["vps_id"].'">#'.$vps["vps_id"].' - '.$vps["vps_hostname"].'</a><br>';
	
	$xtpl->table_td($vpses);
	$xtpl->table_tr();
	
	if($member->m["m_state"] != "deleted")
		$xtpl->form_add_checkbox(_("Lazy delete").':', 'lazy_delete', '1', true,
			_("Do not delete member and his VPSes immediately, but after passing of predefined time."));
	
	$xtpl->form_add_checkbox(_("Notify member").':', 'notify', '1', true);
	$xtpl->form_out(_("Delete"));
}

function request_approve() {
	global $db;
	
	if(!$_SESSION["is_admin"])
		return;
	
	$row = request_by_id($_GET["id"]);
	
	if(!$row)
		return;
	
	$data = null;
	
	if(isset($_POST["m_name"])) { // called from request details
		$data = $_POST;
		
	} else { // accessed from request list or mail
		$data = $row;
	}
	
	switch($row["m_type"]) {
		case "add":
			$data["m_level"] = PRIV_USER;
			$data["m_playground_enable"] = true;
			$data["m_mailer_enable"] = true;
			$data["m_info"] = "";
			$data["m_pass"] = random_string(10);
			
			$m = member_load();
			$m_id = $m->create_new($data);
			
			if(!isset($_POST["m_create_vps"]) || $_POST["m_create_vps"]) { // create vps
				$server = null;
				
				if($_POST["m_node"])
					$server = server_by_id($_POST["m_node"]);
				else
					$server = server_by_id(pick_free_node($data["m_location"]));
				
				$vps = vps_load();
				$vps->create_new($server["server_id"], $data["m_distribution"], "vps", $m_id, "");
				
				$mapping = nas_create_default_exports("vps", $vps->ve);
				nas_create_default_mounts($vps->ve, $mapping);
				
				$vps->add_default_configs("default_config_chain");
				
				if(!isset($_POST["m_assign_ips"]) || $_POST["m_assign_ips"]) {
					$vps->add_first_available_ip($server["server_location"], 4);
					$vps->add_first_available_ip($server["server_location"], 6);
				}
				
				$vps->start();
			}
			break;
		
		case "change":
			$db->query("UPDATE members SET
							m_name = '".$db->check($row["m_name"])."',
							m_mail = '".$db->check($row["m_mail"])."',
							m_address = '".$db->check($row["m_address"])."'
						WHERE m_id = ".$db->check($row["m_applicant"]));
			
			// mail user about the approval
			request_change_mail_member($row, "approved", $row["m_mail"]);
			break;
	}
	
	$db->query("UPDATE members_changes SET
	            m_state = 'approved',
	            m_changed_by = ".$db->check($_SESSION["member"]["m_id"]).",
	            m_admin_response = '".$db->check($data["m_admin_response"])."',
	            m_changed_at = ".time()."
	            WHERE m_id = ".$db->check($row["m_id"]));
	
	$row = request_by_id($_GET["id"]);
	
	// mail admins about the approval
	request_change_mail_admins($row, "approved");
	request_mail_last_update($row);
	
	notify_user(_("Request approved"), '');
	redirect('?page=adminm&section=members&action=approval_requests');
}

function request_deny() {
	global $db;
	
	if(!$_SESSION["is_admin"])
		return;
	
	$row = request_by_id($_GET["id"]);
	
	if(!$row)
		return;
	
	$data = null;
	
	if(isset($_POST["m_name"])) { // called from request details
		$data = $_POST;
		
	} else { // accessed from request list or mail
		$data = $row;
	}
	
	$db->query("UPDATE members_changes SET
	            m_state = 'denied',
	            m_changed_by = ".$db->check($_SESSION["member"]["m_id"]).",
	            m_admin_response = '".$db->check($data["m_admin_response"])."',
	            m_changed_at = ".time()."
	            WHERE m_id = ".$db->check($row["m_id"]));
	
	$row = request_by_id($_GET["id"]);
	
	// mail user about the denial
	// mail admins about the denial
	request_change_mail_all($row, "denied", $row["current_mail"]);
	
	notify_user(_("Request denied"), '');
	redirect('?page=adminm&section=members&action=approval_requests');
}

function request_invalidate() {
	global $db;
	
	if(!$_SESSION["is_admin"])
		return;
	
	$row = request_by_id($_GET["id"]);
	
	if(!$row)
		return;
	
	$data = null;
	
	if(isset($_POST["m_name"])) { // called from request details
		$data = $_POST;
		
	} else { // accessed from request list or mail
		$data = $row;
	}
	
	$db->query("UPDATE members_changes SET
	            m_state = 'invalid',
	            m_changed_by = ".$db->check($_SESSION["member"]["m_id"]).",
	            m_admin_response = '".$db->check($data["m_admin_response"])."',
	            m_changed_at = ".time()."
	            WHERE m_id = ".$db->check($row["m_id"]));
	
	$row = request_by_id($_GET["id"]);
	
	// mail user about the invalidation
	// mail admins about the invalidation
	request_change_mail_all($row, "invalid", $row["current_mail"]);
	
	notify_user(_("Request invalidated"), '');
	redirect('?page=adminm&section=members&action=approval_requests');
}

function request_ignore() {
	global $db;
	
	if(!$_SESSION["is_admin"])
		return;
	
	$row = request_by_id($_GET["id"]);
	
	if(!$row)
		return;
	
	$data = null;
	
	if(isset($_POST["m_name"])) { // called from request details
		$data = $_POST;
		
	} else { // accessed from request list or mail
		$data = $row;
	}
	
	$db->query("UPDATE members_changes SET
	            m_state = 'ignored',
	            m_changed_by = ".$db->check($_SESSION["member"]["m_id"]).",
	            m_admin_response = '".$db->check($data["m_admin_response"])."',
	            m_changed_at = ".time()."
	            WHERE m_id = ".$db->check($row["m_id"]));
	
	$row = request_by_id($_GET["id"]);
	
	// mail admins about the ignoring
	request_change_mail_admins($row, "ignored");
	request_mail_last_update($row);
	
	notify_user(_("Request ignored"), '');
	redirect('?page=adminm&section=members&action=approval_requests');
}

if ($_SESSION["logged_in"]) {

	if ($_SESSION["is_admin"]) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New member").'" /> '._("New member"), '?page=adminm&section=members&action=new');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Requests for approval").'" /> '._("Requests for approval"), '?page=adminm&section=members&action=approval_requests');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Export e-mails").'" /> '._("Export e-mails"), '?page=adminm&section=members&action=export_mails');
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Export e-mails of non-payers").'" /> '._("Export e-mails of non-payers"), '?page=adminm&section=members&action=export_notpaid_mails');
		if ($cluster_cfg->get("payments_enabled")) {
			$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Payments history").'" /> '._("Display history of payments"), '?page=adminm&section=members&action=payments_history');
		}
		$xtpl->sbar_add('<img src="template/icons/m_edit.png"  title="'._("Deleted members").'" /> '._("Deleted members"), '?page=adminm&section=members&action=show_deleted');
	}

	$xtpl->sbar_out(_("Manage members"));

	switch ($_GET["action"]) {
		case 'new':
			if ($_SESSION["is_admin"]) {
				print_newm();
			}
			break;
		case 'new2':
			if ($_SESSION["is_admin"]) {
				$ereg_ok = false;
				if (ereg('^[a-zA-Z0-9\.\-]{1,63}$',$_REQUEST["m_nick"])) {
					if (ereg('^[0-9]{1,4}$',$_REQUEST["m_level"])) {
						if (($_REQUEST["m_pass"] == $_REQUEST["m_pass2"]) && (strlen($_REQUEST["m_pass"]) >= 5)) {
							if (is_string($_REQUEST["m_mail"])) {

								$ereg_ok = true;
								$m = member_load();

								if (!$m->exists) {

									if ($m->create_new($_REQUEST)) {
										nas_create_default_exports("member", $m->m);
										
										$xtpl->perex(_("Member added"),
														_("Continue")
														. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

									} else $xtpl->perex(_("Error"),
													_("Continue")
													. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

								} else $xtpl->perex(_("Error").': '
												. _("User already exists"), _("Continue")
												. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

							} else $xtpl->perex(_("Invalid entry").': '._("E-mail"),'');
						} else $xtpl->perex(_("Invalid entry").': '._("Password"),'');
					} else $xtpl->perex(_("Invalid entry").': '._("Privileges"),'');
				} else $xtpl->perex(_("Invalid entry").': '._("Nickname"),'');

				if (!$ereg_ok) {

					print_newm();

				} else {

						$xtpl->delayed_redirect('?page=adminm', 350);

				}
			}
			break;
		case 'delete':
			if ($_SESSION["is_admin"] && ($m = member_load($_GET["id"]))) {

				$xtpl->perex(_("Are you sure, you want to delete")
								.' '.$m->m["m_nick"].'?','');
				print_deletem($m);

			}
			break;
		case 'delete2':
			if ($_SESSION["is_admin"] && ($m = member_load($_GET["id"]))) {
				$xtpl->perex(_("Are you sure, you want to delete")
						.' '.$m->m["m_nick"].'?',
						'<a href="?page=adminm&section=members">'
						. strtoupper(_("No"))
						. '</a> | <a href="?page=adminm&section=members&action=delete3&id='.$_GET["id"].'&notify='.$_REQUEST["notify"].'&lazy='.$_REQUEST["lazy_delete"].'">'
						. strtoupper(_("Yes")).'</a>');
				}
			break;
		case 'delete3':
			if ($_SESSION["is_admin"]) {

				if ($m = member_load($_GET["id"]))
					
					$lazy = $_GET["lazy"] ? true : false;
					
					$m->delete_all_vpses($lazy);
					
					if ($m->destroy($lazy)) {
						if ($_GET["notify"])
							$m->notify_delete($lazy);
						
						$xtpl->perex(_("Member deleted"), _("Continue").' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');
						$xtpl->delayed_redirect('?page=adminm', 350);

					} else {

						$xtpl->perex(_("Error"),
										_("Continue")
										. ' <a href="?page=adminm&section=members">'
										. strtolower(_("Here")).'</a>');
					}
			}
			break;
		case 'edit':
			$member = member_load($_GET["id"]);
			if ($member)
				print_editm($member);
			break;
		case 'edit_member':
			$m = member_load($_GET["id"]);
			
			if($_SESSION["is_admin"]) {
				$m->m["m_nick"] = $_POST["m_nick"];
				$m->m["m_level"] = $_POST["m_level"];
				$m->m["m_info"] = $_POST["m_info"];
				$m->m["m_monthly_payment"] = $_POST["m_monthly_payment"];
				$m->m["m_playground_enable"] = $_POST["m_playground_enable"];
			}
			
			$m->m["m_mailer_enable"] = $_POST["m_mailer_enable"];
			
			if ($m->save_changes())
				notify_user(_("Changes saved"), '');
				
			else
				notify_user(_("No change"), '');
			
			redirect('?page=adminm&section=members&action=edit&id='.$m->m["m_id"]);
			
			break;
		case 'passwd':
			$m = member_load($_GET["id"]);
			
			if ($_POST["m_pass"] != $_POST["m_pass2"]) {
				$xtpl->perex(_("Invalid entry").': '._("Password"), _("The two passwords do not match."));
				print_editm($m);
				
			} elseif (strlen($_POST["m_pass"]) < 5) {
				$xtpl->perex(_("Invalid entry").': '._("Password"), _("Password must be at least 5 characters long."));
				print_editm($m);
				
			} else {
				$m->m["m_pass"] = md5($m->m["m_nick"].$_POST["m_pass"]);
				$m->save_changes();
				
				notify_user(_("Password set"), _("The password was successfully changed."));
				redirect('?page=adminm&section=members&action=edit&id='.$m->m["m_id"]);
			}
			
			break;
		case 'edit_personal':
			$m = member_load($_GET["id"]);
			
			if($_SESSION["is_admin"]) {
				$m->m["m_name"] = $_POST["m_name"];
				$m->m["m_mail"] = $_POST["m_mail"];
				$m->m["m_address"] = $_POST["m_address"];
				
				if ($m->save_changes())
					notify_user(_("Changes saved"), _("Continue").' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');
				
				else
					notify_user(_("No change"), '');
				
				redirect('?page=adminm&section=members&action=edit&id='.$m->m["m_id"]);
				
			} elseif(!$_POST["reason"]) {
				$xtpl->perex(_("Reason is required"), _("Please fill in reason for change."));
				print_editm($m);
				
			} else {
				$db->query("INSERT INTO members_changes SET
				            m_created = ".time().",
				            m_type = 'change',
				            m_state = 'awaiting',
				            m_applicant = ".$db->check($m->m["m_id"]).",
				            m_name = '".$db->check($_POST["m_name"])."',
				            m_mail = '".$db->check($_POST["m_mail"])."',
				            m_address = '".$db->check($_POST["m_address"])."',
				            m_reason = '".$db->check($_POST["reason"])."',
				            m_addr = '".$db->check($_SERVER["REMOTE_ADDR"])."',
				            m_addr_reverse = '".$db->check(gethostbyaddr($_SERVER["REMOTE_ADDR"]))."'
				            ");
				
				$rs = $db->query("SELECT c.*, applicant.m_nick AS applicant_nick, applicant.m_name AS current_name,
				                  applicant.m_mail AS current_mail, applicant.m_address AS current_address,
				                  applicant.m_id AS applicant_id, admin.m_id AS admin_id, admin.m_nick AS admin_nick
				                  FROM members_changes c
				                  LEFT JOIN members applicant ON c.m_applicant = applicant.m_id
				                  LEFT JOIN members admin ON c.m_changed_by = admin.m_id
				                  WHERE c.m_id = ".$db->check($db->insert_id())."");
				
				$row = $db->fetch_array($rs);
					
				request_change_mail_admins($row, "awaiting");
				request_mail_last_update($row);
				
				notify_user(_("Request was scheduled for approval"), _("Please wait for administrator to approve or deny your request."));
				redirect('?page=adminm&section=members&action=edit&id='.$m->m["m_id"]);
			}
			
			break;
		case 'suspend':
			$member = member_load($_GET["id"]);
			
			if ($_SESSION["is_admin"] && $member->exists) {
				$member->suspend($_POST["reason"]);
				
				if ($_POST["stop_all_vpses"])
					$member->stop_all_vpses();
				
				$member->set_info( $member->m["m_info"]."\n".strftime("%d.%m.%Y")." - "._("suspended")." - ".$_POST["reason"] );
				
				if ($_POST["notify"])
					$member->notify_suspend($_POST["reason"]);
				
				$xtpl->perex(_("Account suspended"),
					$_POST["stop_all_vpses"] ? _("All member's VPSes were stopped.")
					: _("All member's VPSes kept running.")
				);
			}
			break;
		case 'restore':
			$member = member_load($_GET["id"]);
			
			if ($_SESSION["is_admin"] && $member->exists) {
				$member->restore();
				
				if ($_POST["start_all_vpses"])
					$member->start_all_vpses();
				
				if ($_POST["notify"])
					$member->notify_restore();
				
				$xtpl->perex(_("Account restored"), _("Member can now use his VPSes."));
			}
			break;
		case 'payset':
			if (($member = new member_load($_GET["id"])) && $_SESSION["is_admin"]) {

				$xtpl->title(_("Edit payments"));

				$xtpl->form_create('?page=adminm&section=members&action=payset2&id='.$_GET["id"], 'post');

				$xtpl->table_td(_("Paid until").':');

				if ($member->m["m_paid_until"] > 0) {
					$lastpaidto = date('Y-m-d', $member->m["m_paid_until"]);
				} else {
					$lastpaidto = _("Never been paid");
				}

				$xtpl->table_td($lastpaidto);
				$xtpl->table_tr();

				$xtpl->table_td(_("Nickname").':');
				$xtpl->table_td($member->m["m_nick"]);
				$xtpl->table_tr();

				$xtpl->table_td(_("Monthly payment").':');
				$xtpl->table_td($member->m["m_monthly_payment"]);
				$xtpl->table_tr();

				$xtpl->form_add_input(_("Newly paid until").':', 'text', '30', 'paid_until', '', 'Y-m-d, eg. 2009-05-01');
				$xtpl->form_add_input(_("Months to add").':', 'text', '30', 'months_to_add', '', ' ');

				$xtpl->table_add_category('');
				$xtpl->table_add_category('');

				$xtpl->form_out(_("Save"));

				$xtpl->table_add_category("ID");
				$xtpl->table_add_category("MEMBER");
				$xtpl->table_add_category("CHANGED");
				$xtpl->table_add_category("FROM");
				$xtpl->table_add_category("TO");

				while ($hist = $db->find("members_payments", "m_id = {$member->m["m_id"]}", "id DESC", 30)) {
					$acct_m = $db->findByColumnOnce("members", "m_id", $hist["acct_m_id"]);

					$xtpl->table_td($hist["id"]);
					$xtpl->table_td($acct_m["m_nick"]);
					$xtpl->table_td(date('Y-m-d H:i', $hist["timestamp"]));
					$xtpl->table_td(date('Y-m-d', $hist["change_from"]));
					$xtpl->table_td(date('Y-m-d', $hist["change_to"]));

					$xtpl->table_tr();
				}

				$xtpl->table_out();

			}
			break;
		case 'payset2':
			if (($member = member_load($_GET["id"])) && $_SESSION["is_admin"]) {

				$log["m_id"] = $member->m["m_id"];
				$log["acct_m_id"] = $_SESSION["member"]["m_id"];
				$log["timestamp"] = time();
				$log["change_from"] = $member->m["m_paid_until"];

				if ($_REQUEST["paid_until"]) {

					$member->set_paid_until($_REQUEST["paid_until"]);

					$xtpl->perex(_("Payment successfully set"), _("Continue")
									. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

				} elseif ($_REQUEST["months_to_add"] && $member->m["m_paid_until"]) {

					$member->set_paid_add_months($_REQUEST["months_to_add"]);

					$xtpl->perex(_("Payment successfully set"), _("Continue")
								. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

				} else {
					$xtpl->perex(_("Error"), _("Continue")
											. ' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');
				}

				$log["change_to"] = $member->m["m_paid_until"];

				$sql = 'INSERT INTO members_payments
												SET m_id = "'. $db->check($log["m_id"]) .'",
														acct_m_id 	= "'. $db->check($log["acct_m_id"]) .'",
														timestamp		= "'. $db->check($log["timestamp"]) .'",
														change_from = "'. $db->check($log["change_from"]) .'",
														change_to 	= "'. $db->check($log["change_to"]) .'"';
				$db->query($sql);

				$xtpl->delayed_redirect('?page=adminm', 350);

			}
			break;

		case 'export_mails':
			if ($_SESSION["is_admin"]) {

				$xtpl->table_add_category('');

				$mails = array();

				if ($members = get_members_array()) {

					foreach ($members as $member) {
							$mails[$member->m["m_mail"]] = $member->m["m_mail"];
					}
				}

				$xtpl->table_td(implode(', ', $mails));
				$xtpl->table_tr();

				$xtpl->table_out();
			}
			break;
		case 'export_notpaid_mails':
			if ($_SESSION["is_admin"]) {

				$xtpl->table_add_category('');

				$mails = array();

				if ($members = get_members_array()) {

					foreach ($members as $member) {

						if ($member->has_paid_now() < 1) {
							$mails[$member->m["m_mail"]] = $member->m["m_mail"];
						}

					}
				}

				$xtpl->table_td(implode(', ', $mails));
				$xtpl->table_tr();

				$xtpl->table_out();
			}
			break;
		case 'payments_history':
			$whereCond = array();
			$whereCond[] = 1;

			if ($_REQUEST["acct_m_id"] != "") {
				$whereCond[] = 'acct_m_id = "'.$db->check($_REQUEST["acct_m_id"]).'"';
			}
			if ($_REQUEST["m_id"] != "") {
				$whereCond[] = 'm_id = "'.$db->check($_REQUEST["m_id"]).'"';
			}
			if ($_REQUEST["limit"] != "") {
				$limit = $_REQUEST["limit"];
			} else {
				$limit = 50;
			}

			$xtpl->form_create('?page=adminm&filter=yes&action=payments_history', 'post');
			$xtpl->form_add_input(_("Limit").':', 'text', '40', 'limit', $limit, '');
			$xtpl->form_add_input(_("Changed by member ID").':', 'text', '40', 'acct_m_id', $_REQUEST["acct_m_id"], '');
			$xtpl->form_add_input(_("Changed to member ID").':', 'text', '40', 'm_id', $_REQUEST["m_id"], '');
			$xtpl->form_out(_("Show"));

			$xtpl->table_add_category("ID");
			$xtpl->table_add_category("CHANGED BY");
			$xtpl->table_add_category("CHANGED TO");
			$xtpl->table_add_category("CHANGED");
			$xtpl->table_add_category("FROM");
      $xtpl->table_add_category("TO");
      $xtpl->table_add_category("MONTHS");

			while ($hist = $db->find("members_payments", $whereCond, "id DESC", $limit)) {
				$acct_m = $db->findByColumnOnce("members", "m_id", $hist["acct_m_id"]);
				$m = $db->findByColumnOnce("members", "m_id", $hist["m_id"]);

				$xtpl->table_td($hist["id"]);
				$xtpl->table_td($acct_m["m_id"].' '.$acct_m["m_nick"]);
				$xtpl->table_td($m["m_id"].' '.$m["m_nick"]);
				$xtpl->table_td(date('Y-m-d H:i', $hist["timestamp"]));
				$xtpl->table_td(date('<- Y-m-d', $hist["change_from"]));
				$xtpl->table_td(date('-> Y-m-d', $hist["change_to"]));
				if ($hist["change_from"]) {
          $xtpl->table_td(round(($hist["change_to"]-$hist["change_from"])/2629800), false, true);
        } else {
          $xtpl->table_td('---', false, true);
        }
				$xtpl->table_tr();
			}

			$xtpl->table_out();
			break;
		case 'approval_requests':
			if(!$_SESSION["is_admin"])
				break;
			
			$xtpl->title(_("Requests for approval"));
			
			$xtpl->form_create('?page=adminm&section=members&action=approval_requests', 'get');
			
			$xtpl->table_td(_("Limit").':'.
				'<input type="hidden" name="page" value="adminm">'.
				'<input type="hidden" name="section" value="members">'.
				'<input type="hidden" name="action" value="approval_requests">'
			);
			$xtpl->form_add_input_pure('text', '30', 'limit', $_GET["limit"] ? $_GET["limit"] : 50);
			$xtpl->table_tr();
			
			$xtpl->form_add_select(_("Type").':', 'type', array("" => _("all"), "add" => _("registration"), "change" => _("change")), $_GET["type"]);
			$xtpl->form_add_select(_("State").':', 'state', array(
				"all" => _("all"),
				"awaiting" => _("awaiting"),
				"approved" => _("approved"),
				"denied" => _("denied"),
				"invalid" => _("invalid"),
				"ignored" => _("ignored")
			), $_GET["state"] ? $_GET["state"] : "awaiting");
			
			$xtpl->form_add_input(_("IP address").':', 'text', '30', 'ip', $_GET["ip"]);
			
			$xtpl->form_out(_("Show"));
			
			$xtpl->table_add_category('DATE');
			$xtpl->table_add_category('TYPE');
			$xtpl->table_add_category('NICK');
			$xtpl->table_add_category('NAME');
			$xtpl->table_add_category('IP');
			$xtpl->table_add_category('STATE');
			$xtpl->table_add_category('ADMIN');
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			
			$conds = array();
			
			if($_GET["state"] != "all")
				$conds[] = "c.m_state = '".$db->check($_GET["state"] ? $_GET["state"] : "awaiting")."'";
			
			if($_GET["type"])
				$conds[] = "c.m_type = '".$db->check($_GET["type"])."'";
			
			if($_GET["ip"])
				$conds[] = "c.m_addr = '".$db->check($_GET["ip"])."'";
			
			$conds_str = implode(" AND ", $conds);
			
			$rs = $db->query("SELECT c.*, applicant.m_nick AS applicant_nick, admin.m_nick AS admin_nick
			                  FROM members_changes c
			                  LEFT JOIN members applicant ON c.m_applicant = applicant.m_id
			                  LEFT JOIN members admin ON c.m_changed_by = admin.m_id
			                  ".($conds_str ? 'WHERE '.$conds_str : '')."
			                  ORDER BY c.m_created
			                  LIMIT ".$db->check($_GET["limit"] ? $_GET["limit"] : "50"));
			
			while($row = $db->fetch_array($rs)) {
				$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $row["m_created"]));
				$xtpl->table_td($row["m_type"] == "add" ? _("registration") : _("change"));
				$xtpl->table_td($row["m_type"] == "change" ? ('<a href="?page=adminm&section=members&action=info&id='.$row["m_applicant"].'">'.$row["applicant_nick"].'</a>') : $row["m_nick"]);
				$xtpl->table_td($row["m_name"]);
				$xtpl->table_td($row["m_addr"]);
				$xtpl->table_td($row["m_state"]);
				$xtpl->table_td($row["m_changed_by"] ? ('<a href="?page=adminm&section=members&action=info&id='.$row["m_changed_by"].'">'.$row["admin_nick"].'</a>') : '-');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=request_details&id='.$row["m_id"].'"><img src="template/icons/m_edit.png"  title="'. _("Details") .'" /></a>');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=request_process&id='.$row["m_id"].'&rule=approve">'._("approve").'</a>');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=request_process&id='.$row["m_id"].'&rule=deny">'._("deny").'</a>');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=request_process&id='.$row["m_id"].'&rule=ignore">'._("ignore").'</a>');
				
				$xtpl->table_tr();
			}
			
			$xtpl->table_out();
			
			break;
			
		case "request_details":
			if(!$_SESSION["is_admin"])
				break;
			
			$rs = $db->query("SELECT c.*, applicant.m_nick AS applicant_nick, applicant.m_name AS current_name,
			                  applicant.m_mail AS current_mail, applicant.m_address AS current_address,
			                  admin.m_nick AS admin_nick
			                  FROM members_changes c
			                  LEFT JOIN members applicant ON c.m_applicant = applicant.m_id
			                  LEFT JOIN members admin ON c.m_changed_by = admin.m_id
			                  WHERE c.m_id = ".$db->check($_GET["id"])."");
			
			$row = $db->fetch_array($rs);
			
			if(!$row)
				break;
			
			$xtpl->title(_("Request for approval details"));
			
			$xtpl->table_add_category(_("Request info"));
			$xtpl->table_add_category('');
			
			$xtpl->table_td(_("Created").':');
			$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $row["m_created"]));
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Changed").':');
			$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $row["m_changed_at"]));
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Type").':');
			$xtpl->table_td($row["m_type"] == "add" ? _("registration") : _("change"));
			$xtpl->table_tr();
			
			$xtpl->table_td(_("State").':');
			$xtpl->table_td($row["m_state"]);
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Applicant").':');
			$xtpl->table_td($row["m_applicant"] ? ('<a href="?page=adminm&section=members&action=info&id='.$row["m_applicant"].'">'.$row["applicant_nick"].'</a>') : '-');
			$xtpl->table_tr();
			
			$xtpl->table_td(_("Admin").':');
			$xtpl->table_td($row["m_changed_by"] ? ('<a href="?page=adminm&section=members&action=info&id='.$row["m_changed_by"].'">'.$row["admin_nick"].'</a>') : '-');
			$xtpl->table_tr();
			
			$xtpl->table_td(_("IP Address").':');
			$xtpl->table_td($row["m_addr"]);
			$xtpl->table_tr();
			
			$xtpl->table_td(_("IP Address PTR").':');
			$xtpl->table_td($row["m_addr_reverse"]);
			$xtpl->table_tr();
			
			$xtpl->table_out();
			
			switch($row["m_type"]) {
				case "add":
					$xtpl->table_add_category(_("Application"));
					$xtpl->table_add_category('');
					
					$xtpl->form_create('?page=adminm&section=members&action=request_process&id='.$row["m_id"], 'post');
					
					$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', $row["m_nick"], _("A-Z, a-z, dot, dash"), 63);
					$xtpl->form_add_input(_("Name").':', 'text', '30', 'm_name', $row["m_name"], '', 255);
					$xtpl->form_add_input(_("Email").':', 'text', '30', 'm_mail', $row["m_mail"], '', 127);
					$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'm_address', $row["m_address"]);
					
					$xtpl->table_td(_("Year of birth").':');
					$xtpl->table_td($row["m_year"]);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Jabber").':');
					$xtpl->table_td($row["m_jabber"]);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("How").':');
					$xtpl->table_td($row["m_how"]);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Note").':');
					$xtpl->table_td($row["m_note"]);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Currency").':');
					$xtpl->table_td($row["m_currency"]);
					$xtpl->table_tr();
					
					$xtpl->form_add_checkbox(_("Create VPS").':', 'm_create_vps', '1', true);
					
					$xtpl->form_add_select(_("Distribution").':', 'm_distribution', list_templates(false), $row["m_distribution"]);
					$xtpl->form_add_select(_("Location").':', 'm_location', $cluster->list_locations(), $row["m_location"]);
					
					$empty = array("" => _("pick automatically"));
					$nodes = list_servers(false, array('node'));
					$xtpl->form_add_select(_("Node").':', 'm_node', array_merge($empty, $nodes));
					
					$xtpl->form_add_checkbox(_("Assign IP addresses").':', 'm_assign_ips', '1', true);
					$xtpl->form_add_select(_("IPv4").':', 'ipv4', array_merge($empty, get_free_ip_list(4, $row["m_location"])), '', _("listing IPs from application location only"));
					$xtpl->form_add_select(_("IPv6").':', 'ipv6', array_merge($empty, get_free_ip_list(6, $row["m_location"])), '', _("listing IPs from application location only"));
					
					$xtpl->form_add_input(_("Admin response").':', 'text', '30', 'm_admin_response', $row["m_admin_response"]);
					
					$xtpl->table_td('');
					$xtpl->table_td(
						$xtpl->html_submit(_("Approve"), "approve").
						$xtpl->html_submit(_("Deny"), "deny").
						$xtpl->html_submit(_("Invalidate"), "invalidate").
						$xtpl->html_submit(_("Ignore"), "ignore")
					);
					$xtpl->table_tr();
					
					$xtpl->form_out_raw();
					
					break;
				
				case "change":
					$xtpl->table_add_category(_("Personal information"));
					$xtpl->table_add_category(_("From"));
					$xtpl->table_add_category(_("To"));
					
					$xtpl->form_create('?page=adminm&section=members&action=request_process&id='.$row["m_id"], 'post');
					
					$xtpl->table_td(_("Name").':');
					$xtpl->table_td($row["current_name"]);
					$xtpl->form_add_input_pure('text', '30', 'm_name', $row["m_name"], '', 255);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Email").':');
					$xtpl->table_td($row["current_mail"]);
					$xtpl->form_add_input_pure('text', '30', 'm_mail', $row["m_mail"], '', 127);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Postal address").':');
					$xtpl->table_td($row["current_address"]);
					$xtpl->form_add_input_pure('text', '30', 'm_address', $row["m_address"]);
					$xtpl->table_tr();
					
					$xtpl->table_td(_("Reason for change").':');
					$xtpl->table_td($row["m_reason"], false, false, 2);
					$xtpl->table_tr();
					
					$xtpl->form_add_input(_("Admin response").':', 'text', '30', 'm_admin_response', $row["m_admin_response"]);
					
					$xtpl->table_td('');
					$xtpl->table_td(
						$xtpl->html_submit(_("Approve"), "approve").
						$xtpl->html_submit(_("Deny"), "deny").
						$xtpl->html_submit(_("Invalidate"), "invalidate").
						$xtpl->html_submit(_("Ignore"), "ignore")
					);
					$xtpl->table_tr();
					
					$xtpl->form_out_raw();
					
					break;
			}
			
			break;
		
		case "request_process":
			if(!$_SESSION["is_admin"])
				break;
			
			if(isset($_POST["approve"]) || $_GET["rule"] == "approve")
				request_approve();
			
			elseif(isset($_POST["deny"]) || $_GET["rule"] == "deny")
				request_deny();
			
			elseif(isset($_POST["invalidate"]) || $_GET["rule"] == "invalidate")
				request_invalidate();
			
			elseif(isset($_POST["ignore"]) || $_GET["rule"] == "ignore")
				request_ignore();
			
			break;
		
		case 'show_deleted':
			if(!$_SESSION["is_admin"])
				break;
			
			$xtpl->table_add_category('ID');
			$xtpl->table_add_category(_("NICKNAME"));
			$xtpl->table_add_category(_("VPS"));
			$xtpl->table_add_category(_("FULL NAME"));
			$xtpl->table_add_category(_("DELETED"));
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');
			
			$rs = $db->query("SELECT m_id FROM members WHERE m_state = 'deleted'");
			
			while($row = $db->fetch_array($rs)) {
				$m = new member_load($row["m_id"]);
				
				$xtpl->table_td($m->mid);
				$xtpl->table_td($m->m["m_nick"]);
				$xtpl->table_td("<a href='?page=adminvps&m_nick=".$m->m["m_nick"]."'>[ ".$m->get_vps_count()." ]</a>");
				$xtpl->table_td($m->m["m_name"]);
				$xtpl->table_td(strftime("%Y-%m-%d %H:%M", $m->m["m_deleted"]));
				$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$m->mid.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');
				$xtpl->table_td('<a href="?page=adminm&section=members&action=delete&id='.$m->mid.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');
				$xtpl->table_tr();
			}
			
			$xtpl->table_out();
			
			break;
		
		default:
			if ($_SESSION["is_admin"]) {

				$xtpl->title(_("Manage members [Admin mode]"));

			} else {

				$xtpl->title(_("Manage members"));
			}

			$xtpl->table_add_category('ID');
			$xtpl->table_add_category(_("NICKNAME"));
			$xtpl->table_add_category(_("VPS"));
			if ($cluster_cfg->get("payments_enabled")) {
				$xtpl->table_add_category(_("$"));
			}
			$xtpl->table_add_category(_("FULL NAME"));
			$xtpl->table_add_category(_("LAST ACTIVITY"));
			if ($cluster_cfg->get("payments_enabled")) {
				$xtpl->table_add_category(_("PAYMENT"));
			}
			$xtpl->table_add_category('');
			$xtpl->table_add_category('');

			$listed_members = 0;
			$total_income = 0;
			$this_month_income = 0;
			$t_now = time();
			$t_year = date('Y', $t_now);
			$t_month = date('m', $t_now);

			$t_this_month = mktime (0, 0, 0, $t_month, 1, $t_year);

			$t_next_month_tmp = mktime (0, 0, 0, $t_month, 1, $t_year) + 2678400;

			$t_next_month_year = date('Y', $t_next_month_tmp);
			$t_next_month_month = date('m', $t_next_month_tmp);

			$t_next_month = mktime (0, 0, 0, $t_next_month_month, 1, $t_next_month_year);

			if ($members = get_members_array()) {

				foreach ($members as $member) {

					$xtpl->table_td($member->m["m_id"]);

					if (($_SESSION["is_admin"]) && ($member->m["m_id"] != $_SESSION["member"]["m_id"])) {

						$xtpl->table_td("<a href='?page=login&action=switch_context&m_id={$member->m["m_id"]}&next=".urlencode($_SERVER["REQUEST_URI"])."'><img src=\"template/icons/m_switch.png\"  title=". _("Switch context") ." /></a>".
						$member->m["m_nick"]);

					} else {
						$xtpl->table_td($member->m["m_nick"]);
					}

					$vps_count = $member->get_vps_count();

					$xtpl->table_td("<a href='?page=adminvps&m_nick=".$member->m["m_nick"]."'>[ ".$vps_count." ]</a>");

					if ($cluster_cfg->get("payments_enabled")) {
						$xtpl->table_td($member->m["m_monthly_payment"]);
					}

					if (($member->m["m_paid_until"] >= $t_this_month) && ($member->m["m_paid_until"] < $t_next_month)) {
						$this_month_income += $member->m["m_monthly_payment"];
					}

					$total_income += $member->m["m_monthly_payment"];

					$xtpl->table_td($member->m["m_name"]);

					$paid = $member->has_paid_now();

					if ($member->m["m_last_activity"]) {
						if (($member->m["m_last_activity"]+2592000) < time()) {

							// Month
							$xtpl->table_td(date('Y-m-d H:i:s', $member->m["m_last_activity"]), '#FFF');

						} elseif (($member->m["m_last_activity"]+604800) < time()) {

							// Week
							$xtpl->table_td(date('Y-m-d H:i:s', $member->m["m_last_activity"]), '#99FF66');

						} elseif (($member->m["m_last_activity"]+86400) < time()) {

							// Day
							$xtpl->table_td(date('Y-m-d H:i:s', $member->m["m_last_activity"]), '#66FF33');

						} else {

							// Less
							$xtpl->table_td(date('Y-m-d H:i:s', $member->m["m_last_activity"]), '#33CC00');

						}

					} else {
					    $xtpl->table_td("---", '#FFF');
					}

					if ($cluster_cfg->get("payments_enabled")) {

						if ($member->m["m_paid_until"]) {
								$paid_until = date('Y-m-d', $member->m["m_paid_until"]);
						} else {
							$paid_until = "Never been paid";
						}

						if ($_SESSION["is_admin"]) {

							if ($paid == (-1)) {
								$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='.$member->mid.'">'._("info. missing").'</a>', '#FF8C00');

							} elseif ($paid == 0) {
								$table_td = '<b><a href="?page=adminm&section=members&action=payset&id='.$member->mid.'" title="'.$paid_until.'">'.
										_("not paid!").
										'</a></b>';

								if ($member->m["m_paid_until"]) {
										$table_td .= ' '.ceil(($member->m["m_paid_until"] - time())/86400).'d';
								}

								$xtpl->table_td($table_td, '#B22222');

							} else {

								if (($member->m["m_paid_until"] - time()) >= 604800) {
										$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='.$member->mid.'">'._("->").' '.$paid_until.'</a>', '#66FF66');
								} else {
										$xtpl->table_td('<a href="?page=adminm&section=members&action=payset&id='.$member->mid.'">'._("->").' '.$paid_until.'</a>', '#FFA500');
								}
							}
						} else {

							if ($paid == (-1)) {
								$xtpl->table_td(_("info. missing"), '#FF8C00');

							} elseif ($paid == 0) {
								$xtpl->table_td('<b>'._("not paid!").' (->'.$paid_until.')</b>', '#B22222');

							} else {

								if (($member->m["m_paid_until"] - time()) >= 604800) {
										$xtpl->table_td(_("->").' '.$paid_until, '#66FF66');

								} else {
										$xtpl->table_td(_("->").' '.$paid_until, '#FFA500');
								}
							}
						}
					}

					$xtpl->table_td('<a href="?page=adminm&section=members&action=edit&id='.$member->mid.'"><img src="template/icons/m_edit.png"  title="'. _("Edit") .'" /></a>');

					if ($_SESSION["is_admin"]) {

// 						if ($vps_count > 0) {
// 							$xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'. _("Cannot delete, has VPSes") .'" />');
// 
// 						} else {
							$xtpl->table_td('<a href="?page=adminm&section=members&action=delete&id='.$member->mid.'"><img src="template/icons/m_delete.png"  title="'. _("Delete") .'" /></a>');
// 						}

					} else {
						$xtpl->table_td('<img src="template/icons/vps_delete_grey.png"  title="'. _("Cannot delete yourself") .'" />');
					}

					if ($_SESSION["is_admin"] && ($member->m["m_info"]!='')) {
						$xtpl->table_td('<img src="template/icons/info.png" title="'.$member->m["m_info"].'"');
					}

					if ($member->m["m_level"] >= PRIV_SUPERADMIN) {
						$xtpl->table_tr('#22FF22');
					} elseif ($member->m["m_level"] >= PRIV_ADMIN) {
						$xtpl->table_tr('#66FF66');
					} elseif ($member->m["m_level"] >= PRIV_POWERUSER) {
						$xtpl->table_tr('#BBFFBB');
					} elseif ($member->m["m_state"] != "active") {
						$xtpl->table_tr('#A6A6A6');
					} else {
						$xtpl->table_tr();
					}

					$listed_members++;
				}
			}

			$xtpl->table_out();

			if ($_SESSION["is_admin"] && $cluster_cfg->get("payments_enabled")) {

				$xtpl->table_add_category(_("Members in total").':');
				$xtpl->table_add_category($listed_members);
				$xtpl->table_add_category(_("Estimated monthly income").':');
				$xtpl->table_add_category($total_income);
				$xtpl->table_add_category(_("Estimated this month").':');
				$xtpl->table_add_category($this_month_income);
				$xtpl->table_out();
			}
			break;
	}

} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
