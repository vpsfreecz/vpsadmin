# Edit and rename to config.rb

require 'lib/node'
require 'lib/vps'
require 'lib/backuper'
require 'lib/firewall'

module Settings
	DB_HOST = "localhost"
	DB_USER = "vpsadmin"
	DB_PASS = "password"
	DB_NAME = "vpsadmin"
	SERVER_ID = 1
	DOMAIN = "vpsfree.cz"
	NETDEV = "eth0"
	THREADS = 6
	CHECK_INTERVAL = 1
	STATUS_INTERVAL = 300
	DB_RETRY_INTERVAL = 30
	
	UPDATE_VPS_STATUS = true
	
	VZCTL = "/usr/sbin/vzctl"
	VZLIST = "/usr/sbin/vzlist"
	VZQUOTA = "/usr/sbin/vzquota"
	VZMIGRATE = "/usr/sbin/vzmigrate"
	VZ_ROOT = "/vz"
	VZ_CONF = "/etc/vz"
	
	CAT = "/bin/cat"
	DF = "/bin/df"
	RM = "/bin/rm"
	MV = "/bin/mv"
	CP = "/bin/cp"
	MKDIR = "/bin/mkdir"
	SCP = "/usr/bin/scp"
	RDIFF_BACKUP = "/usr/bin/rdiff-backup"
	RSYNC = "/usr/bin/rsync"
	IPTABLES = "/sbin/iptables"
	IP6TABLES = "/sbin/ip6tables"
	
	BACKUPS_MNT_DIR = "/mnt"
	RESTORE_TARGET = "#{VZ_ROOT}/private/%s.restoring"
	
	BACKUPER_LOCK_INTERVAL = 30
	BACKUPER_MOUNTPOINT = "/mnt"
	BACKUPER_DEST = "/storage/vpsfree.cz/vps"
	
	COMMANDS = {
		3 => {:class => "Node", :method => "reboot"},
		4 => {:class => "Node", :method => "sync_templates"},
		1001 => {:class => "VPS", :method => "start"},
		1002 => {:class => "VPS", :method => "stop"},
		1003 => {:class => "VPS", :method => "restart"},
		2002 => {:class => "VPS", :method => "set_params"},
		2003 => {:class => "VPS", :method => "set_params"},
		2004 => {:class => "VPS", :method => "set_params"},
		2005 => {:class => "VPS", :method => "set_params"},
		2006 => {:class => "VPS", :method => "set_params"},
		2007 => {:class => "VPS", :method => "set_params"},
		3001 => {:class => "VPS", :method => "create"},
		3002 => {:class => "VPS", :method => "destroy"},
		3003 => {:class => "VPS", :method => "reinstall"},
		3004 => {:class => "VPS", :method => "clone"},
		4001 => {:class => "VPS", :method => "migrate_offline"},
		4002 => {:class => "VPS", :method => "migrate_online"},
		5003 => {:class => "VPS", :method => "restore"},
		5005 => {:class => "Backuper", :method => "backup"},
		5006 => {:class => "Backuper", :method => "backup"},
		7201 => {:class => "Firewall", :method => "reg_ips"},
		8001 => {:class => "VPS", :method => "features"},
	}
end
