require 'rubygems'
require 'yaml'

$APP_CONFIG = {}

def load_cfg(path)
	raw_config = File.read(path)
	$APP_CONFIG = YAML.load(raw_config)
end
