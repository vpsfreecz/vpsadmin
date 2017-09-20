#!/usr/bin/env ruby

require 'optparse'

require 'rubygems'
require 'mysql'

class NotFound < StandardError
	def initialize(s)
		@s = s
	end
	
	def to_s
		super + " #{@s}"
		end
end

$translation = {
	:ram => {
		1 => "privvmpages-4g-6g",
		3 => "privvmpages-6g-6g",
		5 => "privvmpages-8g-8g",
	},
	:hdd => {
		1 => "hdd-40g",
		2 => "hdd-60g",
		3 => "hdd-80g",
		9 => "hdd-20g",
		11 => "hdd-160g",
		16 => "hdd-300g",
		17 => "hdd-500g",
	},
	:cpu => {
		1 => "cpu-8c-800",
		2 => "cpu-1c-50",
		3 => "cpu-1c-75",
		4 => "cpu-1c-100",
		5 => "cpu-2c-150",
		6 => "cpu-2c-200",
		7 => "cpu-3c-250",
		8 => "cpu-3c-300",
		9 => "cpu-4c-350",
		10 => "cpu-4c-400",
		11 => "cpu-5c-500",
		12 => "cpu-6c-600",
		13 => "cpu-7c-700",
	}
}

base = "base-privvmpages"

def tr(t, val)
	n = $configs[ $translation[t][val.to_i] ]
	raise NotFound.new("[#{t.to_s}.#{val} not found]") unless n
	n
end

options = {
	:dry_run => false,
}

OptionParser.new do |opts|
	opts.on("-d", "--dry-run", "Dry run") do
		options[:dry_run] = true
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

db = Mysql.new("host", "vpsadmin", "password", "vpsadmin")

$configs = {}

rs = db.query("SELECT id, name FROM config")
rs.each_hash do |row|
	$configs[ row["name"] ] = row["id"].to_i
end

rs = db.query("SELECT vps_id, vps_privvmpages, vps_diskspace, vps_cpulimit FROM vps ORDER BY vps_id")
rs.each_hash do |row|
	if options[:dry_run]
		puts row["vps_id"]
		puts "\t#{base} (#{$configs[base]})"
		puts "\t#{row["vps_privvmpages"]} -> #{$translation[:ram][row["vps_privvmpages"].to_i]} (#{tr(:ram, row["vps_privvmpages"])})"
		puts "\t#{row["vps_diskspace"]} -> #{$translation[:hdd][row["vps_diskspace"].to_i]} (#{tr(:hdd, row["vps_diskspace"])})"
		puts "\t#{row["vps_cpulimit"]} -> #{$translation[:cpu][row["vps_cpulimit"].to_i]} (#{tr(:cpu, row["vps_cpulimit"])})"
	else
		st = db.prepare("INSERT INTO vps_has_config (vps_id, config_id, `order`) VALUES (?, ?, 1), (?, ?, 2), (?, ?, 3), (?, ?, 4)")
		st.execute(
			row["vps_id"], $configs[base],
			row["vps_id"], tr(:ram, row["vps_privvmpages"]),
			row["vps_id"], tr(:hdd, row["vps_diskspace"]),
			row["vps_id"], tr(:cpu, row["vps_cpulimit"])
		)
		st.close
	end
end
