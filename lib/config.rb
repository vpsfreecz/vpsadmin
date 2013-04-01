require 'rubygems'
require 'yaml'

IMPLICIT_CONFIG = {
	:db => {
		:host => nil,
		:user => nil,
		:pass => nil,
		:name => nil,
		:retry_interval => 30,
	},
	
	:vpsadmin => {
		:server_id => nil,
		:domain => "vpsfree.cz",
		:netdev => "eth0",
		:threads => 6,
		:check_interval => 1,
		:status_interval => 300,
		:update_vps_status => true,
		:root => "/opt/vpsadmind",
		:init => true,
		:handlers => {
			"VpsAdmin" => {
				101 => "stop",
				102 => "restart",
				103 => "update",
			},
			"Node" => {
				3 => "reboot",
				4 => "sync_templates",
				7301 => "create_config",
				7302 => "delete_config",
			},
			"VPS" => {
				1001 => "start",
				1002 => "stop",
				1003 => "restart",
				2002 => "set_params",
				2003 => "set_params",
				2004 => "set_params",
				2005 => "set_params",
				2006 => "set_params",
				2007 => "set_params",
				2008 => "applyconfig",
				3001 => "create",
				3002 => "destroy",
				3003 => "reinstall",
				3004 => "clone",
				4001 => "migrate_offline",
				4002 => "migrate_online",
				5301 => "nas_mounts",
				5302 => "nas_mount",
				5303 => "nas_umount",
				5304 => "nas_remount",
				8001 => "features",
			},
			"Storage" => {
				5201 => "create_export",
				5202 => "update_export",
				5203 => "delete_export",
			},
			"Backuper" => {
				5002 => "restore_prepare",
				5003 => "restore_finish",
				5004 => "download",
				5005 => "backup",
				5006 => "backup",
				5007 => "exports",
			},
			"Firewall" => {
				7201 => "reg_ips",
			},
			"Mailer" => {
				9001 => "send",
			}
		}
	},
	
	:vz => {
		:vzctl => "vzctl",
		:vzlist => "vzlist",
		:vzquota => "vzquota",
		:vzmigrate => "vzmigrate",
		:vz_root => "/vz",
		:vz_conf => "/etc/vz",
	},
	
	:bin => {
		:cat => "cat",
		:df => "df",
		:rm => "rm",
		:mv => "mv",
		:cp => "cp",
		:mkdir => "mkdir",
		:chmod => "chmod",
		:tar => "tar",
		:scp => "scp",
		:rdiff_backup => "rdiff-backup",
		:rsync => "rsync",
		:iptables => "iptables",
		:ip6tables => "ip6tables",
		:git => "git",
		:zfs => "zfs",
		:mount => "mount",
		:umount => "umount",
		:uptime => "uptime",
	},
	
	:vps => {
		:clone => {
			:rsync => "%{rsync} -rlptgoDHX --numeric-ids --inplace --delete-after %{src} %{dst}",
		}
	},
	
	:storage => {
		:method => "Zfs",
		:update_status => true,
	},
	
	:backuper => {
		:method => "RdiffBackup",
		:lock_interval => 30,
		:mountpoint => "/mnt",
		:dest => "/storage/vpsfree.cz/backup",
		:tmp_restore => "/storage/vpsfree.cz/restore",
		:backups_mnt_dir => "/mnt",
		:restore_target => "/mnt/%{node}/%{veid}.restoring",
		:restore_src => "/vz/private/%{veid}.restoring",
		:download => "/storage/vpsfree.cz/download",
		:zfs => {
			:zpool => "storage/vpsfree.cz/backup",
			:rsync => "%{rsync} -rlptgoDHX --numeric-ids --inplace --delete-after --exclude .zfs/ --exclude-from %{exclude} %{src} %{dst}",
		},
		:store => {
			:min_backups => 14,
			:max_backups => 20,
			:max_age => 14,
		},
		:exports => {
			:enabled => true,
			:delimiter => "### vpsAdmin ###",
			:options => "",
			:path => "/etc/exports",
			:reexport => "exportfs -r"
		},
	},
	
	:mailer => {
		:smtp_server => "localhost",
		:smtp_port => 25,
	},
	
	:console => {
		:host => "localhost",
		:port => 8081,
	},
	
	:remote => {
		:socket => "/var/run/vpsadmind.sock",
		:handlers => {
			"VpsAdmin" => [
				"reload",
				"restart",
				"status",
				"stop",
				"update"
			]
		}
	}
}

class AppConfig
	def initialize(file)
		@file = file
		@mutex = Mutex.new
	end
	
	def load
		begin
			tmp = YAML.load(File.read(@file))
		rescue ArgumentError
			$stderr.puts "Error loading config: #{$!.message}"
			return false
		end
		
		unless tmp
			$stderr.puts "Using implicit config, some specific settings (database, server id) are missing, may not work properly"
			@cfg = IMPLICIT_CONFIG
			return true
		end
		
		@cfg = merge(IMPLICIT_CONFIG, tmp)
		
		true
	end
	
	def reload
		sync do
			load
		end
	end
	
	def get(*args)
		val = nil
		
		sync do
			args.each do |k|
				if val
					val = val[k]
				else
					val = @cfg[k]
				end
			end
			
			if block_given?
				yield(args.empty? ? @cfg : val)
				return
			end
		end
		
		val
	end
	
	def merge(src, override)
		src.merge(override) do |k, old_v, new_v|
			if old_v.instance_of?(Hash)
				next new_v if k == :handlers
				
				merge(old_v, new_v)
			else
				new_v
			end
		end
	end
	
	def sync
		@mutex.synchronize do
			yield
		end
	end
end
