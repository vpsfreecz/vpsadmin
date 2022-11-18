(function () {

var timeout;
var filters = [
	'limit', 'environment', 'location',	'node', 'vps', 'user'
];

function pad(num, size) {
	var s = num+"";

	while (s.length < size)
		s = "0" + s;

	return s;
}

function round (number, precision) {
	var factor = Math.pow(10, precision);
	var tempNumber = number * factor;
	var roundedTempNumber = Math.round(tempNumber);
	return roundedTempNumber / factor;
}

function formatDataRate(n) {
	var units = [
		{threshold: 2 << 29, unit: 'G'},
		{threshold: 2 << 19, unit: 'M'},
		{threshold: 2 << 9,  unit: 'k'},
	];

	ret = "";
	selected = 0;

	for (var i = 0; i < units.length; i++) {
		if (n > units[i].threshold)
			return round((n / units[i].threshold), 2) + units[i].unit;
	}

	return round(n, 2);
}

function formatNumber(n) {
	var units = [
		{threshold: 1000*1000*1000, unit: 'G'},
		{threshold: 1000*1000, unit: 'M'},
		{threshold: 1000,  unit: 'k'},
	];

	ret = "";
	selected = 0;

	for (var i = 0; i < units.length; i++) {
		if (n > units[i].threshold)
			return round((n / units[i].threshold), 2) + units[i].unit;
	}

	return round(n, 2);
}

function getParams (callback) {
	var ret = {
		'meta': {
			'includes': 'network_interface__vps__node',
		}
	};

	filters.forEach(function (param) {
		var v = $('#monitor-filters').find('*[name="'+param+'"]').val();

		if (v && !(v === '0'))
			ret[param] = v;
	 });

	return callback(ret);
}

function td () {
	return $('<td>').html(Array.prototype.slice.call(arguments).join(''));
}

function rate (n, delta) {
	return td(formatDataRate((n / delta) * 8)).css('text-align', 'right');
}

function packets (n, delta) {
	return td(formatNumber(n / delta)).css('text-align', 'right');
}

function updateMonitor () {
	getParams(function (params) {
		apiClient.network_interface_monitor.list(params, function (c, list) {
			$('#live_monitor tr').slice(3).remove();

			list.each(function (stat) {
				var tr = $('<tr>');

				tr.append(td(
					'<a href="?page=adminvps&action=info&veid='+stat.network_interface.vps_id+'">#' +
					stat.network_interface.vps_id +
					'</a>'
				));
				tr.append(td(
					'<a href="?page=node&id='+stat.network_interface.vps.node_id+'">' +
					stat.network_interface.vps.node.domain_name +
					'</a>'
				));
				tr.append(td(stat.network_interface.name));

				['in', 'out'].forEach(function (dir) {
					tr.append(rate(stat['bytes_'+dir], stat.delta));
					tr.append(packets(stat['packets_'+dir], stat.delta));
				});

				tr.append(rate(stat['bytes_in'] + stat['bytes_out'], stat.delta));
				tr.append(packets(stat['packets_in'] + stat['packets_out'], stat.delta));

				tr.appendTo('#live_monitor tbody');
			});
		});
	});

	timeout = setTimeout(updateMonitor, 10000);

	var now = new Date();

	$('#monitor-last-update').html(
		now.getFullYear()+'-'+pad(now.getMonth() + 1, 2)+'-'+pad(now.getDate() + 1, 2)+' '+
		pad(now.getHours(), 2)+':'+pad(now.getMinutes(), 2)+':'+pad(now.getSeconds(), 2)
	);
}

$(document).ready(function () {
	timeout = setTimeout(updateMonitor, 10000)

	$('#monitor-filters input[name="refresh"]').change(function () {
		if (this.checked) {
			updateMonitor();

		} else {
			clearTimeout(timeout);
			timeout = null;
		}
	});

	filters.forEach(function (name) {
		$('#monitor-filters *[name="'+name+'"]').change(function () {
			if (timeout)
				updateMonitor();
		});
	});
});

}());
