require 'rubygems'
require 'yaml'

$APP_CONFIG = {}

def read_cfg(path)
	YAML.load(File.read(path))
end

def load_cfg(path)
	$APP_CONFIG = read_cfg(path)
end

def reload_cfg(path)
	cfg = read_cfg(path)
	$APP_CONFIG[:vpsadmin][:threads] = cfg[:vpsadmin][:threads]
end
