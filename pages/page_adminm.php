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
					var length = 8;
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
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');
	$xtpl->table_add_category('&nbsp;');

	$xtpl->form_create('?page=adminm&section=members&action=edit2&id='.$_GET["id"], 'post');

	if ($member->m["m_created"]) {
	    $xtpl->table_td("Created".':');
	    $xtpl->table_td(strftime("%Y-%m-%d %H:%M", $member->m["m_created"]));
	    $xtpl->table_tr();
	}

	if ($_SESSION["is_admin"]) {

			$xtpl->form_add_input(_("Nickname").':', 'text', '30', 'm_nick', $member->m["m_nick"], _("A-Z, a-z, dot, dash"), 63);
	    $xtpl->form_add_select(_("Privileges").':', 'm_level', $cfg_privlevel, $member->m["m_level"],  '');

	} else {

		$xtpl->table_td(_("Nickname").':');
		$xtpl->table_td($member->m["m_nick"]);
		$xtpl->table_td('');
		$xtpl->table_tr();

		$xtpl->table_td(_("Privileges").':');
		$xtpl->table_td($cfg_privlevel[$member->m["m_level"]]);
		$xtpl->table_td('');
		$xtpl->table_tr();
	}

	$xtpl->form_add_input(_("Password").':', 'password', '30', 'm_pass', '', _("fill in only when change is required"), -5);
	$xtpl->form_add_input(_("Repeat password").':', 'password', '30', 'm_pass2', '', _("fill in only when change is required"), -5);
	$xtpl->form_add_input(_("Full name").':', 'text', '30', 'm_name', $member->m["m_name"], _("A-Z, a-z, with diacritic"), 255);
	$xtpl->form_add_input(_("E-mail").':', 'text', '30', 'm_mail', $member->m["m_mail"], ' ');
	$xtpl->form_add_input(_("Postal address").':', 'text', '30', 'm_address', $member->m["m_address"], ' ');
	
	if ($_SESSION["is_admin"]) {
		$xtpl->table_td(_("VPS count").':');
		$xtpl->table_td("<a href='?page=adminvps&m_nick=".$member->m["m_nick"]."'>".$member->get_vps_count()."</a>");
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

	if ($cluster_cfg->get("mailer_enabled")) {
		$xtpl->form_add_checkbox(_("Enable vpsAdmin mailer").':', 'm_mailer_enable', '1', $member->m["m_mailer_enable"], $hint = '');
	}

	if ($_SESSION["is_admin"]) {
	    $xtpl->form_add_input(_("Monthly payment").':', 'text', '30', 'm_monthly_payment', $member->m["m_monthly_payment"], ' ');
	    $xtpl->form_add_checkbox(_("Enable playground VPS").':', 'm_playground_enable', '1', $member->m["m_playground_enable"], $hint = '');
	    $xtpl->form_add_textarea(_("Info").':', 28, 4, 'm_info', $member->m["m_info"], _("Note for administrators"));
	}

	$xtpl->form_out(_("Save"));
	
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

if ($_SESSION["logged_in"]) {

	if ($_SESSION["is_admin"]) {
		$xtpl->sbar_add('<img src="template/icons/m_add.png"  title="'._("New member").'" /> '._("New member"), '?page=adminm&section=members&action=new');
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
			if (
					(
						($member)
					) && (
						($_SESSION["is_admin"]) || ($member->m["m_id"] == $_SESSION["member"]["m_id"])
					)
				) {

				print_editm($member);

			}
			break;
		case 'edit2':
			$ereg_ok = false;
			$member = member_load($_GET["id"]);

			if (
					(
						$_SESSION["is_admin"]) || ($member->m["m_id"] == $_SESSION["member"]["m_id"]
					) && (
						ereg('^[0-9]{1,4}$', $_REQUEST["m_level"]) || (!$_SESSION["is_admin"])
					)
				 ) {
				if (($_REQUEST["m_pass"] == $_REQUEST["m_pass2"])) {
					if (is_string($_REQUEST["m_mail"])) {

						$ereg_ok = true;

						if ($member->exists) {

							if ($_SESSION["is_admin"]) {
							    $member->m["m_nick"] = $_REQUEST["m_nick"];
							    $member->m["m_level"] = $_REQUEST["m_level"];
							    $member->m["m_info"] = $_REQUEST["m_info"];
							    $member->m["m_monthly_payment"] = $_REQUEST["m_monthly_payment"];
							    $member->m["m_playground_enable"] = $_REQUEST["m_playground_enable"];
							}

							if (($_REQUEST["m_pass"] != '') && (strlen($_REQUEST["m_pass"]) >= 5)) {
								$member->m["m_pass"] = md5($member->m["m_nick"].$_REQUEST["m_pass"]);
							}

							$member->m["m_name"] = $_REQUEST["m_name"];
							$member->m["m_mail"] = $_REQUEST["m_mail"];
							$member->m["m_address"] = $_REQUEST["m_address"];
							$member->m["m_mailer_enable"] = $_REQUEST["m_mailer_enable"];

							if ($member->save_changes()) {
								$xtpl->perex(_("Changes saved"), _("Continue").' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');
							} else {
								$xtpl->perex(_("No change"), _("Continue").' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');
							}

						} else $xtpl->perex(_("Error"), _("Continue").' <a href="?page=adminm&section=members">'.strtolower(_("Here")).'</a>');

					} else $xtpl->perex(_("Invalid entry").': '._("E-mail"),'');
				} else $xtpl->perex(_("Invalid entry").': '._("Password"),'');
			} else $xtpl->perex(_("Invalid entry").': '._("Privileges"),'');

			if (!$ereg_ok) {
				print_editm($member);
			} else {
			    $xtpl->delayed_redirect('?page=adminm', 350);
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
