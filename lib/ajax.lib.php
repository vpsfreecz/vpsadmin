<?php
/*
    ./lib/vps.lib.php

    vpsAdmin
    Web-admin interface for OpenVZ (see http://openvz.org)
    Copyright (C) 2009 Tomas Srnka, tomas@srnka.info

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

$html_js_b = '<script type="text/javascript">';
$html_js_e = '</script>';

/** Creates ajax request, which obtains HTML code in certain intervals. This code is afterwards put instead of $div.

    @param String $url - url of ajax request
    @param String #div - div, which should be updated
    @param int    $time - time interval of request

    @return String HTML code
*/
function ajax_getHTML($url, $div, $time=1000)
{
	$out = '
	<script type="text/javascript">
	$(document).ready(function (){
		var ajax_old_data = "";

		setInterval(function () {
			var ts = Math.round((new Date()).getTime() / 2000);

			$.get("'.$url.'&ts="+ts, function(data) {
				if ((data != ajax_old_data)) {
					$("#'.$div.'").html(data);
					ajax_old_data = data;
				}
			});
		}, '.$time.');
	});
	</script>
	';

    return $out;
}

function moo_inputremaining($input, $output, $chars, $uid)
{
	global $html_js_b;
	global $html_js_e;

	$out = $html_js_b."\n";

	$out .= '
	$(document).ready(function (){
		$("#'.$input.'").keyup(function (o){
			var n = '.abs($chars).' - $(this).val().length;
			$("#'.$output.'").text( n < 0 ? 0 : n );
		});
	});
	';

	$out .= $html_js_e."\n";

	return $out;
}
?>
