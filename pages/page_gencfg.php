<?php
/*
  ./pages/page_cluster.php

  vpsAdmin
  Web-admin interface for OpenVZ (see http://openvz.org)
  Copyright (C) 2008-2011 Pavel Snajdr, snajpa@snajpa.net
*/
if ($_SESSION["is_admin"]) {

$xtpl->title(_("Gencfg"));
$xtpl->sbar_out(_("Gencfg"));

if ($_REQUEST["vps"]) {

$vps = vps_load($_REQUEST["vps"]);
$vps_id = $vps->ve["vps_id"];
$hostname = $vps->ve["vps_hostname"];
$nameserver = $vps->ve["vps_nameserver"];

while ($ip = $db->find("vps_ip", "vps_id = {$vps_id}")) {
  $ips .= "{$ip["ip_addr"]} ";
}

$tpl = $db->findOnce("cfg_templates", "templ_id  = {$vps->ve["vps_template"]}");

$template = $tpl["templ_name"];

$xtpl->table_td(nl2br(<<<CFG
NUMPROC="2046:2046"
AVNUMPROC="1023:1023"
NUMTCPSOCK="2046:2046"
NUMOTHERSOCK="2046:2046"
VMGUARPAGES="255938:9223372036854775807"

# Secondary parameters
KMEMSIZE="9223372036854775807:9223372036854775807"
TCPSNDBUF="19560953:27941369"
TCPRCVBUF="19560953:27941369"
OTHERSOCKBUF="9780476:18160892"
DGRAMRCVBUF="9780476:9780476"
OOMGUARPAGES="9223372036854775807:9223372036854775807"
PRIVVMPAGES="1048576:1585152"

# Auxiliary parameters
LOCKEDPAGES="4092:4092"
SHMPAGES="122789:122789"
PHYSPAGES="0:9223372036854775807"
NUMFILE="32736:32736"
NUMFLOCK="1000:1100"
NUMPTY="204:204"
NUMSIGINFO="1024:1024"
DCACHESIZE="18306733:18855936"
NUMIPTENT="100:100"
DISKSPACE="41943040:41943040"
DISKINODES="13583879:14942268"
CPUUNITS="23808"
HOSTNAME="$hostname"
VE_ROOT="/var/lib/vz/root/\$VEID"
VE_PRIVATE="/var/lib/vz/private/\$VEID"
OSTEMPLATE="$template"
ORIGIN_SAMPLE="vps.basic"
NAMESERVER="$nameserver"
ONBOOT="yes"
IP_ADDRESS="$ips"

CFG
));
$xtpl->table_tr();
$xtpl->table_out();
} else $xtpl->perex(_("Set _GET[vps]"), '');
} else $xtpl->perex(_("Access forbidden"), _("You have to log in to be able to access vpsAdmin's functions"));
?>
